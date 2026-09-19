import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/build_graph.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';

/// Tick interno de la simulación física.
///
/// No forma parte de la API pública de interacción del grafo.
class _PhysicsTick extends VisualizationEvent {
  const _PhysicsTick();
}

/// Orquesta construcción, actualización e interacción del grafo.
///
/// Existen dos mecanismos de posicionamiento diferentes:
///
/// 1. CalculateLayout / Fruchterman-Reingold:
///    utilizado para la carga inicial y cambios estructurales.
///
/// 2. Simulación incremental:
///    utilizada durante el drag y la relajación posterior.
///
/// `_lastLayout` es siempre la memoria espacial autoritativa.
class VisualizationBloc extends Bloc<VisualizationEvent, VisualizationState> {
  final BuildGraph _buildGraph;
  final CalculateLayout _calculateLayout;
  final Duration _debounceDuration;

  LayoutResult? _lastLayout;

  int _debounceSeq = 0;
  int _lastNodeHash = 0;

  bool _isBuilding = false;

  /// Nodo fijado actualmente por el dedo.
  int? _draggedNodeId;

  /// Velocidad actual de cada nodo.
  final Map<int, Offset> _velocities = <int, Offset>{};

  /// Longitud de reposo de cada resorte.
  ///
  /// Se captura al comenzar una interacción para que el grafo intente
  /// conservar aproximadamente su geometría anterior en vez de colapsar
  /// hacia una distancia arbitraria.
  final Map<String, double> _springRestLengths = <String, double>{};

  Timer? _physicsTimer;

  /// Cantidad de ticks consecutivos con movimiento prácticamente nulo.
  int _settledTicks = 0;

  Offset? _barycenter;

  @visibleForTesting
  bool get isBuilding => _isBuilding;

  @visibleForTesting
  int? get draggedNodeId => _draggedNodeId;

  static const double _canvasWidth = 2000.0;
  static const double _canvasHeight = 2000.0;
  static const double _canvasDepth = 2000.0;

  static const double _canvasMargin = 30.0;

  /// ~30 FPS es suficiente para este tipo de grafo y reduce trabajo
  /// innecesario frente a una simulación de 60 FPS.
  static const Duration _physicsInterval = Duration(milliseconds: 33);

  /// Intensidad de los resortes.
  static const double _directSpringStrength = 0.020;
  static const double _transitiveSpringStrength = 0.008;

  /// Amortiguación de velocidad.
  ///
  /// Cuanto menor sea, antes se detendrá el sistema.
  static const double _damping = 0.82;

  /// Límite de velocidad por tick para evitar explosiones numéricas.
  static const double _maxSpeed = 24.0;

  /// Repulsión local para evitar que dos nodos terminen exactamente
  /// superpuestos durante la relajación.
  static const double _repulsionDistance = 90.0;
  static const double _repulsionStrength = 0.035;

  /// Umbral para considerar que el sistema prácticamente se detuvo.
  static const double _settledSpeed = 0.12;

  static const int _settledTicksRequired = 10;

  VisualizationBloc({
    required BuildGraph buildGraph,
    required CalculateLayout calculateLayout,
    Duration debounceDuration = const Duration(seconds: 1),
  }) : _buildGraph = buildGraph,
       _calculateLayout = calculateLayout,
       _debounceDuration = debounceDuration,
       super(const VisualizationInitial()) {
    on<BuildGraphRequested>(_onBuildGraphRequested);

    on<NodeSelected>(_onNodeSelected);
    on<NodeDeselected>(_onNodeDeselected);

    on<NodeDragStarted>(_onNodeDragStarted);
    on<NodeDragUpdated>(_onNodeDragUpdated);
    on<NodeDragEnded>(_onNodeDragEnded);

    on<_PhysicsTick>(_onPhysicsTick);

    on<RetryGraphBuild>(_onRetryGraphBuild);
  }

