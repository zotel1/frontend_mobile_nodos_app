import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/build_graph.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';

/// Orquesta la construcción, actualización e interacción del grafo.
///
/// El grafo se trata como una estructura visual persistente:
///
/// - la primera carga realiza un layout completo;
/// - las actualizaciones BLE conservan las posiciones conocidas;
/// - cambios de RSSI/metadata no ejecutan física;
/// - un cambio real de topología puede estabilizar el layout;
/// - GraphBuilding solo aparece cuando todavía no existe un grafo visible;
/// - el movimiento manual actualiza la misma memoria espacial utilizada
///   posteriormente por los refresh BLE.
///
/// `_lastLayout` representa la memoria espacial autoritativa del grafo.
class VisualizationBloc extends Bloc<VisualizationEvent, VisualizationState> {
  final BuildGraph _buildGraph;
  final CalculateLayout _calculateLayout;
  final Duration _debounceDuration;

  /// Último layout visible y memoria espacial autoritativa.
  LayoutResult? _lastLayout;

  /// Secuencia para debounce de actualizaciones BLE.
  int _debounceSeq = 0;

  /// Último hash BLE observado.
  ///
  /// Se utiliza exclusivamente para ignorar actualizaciones idénticas.
  int _lastNodeHash = 0;

  /// Evita dos construcciones simultáneas.
  bool _isBuilding = false;

  /// Nodo actualmente agarrado mediante long press.
  ///
  /// null cuando no existe drag activo.
  int? _draggedNodeId;

  /// Centro de referencia del grafo.
  Offset? _barycenter;

  @visibleForTesting
  bool get isBuilding => _isBuilding;

  @visibleForTesting
  int? get draggedNodeId => _draggedNodeId;

  static const double _canvasWidth = 2000.0;
  static const double _canvasHeight = 2000.0;
  static const double _canvasDepth = 2000.0;

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

    on<RetryGraphBuild>(_onRetryGraphBuild);
  }

  /// Recibe una actualización procedente del scanner BLE.
  ///
  /// El debounce agrupa ráfagas rápidas. La decisión sobre si cambió
  /// realmente la estructura del grafo se realiza posteriormente,
  /// comparando el resultado de BuildGraph contra `_lastLayout`.
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

  /// Hash de ID + RSSI.
  ///
  /// Sirve únicamente para deduplicar eventos BLE exactamente iguales.
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

  /// Construye o actualiza el grafo.
  ///
  /// La topología se determina después de BuildGraph:
  ///
  /// - mismos IDs + mismas aristas:
  ///   actualización de metadata, sin física;
  ///
  /// - cambian IDs o aristas:
  ///   actualización estructural, con estabilización;
  ///
  /// - sin layout anterior:
  ///   layout inicial completo.
  ///
  /// Durante una actualización normal nunca se emite GraphBuilding.
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

          // Si el nodo que estaba siendo arrastrado desapareció del scan,
          // finalizamos el drag automáticamente.
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

  /// Inicia el movimiento manual de un nodo.
  ///
  /// El nodo debe existir en el layout visible.
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
  }

  /// Actualiza la posición del nodo actualmente agarrado.
  ///
  /// Las coordenadas recibidas pertenecen al canvas lógico 2000×2000.
  ///
  /// La posición se limita al canvas y se guarda inmediatamente tanto en:
  ///
  /// - `_lastLayout`, para que sobreviva a refresh BLE posteriores;
  /// - `GraphReady`, para redibujar 2D y 3D desde la misma fuente de verdad.
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

    final x = event.x.clamp(0.0, _canvasWidth).toDouble();
    final y = event.y.clamp(0.0, _canvasHeight).toDouble();

    var nodeFound = false;

    final updatedNodes = currentState.layout.nodes
        .map((node) {
          if (node.id != event.nodeId) {
            return node;
          }

          nodeFound = true;

          return _copyNodeWithPosition(node, x: x, y: y);
        })
        .toList(growable: false);

    if (!nodeFound) {
      _draggedNodeId = null;
      return;
    }

    final updatedLayout = LayoutResult(
      nodes: updatedNodes,
      edges: currentState.layout.edges,
      iterations: currentState.layout.iterations,
      converged: currentState.layout.converged,
    );

    _lastLayout = updatedLayout;

    // No recalculamos barycenter durante cada frame de drag.
    //
    // GraphView solo utiliza barycenter para el centrado inicial, por lo que
    // cambiarlo continuamente no aporta nada y añade trabajo innecesario.
    emit(
      GraphReady(
        updatedLayout,
        selectedNodeId: currentState.selectedNodeId,
        barycenter: currentState.barycenter,
      ),
    );
  }

  /// Finaliza el movimiento manual.
  ///
  /// En esta primera implementación no ejecutamos física al soltar.
  /// La posición queda exactamente donde la dejó el usuario.
  ///
  /// En el siguiente paso este punto servirá para iniciar la relajación
  /// de los nodos conectados.
  void _onNodeDragEnded(NodeDragEnded event, Emitter<VisualizationState> emit) {
    if (_draggedNodeId != event.nodeId) {
      return;
    }

    _draggedNodeId = null;
  }

  /// Crea una copia del nodo modificando únicamente su posición 2D.
  ///
  /// Z y toda la metadata permanecen intactos para mantener paridad con
  /// el modelo utilizado por las vistas 2D y 3D.
  GraphNode _copyNodeWithPosition(
    GraphNode node, {
    required double x,
    required double y,
  }) {
    return GraphNode(
      id: node.id,
      x: x,
      y: y,
      z: node.z,
      proximity: node.proximity,
      name: node.name,
      suggestedName: node.suggestedName,
      connectionCount: node.connectionCount,
      isSelf: node.isSelf,
      connectable: node.connectable,
      userColor: node.userColor,
      estimatedDistance: node.estimatedDistance,
    );
  }

  /// Determina si BuildGraph produjo una topología distinta.
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
      result.add('${edge.fromId}:${edge.toId}:${edge.edgeType.name}');
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

  /// Selecciona un nodo sin recalcular el layout.
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

  /// Elimina la selección sin recalcular el layout.
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

  /// Reintenta la construcción después de un error.
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

  /// Calcula el punto de referencia del grafo.
  ///
  /// El self-node tiene prioridad. Si no existe, se utiliza el centroide.
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
}
