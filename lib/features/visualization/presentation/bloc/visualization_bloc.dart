import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_layout_snapshot.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/build_graph.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/services/graph_layout_physics.dart';

/// Tick interno de la simulación física.
///
/// No forma parte de la API pública de interacción del grafo.
class _PhysicsTick extends VisualizationEvent {
  const _PhysicsTick();
}

/// Notifica que cambió el snapshot distribuido almacenado en
/// `remote_relations`.
///
/// Es un evento interno. Su única responsabilidad es solicitar una
/// reconstrucción del grafo utilizando el último contexto conocido.
class _RemoteRelationsChanged extends VisualizationEvent {
  const _RemoteRelationsChanged();
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
///
/// Además observa [RemoteRelationRepository] para reconstruir el grafo
/// cuando cambia la topología distribuida recibida mediante Graph Exchange.
class VisualizationBloc extends Bloc<VisualizationEvent, VisualizationState> {
  final BuildGraph _buildGraph;
  final CalculateLayout _calculateLayout;
  final RemoteRelationRepository _remoteRelationRepository;
  final Duration _debounceDuration;

  LayoutResult? _lastLayout;
  int _layoutRevision = 0;

  int _debounceSeq = 0;
  int _lastNodeHash = 0;

  bool _isBuilding = false;

  /// Última solicitud pública de construcción conocida.
  ///
  /// Permite reconstruir el mismo grafo cuando cambia `remote_relations`
  /// sin depender de que la UI vuelva a emitir BuildGraphRequested.
  BuildGraphRequested? _lastBuildRequest;

  /// Suscripción a los snapshots distribuidos.
  StreamSubscription<dynamic>? _remoteRelationsSubscription;

  /// Evita reconstruir inmediatamente por la emisión inicial de Drift.
  ///
  /// `watchAll()` normalmente emite el estado actual apenas comienza la
  /// escucha. Esa primera emisión no representa necesariamente un cambio
  /// ocurrido después de construir el grafo.
  bool _receivedInitialRemoteSnapshot = false;

  /// Nodo fijado actualmente por el dedo.
  int? _draggedNodeId;

  final GraphLayoutPhysics _physics = GraphLayoutPhysics();

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

  /// ~30 FPS es suficiente para este tipo de grafo y reduce trabajo
  /// innecesario frente a una simulación de 60 FPS.
  static const Duration _physicsInterval = Duration(milliseconds: 33);

  static const int _settledTicksRequired = 10;

  VisualizationBloc({
    required BuildGraph buildGraph,
    required CalculateLayout calculateLayout,
    required RemoteRelationRepository remoteRelationRepository,
    Duration debounceDuration = const Duration(seconds: 1),
  }) : _buildGraph = buildGraph,
       _calculateLayout = calculateLayout,
       _remoteRelationRepository = remoteRelationRepository,
       _debounceDuration = debounceDuration,
       super(const VisualizationInitial()) {
    on<BuildGraphRequested>(_onBuildGraphRequested);

    on<_RemoteRelationsChanged>(_onRemoteRelationsChanged);

    on<NodeSelected>(_onNodeSelected);
    on<NodeDeselected>(_onNodeDeselected);

    on<NodeDetailsToggled>(_onNodeDetailsToggled);
    on<NodeDetailsDismissed>(_onNodeDetailsDismissed);

    on<NodeDragStarted>(_onNodeDragStarted);
    on<NodeDragUpdated>(_onNodeDragUpdated);
    on<NodeDragEnded>(_onNodeDragEnded);

    on<_PhysicsTick>(_onPhysicsTick);

    on<RetryGraphBuild>(_onRetryGraphBuild);

    _observeRemoteRelations();
  }

  /// Observa cambios en los snapshots distribuidos.
  ///
  /// Drift emite inicialmente el contenido actual de la tabla. Esa primera
  /// emisión se utiliza únicamente para inicializar la observación.
  ///
  /// Las emisiones posteriores representan cambios que pueden modificar
  /// la topología visible.
  void _observeRemoteRelations() {
    _remoteRelationsSubscription = _remoteRelationRepository.watchAll().listen(
      (_) {
        if (!_receivedInitialRemoteSnapshot) {
          _receivedInitialRemoteSnapshot = true;
          return;
        }

        if (!isClosed) {
          add(const _RemoteRelationsChanged());
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint(
            'VisualizationBloc: error observando remote_relations: $error',
          );
        }
      },
    );
  }