  Future<void> _onBuildGraphRequested(
    BuildGraphRequested event,
    Emitter<VisualizationState> emit,
  ) async {
    final currentHash = _computeNodeHash(event.nodes);

    if (_lastNodeHash != 0 && _lastNodeHash == currentHash) {
      return;
    }

    _lastNodeHash = currentHash;

    _debounceSeq++;

    final currentSeq = _debounceSeq;

    await Future<void>.delayed(_debounceDuration);

    if (currentSeq != _debounceSeq || isClosed) {
      return;
    }

    await processBuildRequest(event, emit);
  }

  int _computeNodeHash(List<dynamic> nodes) {
    final keys = <String>{};

    for (final node in nodes) {
      if (node.id == null) {
        continue;
      }

      final rssi =
          node.rssiHistory is List && (node.rssiHistory as List).isNotEmpty
          ? (node.rssiHistory as List).last
          : -100;

      keys.add('${node.id}:$rssi');
    }

    final sorted = keys.toList()..sort();

    return Object.hashAll(sorted);
  }

  @visibleForTesting
  Future<void> processBuildRequest(
    BuildGraphRequested event,
    Emitter<VisualizationState> emit,
  ) async {
    if (_isBuilding) {
      return;
    }

    _isBuilding = true;

    try {
      final previousLayout = _lastLayout;
      final currentState = state;

      final isInitialBuild =
          previousLayout == null || currentState is VisualizationInitial;

      final selectedNodeId = currentState is GraphReady
          ? currentState.selectedNodeId
          : null;

      if (isInitialBuild) {
        emit(const GraphBuilding());
      }

      final buildResult = await _buildGraph(
        event.scanSessionId,
        myDeviceUuid: event.myDeviceUuid,
        userName: event.userName,
        userColor: event.userColor,
      );

      final initialLayout = buildResult.fold<LayoutResult?>((failure) {
        emit(GraphError(failure.message));
        return null;
      }, (layout) => layout);

      if (initialLayout == null) {
        return;
      }

      if (initialLayout.nodes.isEmpty) {
        emit(const GraphError('No se encontraron nodos en la sesión'));
        return;
      }

      final topologyChanged =
          previousLayout == null ||
          _hasTopologyChanged(previous: previousLayout, current: initialLayout);

      final calcResult = await _calculateLayout(
        initialLayout,
        _canvasWidth,
        _canvasHeight,
        depth: _canvasDepth,
        priorLayout: previousLayout,
        stabilize: topologyChanged,
      );

      calcResult.fold(
        (failure) {
          emit(GraphError(failure.message));
        },
        (layout) {
          _lastLayout = layout;

          _removeStalePhysicsData(layout);

          final activeDraggedNodeId = _draggedNodeId;

          if (activeDraggedNodeId != null &&
              !_containsNode(layout, activeDraggedNodeId)) {
            _draggedNodeId = null;
          }

          _computeBarycenter(layout);

          final preservedSelection =
              selectedNodeId != null && _containsNode(layout, selectedNodeId)
              ? selectedNodeId
              : null;

          emit(
            GraphReady(
              layout,
              selectedNodeId: preservedSelection,
              barycenter: _barycenter,
            ),
          );

          if (kDebugMode) {
            debugPrint(
              topologyChanged
                  ? 'VisualizationBloc: topology changed; layout stabilized.'
                  : 'VisualizationBloc: metadata-only refresh; '
                        'positions preserved.',
            );
          }
        },
      );
    } finally {
      _isBuilding = false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DRAG
  // ─────────────────────────────────────────────────────────────

  void _onNodeDragStarted(
    NodeDragStarted event,
    Emitter<VisualizationState> emit,
  ) {
    final currentState = state;

    if (currentState is! GraphReady) {
      return;
    }

    if (!_containsNode(currentState.layout, event.nodeId)) {
      return;
    }

    _draggedNodeId = event.nodeId;

    // El nodo agarrado no debe conservar velocidad anterior.
    _velocities[event.nodeId] = Offset.zero;

    _captureSpringRestLengths(currentState.layout);

    _settledTicks = 0;

    _startPhysics();
  }

  void _onNodeDragUpdated(
    NodeDragUpdated event,
    Emitter<VisualizationState> emit,
  ) {
    final currentState = state;

    if (currentState is! GraphReady) {
      return;
    }

    if (_draggedNodeId != event.nodeId) {
      return;
    }

    final x = event.x
        .clamp(_canvasMargin, _canvasWidth - _canvasMargin)
        .toDouble();

    final y = event.y
        .clamp(_canvasMargin, _canvasHeight - _canvasMargin)
        .toDouble();

    var nodeFound = false;

    final updatedNodes = currentState.layout.nodes
        .map((node) {
          if (node.id != event.nodeId) {
            return node;
          }

          nodeFound = true;

          return node.copyWith(x: x, y: y);
        })
        .toList(growable: false);

    if (!nodeFound) {
      _draggedNodeId = null;
      return;
    }

    _velocities[event.nodeId] = Offset.zero;

    final updatedLayout = LayoutResult(
      nodes: updatedNodes,
      edges: currentState.layout.edges,
      iterations: currentState.layout.iterations,
      converged: false,
    );

    _lastLayout = updatedLayout;

    emit(
      GraphReady(
        updatedLayout,
        selectedNodeId: currentState.selectedNodeId,
        barycenter: currentState.barycenter,
      ),
    );
  }

  void _onNodeDragEnded(NodeDragEnded event, Emitter<VisualizationState> emit) {
    if (_draggedNodeId != event.nodeId) {
      return;
    }

    _draggedNodeId = null;
    _settledTicks = 0;

    // No detenemos el timer:
    // la red continúa relajándose después de soltar.
    _startPhysics();
  }

  // ─────────────────────────────────────────────────────────────
  // LIVE PHYSICS
  // ─────────────────────────────────────────────────────────────

  void _startPhysics() {
    if (_physicsTimer?.isActive ?? false) {
      return;
    }

    _physicsTimer = Timer.periodic(_physicsInterval, (_) {
      if (!isClosed) {
        add(const _PhysicsTick());
      }
    });
  }

  void _stopPhysics() {
    _physicsTimer?.cancel();
    _physicsTimer = null;

    _settledTicks = 0;

    _velocities.removeWhere(
      (nodeId, velocity) => velocity.distance < _settledSpeed,
    );
  }

  void _onPhysicsTick(_PhysicsTick event, Emitter<VisualizationState> emit) {
    final currentState = state;
    final layout = _lastLayout;

    if (currentState is! GraphReady || layout == null) {
      _stopPhysics();
      return;
    }

    if (layout.nodes.length < 2) {
      if (_draggedNodeId == null) {
        _stopPhysics();
      }

      return;
    }

    final nodesById = <int, dynamic>{};

    for (final node in layout.nodes) {
      final id = node.id;

      if (id != null) {
        nodesById[id] = node;
      }
    }

    final forces = <int, Offset>{};

    for (final id in nodesById.keys) {
      forces[id] = Offset.zero;
    }

    _applySpringForces(layout: layout, nodesById: nodesById, forces: forces);

    _applyRepulsion(nodesById: nodesById, forces: forces);

    var maxSpeed = 0.0;

    final updatedNodes = layout.nodes
        .map((node) {
          final id = node.id;

          if (id == null) {
            return node;
          }

          // El nodo agarrado está fijado exactamente al dedo.
          if (id == _draggedNodeId) {
            _velocities[id] = Offset.zero;
            return node;
          }

          final force = forces[id] ?? Offset.zero;
          final previousVelocity = _velocities[id] ?? Offset.zero;

          var velocity = Offset(
            (previousVelocity.dx + force.dx) * _damping,
            (previousVelocity.dy + force.dy) * _damping,
          );

          velocity = _limitVector(velocity, _maxSpeed);

          if (velocity.distance < 0.01) {
            velocity = Offset.zero;
          }

          _velocities[id] = velocity;

          maxSpeed = math.max(maxSpeed, velocity.distance);

          if (velocity == Offset.zero) {
            return node;
          }

          final newX = (node.x + velocity.dx)
              .clamp(_canvasMargin, _canvasWidth - _canvasMargin)
              .toDouble();

          final newY = (node.y + velocity.dy)
              .clamp(_canvasMargin, _canvasHeight - _canvasMargin)
              .toDouble();

          return node.copyWith(x: newX, y: newY);
        })
        .toList(growable: false);

    final updatedLayout = LayoutResult(
      nodes: updatedNodes,
      edges: layout.edges,
      iterations: layout.iterations,
      converged: _draggedNodeId == null && maxSpeed < _settledSpeed,
    );

    _lastLayout = updatedLayout;

    emit(
      GraphReady(
        updatedLayout,
        selectedNodeId: currentState.selectedNodeId,
        barycenter: currentState.barycenter,
      ),
    );

    if (_draggedNodeId != null) {
      _settledTicks = 0;
      return;
    }

    if (maxSpeed < _settledSpeed) {
      _settledTicks++;
    } else {
      _settledTicks = 0;
    }

    if (_settledTicks >= _settledTicksRequired) {
      _stopPhysics();
    }
  }

  /// Aplica Hooke simplificado sobre las aristas.
  ///
  /// direct:
  ///   vínculo más fuerte.
  ///
  /// transitive:
  ///   vínculo más suave.
  void _applySpringForces({
    required LayoutResult layout,
    required Map<int, dynamic> nodesById,
    required Map<int, Offset> forces,
  }) {
    for (final edge in layout.edges) {
      final from = nodesById[edge.fromId];
      final to = nodesById[edge.toId];

      if (from == null || to == null) {
        continue;
      }

      final dx = to.x - from.x;
      final dy = to.y - from.y;

      final distanceSquared = dx * dx + dy * dy;

      if (distanceSquared < 0.0001) {
        continue;
      }

      final distance = math.sqrt(distanceSquared);

      final direction = Offset(dx / distance, dy / distance);

      final restLength =
          _springRestLengths[_edgeKey(edge)] ??
          distance.clamp(80.0, 500.0).toDouble();

      final displacement = distance - restLength;

      final springStrength = edge.edgeType == EdgeType.direct
          ? _directSpringStrength
          : _transitiveSpringStrength;

      // thickness aporta ligeramente más influencia, sin convertir
      // las aristas gruesas en resortes excesivamente agresivos.
      final thicknessMultiplier =
          1.0 + ((edge.thickness - 1.0).clamp(0.0, 2.0) * 0.12);

      final magnitude = displacement * springStrength * thicknessMultiplier;

      final force = direction * magnitude;

      forces[edge.fromId] = (forces[edge.fromId] ?? Offset.zero) + force;

      forces[edge.toId] = (forces[edge.toId] ?? Offset.zero) - force;
    }
  }

  /// Repulsión local.
  ///
  /// No intenta reemplazar Fruchterman-Reingold. Su único objetivo es
  /// impedir que nodos cercanos terminen visualmente uno encima del otro.
  void _applyRepulsion({
    required Map<int, dynamic> nodesById,
    required Map<int, Offset> forces,
  }) {
    final entries = nodesById.entries.toList(growable: false);

    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final first = entries[i];
        final second = entries[j];

        final dx = second.value.x - first.value.x;
        final dy = second.value.y - first.value.y;

        final distanceSquared = dx * dx + dy * dy;

        if (distanceSquared < 0.0001) {
          continue;
        }

        final distance = math.sqrt(distanceSquared);

        if (distance >= _repulsionDistance) {
          continue;
        }

        final direction = Offset(dx / distance, dy / distance);

        final overlap = _repulsionDistance - distance;

        final magnitude = overlap * _repulsionStrength;

        final force = direction * magnitude;

        forces[first.key] = (forces[first.key] ?? Offset.zero) - force;

        forces[second.key] = (forces[second.key] ?? Offset.zero) + force;
      }
    }
  }

  void _captureSpringRestLengths(LayoutResult layout) {
    final nodesById = <int, dynamic>{};

    for (final node in layout.nodes) {
      final id = node.id;

      if (id != null) {
        nodesById[id] = node;
      }
    }

    for (final edge in layout.edges) {
      final from = nodesById[edge.fromId];
      final to = nodesById[edge.toId];

      if (from == null || to == null) {
        continue;
      }

      final dx = to.x - from.x;
      final dy = to.y - from.y;

      final distance = math.sqrt(dx * dx + dy * dy);

      _springRestLengths[_edgeKey(edge)] = distance
          .clamp(60.0, 600.0)
          .toDouble();
    }
  }

  String _edgeKey(GraphEdge edge) {
    final first = math.min(edge.fromId, edge.toId);
    final second = math.max(edge.fromId, edge.toId);

    return '$first:$second:${edge.edgeType.name}';
  }

  Offset _limitVector(Offset vector, double maximum) {
    final magnitude = vector.distance;

    if (magnitude <= maximum || magnitude == 0) {
      return vector;
    }

    final factor = maximum / magnitude;

    return Offset(vector.dx * factor, vector.dy * factor);
  }

  void _removeStalePhysicsData(LayoutResult layout) {
    final ids = _nodeIds(layout);

    _velocities.removeWhere((id, _) => !ids.contains(id));

    final validEdges = _edgeKeys(layout.edges);

    _springRestLengths.removeWhere((key, _) => !validEdges.contains(key));
  }