  Future<void> _onBuildGraphRequested(
    BuildGraphRequested event,
    Emitter<VisualizationState> emit,
  ) async {
    // Guardamos siempre el contexto más reciente aunque el hash de nodos
    // indique que no hace falta reconstruir en este instante.
    _lastBuildRequest = event;

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

  /// Reconstruye el grafo cuando cambia `remote_relations`.
  ///
  /// Esta ruta NO utiliza `_lastNodeHash`, porque un cambio distribuido puede
  /// modificar nodos/aristas sin alterar la lista BLE recibida desde la UI.
  ///
  /// Tampoco aplica el debounce BLE de un segundo: el cambio remoto ya fue
  /// consolidado previamente como snapshot válido en SQLite.
  Future<void> _onRemoteRelationsChanged(
    _RemoteRelationsChanged event,
    Emitter<VisualizationState> emit,
  ) async {
    final lastRequest = _lastBuildRequest;

    if (lastRequest == null) {
      return;
    }

    // Invalida cualquier BuildGraphRequested que todavía esté esperando
    // dentro del debounce.
    _debounceSeq++;

    await processBuildRequest(lastRequest, emit);
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

      final detailsNodeId = currentState is GraphReady
          ? currentState.detailsNodeId
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

      if (topologyChanged) {
        _layoutRevision++;
      }

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

          _physics.removeStaleData(layout);

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

          final preservedDetails =
              detailsNodeId != null && _containsNode(layout, detailsNodeId)
              ? detailsNodeId
              : null;

          emit(
            GraphReady(
              layout,
              snapshot: GraphLayoutSnapshot(
                layout: layout,
                revision: _layoutRevision,
              ),
              selectedNodeId: preservedSelection,
              detailsNodeId: preservedDetails,
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
    _physics.beginDrag(currentState.layout, event.nodeId);

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
        .clamp(
          GraphLayoutPhysics.canvasMargin,
          _canvasWidth - GraphLayoutPhysics.canvasMargin,
        )
        .toDouble();

    final y = event.y
        .clamp(
          GraphLayoutPhysics.canvasMargin,
          _canvasHeight - GraphLayoutPhysics.canvasMargin,
        )
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

    _physics.resetVelocity(event.nodeId);

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
        snapshot: GraphLayoutSnapshot(
          layout: updatedLayout,
          revision: currentState.snapshot.revision,
        ),
        selectedNodeId: currentState.selectedNodeId,
        detailsNodeId: currentState.detailsNodeId,
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
    _physics.stop();
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

    final step = _physics.tick(layout, draggedNodeId: _draggedNodeId);
    final updatedLayout = step.layout;
    _lastLayout = updatedLayout;

    emit(
      GraphReady(
        updatedLayout,
        snapshot: GraphLayoutSnapshot(
          layout: updatedLayout,
          revision: currentState.snapshot.revision,
        ),
        selectedNodeId: currentState.selectedNodeId,
        detailsNodeId: currentState.detailsNodeId,
        barycenter: currentState.barycenter,
      ),
    );

    if (_draggedNodeId != null) {
      _settledTicks = 0;
      return;
    }

    if (step.maxSpeed < GraphLayoutPhysics.settledSpeed) {
      _settledTicks++;
    } else {
      _settledTicks = 0;
    }

    if (_settledTicks >= _settledTicksRequired) {
      _stopPhysics();
    }
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

  String _edgeKey(GraphEdge edge) {
    final first = edge.fromId < edge.toId ? edge.fromId : edge.toId;
    final second = edge.fromId < edge.toId ? edge.toId : edge.fromId;
    return '$first:$second:${edge.edgeType.name}';
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
        snapshot: currentState.snapshot,
        selectedNodeId: event.nodeId,
        detailsNodeId: currentState.detailsNodeId,
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

    emit(
      GraphReady(
        currentState.layout,
        snapshot: currentState.snapshot,
        detailsNodeId: currentState.detailsNodeId,
        barycenter: currentState.barycenter,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // DETAILS
  // ─────────────────────────────────────────────────────────────

  void _onNodeDetailsToggled(
    NodeDetailsToggled event,
    Emitter<VisualizationState> emit,
  ) {
    final currentState = state;

    if (currentState is! GraphReady) {
      return;
    }

    if (!_containsNode(currentState.layout, event.nodeId)) {
      return;
    }

    final nextDetailsNodeId = currentState.detailsNodeId == event.nodeId
        ? null
        : event.nodeId;

    emit(
      GraphReady(
        currentState.layout,
        snapshot: currentState.snapshot,
        selectedNodeId: currentState.selectedNodeId,
        detailsNodeId: nextDetailsNodeId,
        barycenter: currentState.barycenter,
      ),
    );
  }

  void _onNodeDetailsDismissed(
    NodeDetailsDismissed event,
    Emitter<VisualizationState> emit,
  ) {
    final currentState = state;

    if (currentState is! GraphReady) {
      return;
    }

    if (currentState.detailsNodeId == null) {
      return;
    }

    emit(
      GraphReady(
        currentState.layout,
        snapshot: currentState.snapshot,
        selectedNodeId: currentState.selectedNodeId,
        barycenter: currentState.barycenter,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // RETRY
  // ─────────────────────────────────────────────────────────────

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
  Future<void> close() async {
    _physicsTimer?.cancel();
    _physicsTimer = null;

    await _remoteRelationsSubscription?.cancel();
    _remoteRelationsSubscription = null;

    await super.close();
  }
}