  // ─────────────────────────────────────────────────────────────
  // TOPOLOGY
  // ─────────────────────────────────────────────────────────────

  bool _hasTopologyChanged({
    required LayoutResult previous,
    required LayoutResult current,
  }) {
    final previousNodeIds = _nodeIds(previous);
    final currentNodeIds = _nodeIds(current);

    if (!_sameSet(previousNodeIds, currentNodeIds)) {
      return true;
    }

    final previousEdges = _edgeKeys(previous.edges);
    final currentEdges = _edgeKeys(current.edges);

    return !_sameSet(previousEdges, currentEdges);
  }

  Set<int> _nodeIds(LayoutResult layout) {
    final result = <int>{};

    for (final node in layout.nodes) {
      final id = node.id;

      if (id != null) {
        result.add(id);
      }
    }

    return result;
  }

  Set<String> _edgeKeys(List<GraphEdge> edges) {
    final result = <String>{};

    for (final edge in edges) {
      result.add(_edgeKey(edge));
    }

    return result;
  }

  bool _sameSet<T>(Set<T> first, Set<T> second) {
    if (first.length != second.length) {
      return false;
    }

    return first.containsAll(second);
  }

  bool _containsNode(LayoutResult layout, int nodeId) {
    for (final node in layout.nodes) {
      if (node.id == nodeId) {
        return true;
      }
    }

    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // SELECTION
  // ─────────────────────────────────────────────────────────────

  void _onNodeSelected(NodeSelected event, Emitter<VisualizationState> emit) {
    final currentState = state;

    if (currentState is! GraphReady) {
      return;
    }

    emit(
      GraphReady(
        currentState.layout,
        selectedNodeId: event.nodeId,
        barycenter: currentState.barycenter,
      ),
    );
  }

  void _onNodeDeselected(
    NodeDeselected event,
    Emitter<VisualizationState> emit,
  ) {
    final currentState = state;

    if (currentState is! GraphReady) {
      return;
    }

    emit(GraphReady(currentState.layout, barycenter: currentState.barycenter));
  }

  void _onRetryGraphBuild(
    RetryGraphBuild event,
    Emitter<VisualizationState> emit,
  ) {
    if (state is! GraphError) {
      return;
    }

    add(
      BuildGraphRequested(
        scanSessionId: event.lastSessionId,
        nodes: event.lastNodes,
        myDeviceUuid: event.myDeviceUuid,
        userName: event.userName,
        userColor: event.userColor,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BARYCENTER
  // ─────────────────────────────────────────────────────────────

  void _computeBarycenter(LayoutResult layout) {
    if (layout.nodes.isEmpty) {
      _barycenter = Offset.zero;
      return;
    }

    for (final node in layout.nodes) {
      if (node.isSelf) {
        _barycenter = Offset(node.x, node.y);
        return;
      }
    }

    double sumX = 0.0;
    double sumY = 0.0;

    for (final node in layout.nodes) {
      sumX += node.x;
      sumY += node.y;
    }

    _barycenter = Offset(
      sumX / layout.nodes.length,
      sumY / layout.nodes.length,
    );
  }

  @override
  Future<void> close() {
    _physicsTimer?.cancel();
    _physicsTimer = null;

    return super.close();
  }
}
