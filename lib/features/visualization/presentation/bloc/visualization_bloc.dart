import 'dart:async';

import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/build_graph.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';

/// BLoC que orquesta la construcción y posicionamiento del grafo de
/// visualización.
///
/// Responsabilidades:
/// - Procesar [BuildGraphRequested]: construir el grafo desde el repositorio,
///   luego calcular el layout con Fruchterman-Reingold en un Isolate.
/// - Debounce de 1s para evitar reconstrucciones excesivas durante
///   escaneos BLE rápidos (múltiples detecciones por segundo).
/// - Position cache: almacena el último [LayoutResult] y lo reutiliza
///   como priorLayout en el siguiente cálculo, reduciendo iteraciones
///   de FR de 100 a 30.
/// - Gestionar selección/deselección de nodos para el tooltip.
///
/// Usa [BuildGraph] para obtener nodos y aristas desde el repositorio,
/// y [CalculateLayout] para ejecutar Fruchterman-Reingold en un Isolate.
///
/// Estrategia de debounce: usa un contador de secuencia (_debounceSeq).
/// Cada BuildGraphRequested incrementa el contador. El handler espera
/// la duración configurada y solo procesa si el número de secuencia
/// no cambió durante la espera (es decir, no llegó un evento más nuevo).
/// Esto evita depender de Timer, que ejecuta el callback fuera del
/// ciclo de vida del event handler de BLoC, causando el error
/// "emit was called after an event handler completed normally".
class VisualizationBloc
    extends Bloc<VisualizationEvent, VisualizationState> {
  final BuildGraph _buildGraph;
  final CalculateLayout _calculateLayout;
  final Duration _debounceDuration;

  /// Cache del último layout calculado. Se reutiliza como [priorLayout]
  /// en la siguiente llamada a CalculateLayout para reducir iteraciones
  /// (100→30) y temperatura inicial, acelerando la convergencia.
  LayoutResult? _lastLayout;

  /// Contador de secuencia para el debounce.
  /// Cada BuildGraphRequested incrementa este contador. El handler
  /// espera la ventana de debounce y solo procesa si el contador
  /// coincide con el valor al inicio de la espera.
  int _debounceSeq = 0;

  /// Hash del último conjunto de nodos procesados, combinando IDs y
  /// niveles de proximidad (RSSI).
  ///
  /// PR7: antes era `Set<int>` (_lastNodeIds) comparando solo IDs.
  /// Ahora incluye el último RSSI de cada nodo en el hash para detectar
  /// cambios de proximidad: si los mismos dispositivos se detectan con
  /// RSSI distinto (el usuario se movió), el grafo debe reconstruirse
  /// para reflejar el nuevo nivel de proximidad en los colores.
  int _lastNodeHash = 0;

  /// Guardia contra builds concurrentes (F1: _isBuilding).
  ///
  /// Cubre el edge case donde el timer de debounce dispara mientras
  /// un build anterior todavía está en vuelo. `true` mientras
  /// [processBuildRequest] está ejecutándose.
  bool _isBuilding = false;

  /// Centro geométrico del cluster de nodos (promedio x,y).
  ///
  /// Se calcula en [processBuildRequest] al recibir el layout final.
  /// GraphView lo usa para centrar la vista en el primer GraphReady
  /// con converged=true (R5.13). Agregado en PR2.
  Offset? _barycenter;

  /// Expone [isBuilding] para tests (F1.2).
  @visibleForTesting
  bool get isBuilding => _isBuilding;

  /// Tamaño fijo del canvas donde se posiciona el grafo.
  /// 2000×2000 píxeles da espacio suficiente para 50+ nodos sin
  /// solapamiento.
  static const _canvasWidth = 2000.0;
  static const _canvasHeight = 2000.0;

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
    // T-PR1-012: Handler para reintentar construcción del grafo tras error.
    on<RetryGraphBuild>(_onRetryGraphBuild);
  }

  /// Aplica debounce a BuildGraphRequested usando un contador de secuencia.
  ///
  /// Problema que resuelve: durante un escaneo BLE, NodeListBloc emite
  /// NodeListLoaded múltiples veces por segundo (cada paquete de
  /// advertisement recibido). Sin debounce, se dispararía una
  /// reconstrucción completa del grafo por cada emisión, saturando
  /// el Isolate y causando lag visual.
  ///
  /// Mecanismo: cada evento incrementa _debounceSeq. El handler espera
  /// _debounceDuration y verifica que el contador no haya cambiado.
  /// Si cambió (llegó otro evento), este handler se descarta y el
  /// nuevo evento tomará el control.
  Future<void> _onBuildGraphRequested(
    BuildGraphRequested event,
    Emitter<VisualizationState> emit,
  ) async {
    // PR7: Dedup con hash de IDs + proximity.
    //
    // Antes (F1) se comparaba solo el Set<int> de node IDs. Esto ignoraba
    // cambios de RSSI/proximidad: si el usuario se movía, los mismos
    // nodos aparecían con distinto RSSI pero el grafo no se actualizaba.
    //
    // Ahora se computa un hash combinando cada (nodeId, lastRssi).
    // Si algún nodo cambió de proximidad (RSSI distinto), el hash
    // cambia y se procesa el build. Si IDs + RSSI son idénticos
    // (escaneo estable), se hace dedup para ahorrar cómputo.
    final currentHash = _computeNodeHash(event.nodes);

    if (_lastNodeHash != 0 && _lastNodeHash == currentHash) {
      return; // Mismos IDs + misma proximidad: dedup
    }

    _lastNodeHash = currentHash;
    _debounceSeq++;
    final int currentSeq = _debounceSeq;

    await Future<void>.delayed(_debounceDuration);

    if (currentSeq != _debounceSeq || isClosed) return;

    await processBuildRequest(event, emit);
  }

  /// PR7: Computa un hash estable combinando IDs de nodo y último RSSI.
  ///
  /// Usa un [Set] de strings `$id:$rssi` para eliminar duplicados (si un
  /// nodo aparece múltiples veces en la lista de entrada, se cuenta una
  /// sola). Luego ordena alfabéticamente para garantizar determinismo
  /// independiente del orden de entrada. Finalmente aplica
  /// [Object.hashAll] sobre la lista ordenada.
  ///
  /// Garantías:
  /// - Mismos IDs + mismo RSSI → mismo hash (dedup efectivo)
  /// - Mismos IDs + distinto RSSI → distinto hash (se reconstruye)
  /// - Nodos duplicados en la lista → mismo hash que sin duplicados
  int _computeNodeHash(List<dynamic> nodes) {
    final keys = <String>{};
    for (final n in nodes) {
      if (n.id == null) continue;
      final rssi = (n.rssiHistory is List && (n.rssiHistory as List).isNotEmpty)
          ? (n.rssiHistory as List).last
          : -100;
      keys.add('${n.id}:$rssi');
    }
    final sorted = keys.toList()..sort();
    return Object.hashAll(sorted);
  }

  /// Procesa la construcción y layout del grafo.
  ///
  /// Flujo:
  /// 1. Emite [GraphBuilding] para que la UI muestre indicador de carga.
  /// 2. Llama a [BuildGraph] para obtener nodos y aristas iniciales
  ///    desde el repositorio (posiciones iniciales circulares).
  /// 3. Llama a [CalculateLayout] con posición cache (si existe) para
  ///    refinar posiciones con Fruchterman-Reingold. La cache reduce
  ///    iteraciones de 100 a 30 y la temperatura inicial, acelerando
  ///    la convergencia para recomputaciones.
  /// 4. Emite [GraphReady] con el resultado, o [GraphError] si falla.
  ///
  /// F1: _isBuilding previene llamados concurrentes — si otro build
  /// está en vuelo, el nuevo request se ignora.
  @visibleForTesting
  Future<void> processBuildRequest(
    BuildGraphRequested event,
    Emitter<VisualizationState> emit,
  ) async {
    // F1: Guardia contra builds concurrentes
    if (_isBuilding) return;
    _isBuilding = true;

    try {
      emit(const GraphBuilding());

      // Paso 1: Construir grafo desde el repositorio.
      // PR2: pasar myDeviceUuid para marcar self-node en el grafo.
      // REQ-SN-01: pasar userName y userColor para el self-node sintético.
      final buildResult = await _buildGraph(
        event.scanSessionId,
        myDeviceUuid: event.myDeviceUuid,
        userName: event.userName,
        userColor: event.userColor,
      );

      final initialLayout = buildResult.fold<LayoutResult?>(
        (failure) {
          emit(GraphError(failure.message));
          return null;
        },
        (layout) => layout,
      );

      if (initialLayout == null) return;

      // F2: Si buildGraph retorna un layout sin nodos, emitir error
      // en lugar de proceder con el cálculo de layout (que también
      // sería vacío). El usuario recibe feedback claro en lugar de
      // un canvas en blanco.
      if (initialLayout.nodes.isEmpty) {
        emit(const GraphError('No se encontraron nodos en la sesión'));
        return;
      }

      // Paso 2: Calcular layout con FR, reusando cache si existe.
      // REQ-GL-03: depth=2000 activa el modo 3D del algoritmo FR,
      // permitiendo que los nodos exploren el eje Z (profundidad).
      final calcResult = await _calculateLayout(
        initialLayout,
        _canvasWidth,
        _canvasHeight,
        depth: 2000.0,
        priorLayout: _lastLayout,
      );

      calcResult.fold(
        (failure) => emit(GraphError(failure.message)),
        (layout) {
          // Cachear layout para el próximo BuildGraphRequested
          _lastLayout = layout;

          // PR2: Calcular barycenter del cluster para auto-centrado (R5.13).
          // Promedio de posiciones (x,y) de todos los nodos.
          _computeBarycenter(layout);

          emit(GraphReady(
            layout,
            barycenter: _barycenter,
          ));
        },
      );
    } finally {
      _isBuilding = false;
    }
  }

  /// El usuario seleccionó un nodo: actualiza el estado para
  /// mostrar el tooltip con información detallada.
  ///
  /// Solo procesa la selección si el estado actual es [GraphReady],
  /// ya que no tiene sentido seleccionar un nodo durante la carga
  /// o en estado de error.
  void _onNodeSelected(
    NodeSelected event,
    Emitter<VisualizationState> emit,
  ) {
    final currentState = state;
    if (currentState is GraphReady) {
      emit(GraphReady(
        currentState.layout,
        selectedNodeId: event.nodeId,
        barycenter: currentState.barycenter,
      ));
    }
  }

  /// El usuario cerró el tooltip tocando fuera del grafo.
  ///
  /// Restaura el grafo sin selección activa, preservando el
  /// mismo layout (sin recalcular posiciones).
  void _onNodeDeselected(
    NodeDeselected event,
    Emitter<VisualizationState> emit,
  ) {
    final currentState = state;
    if (currentState is GraphReady) {
      emit(GraphReady(currentState.layout,
          barycenter: currentState.barycenter));
    }
  }

  /// Reintenta la construcción del grafo después de un error.
  ///
  /// QUÉ: convierte [RetryGraphBuild] en un nuevo [BuildGraphRequested]
  /// con los mismos parámetros originales y lo procesa con el pipeline
  /// normal de construcción (debounce + build + layout).
  ///
  /// POR QUÉ: T-PR1-012 — antes no existía este mecanismo. Cuando
  /// el grafo fallaba (GraphError), no había forma de reintentar
  /// desde la UI. El usuario quedaba atrapado en el mensaje de error.
  ///
  /// PR7: preserva [myDeviceUuid] del evento original para que el
  /// self-node siga marcado correctamente tras el reintento.
  ///
  /// Solo procesa si el estado actual es [GraphError] — no tiene
  /// sentido reintentar desde otros estados.
  void _onRetryGraphBuild(
    RetryGraphBuild event,
    Emitter<VisualizationState> emit,
  ) {
    if (state is! GraphError) return;

    // Redispatch como un BuildGraphRequested normal, que pasará
    // por el pipeline completo: debounce → build → layout.
    // PR7: preservar myDeviceUuid del evento original.
    // REQ-SN-01: preservar userName y userColor para el self-node.
    add(BuildGraphRequested(
      scanSessionId: event.lastSessionId,
      nodes: event.lastNodes,
      myDeviceUuid: event.myDeviceUuid,
      userName: event.userName,
      userColor: event.userColor,
    ));
  }

  /// Calcula el barycenter (centro de referencia) del cluster de nodos.
  ///
  /// REQ-SN-02: si existe un self-node (isSelf=true), usa su posición
  /// como barycenter. El self-node está anclado al centro del canvas
  /// y es el punto de referencia natural (el usuario es el centro de su red).
  /// Fallback: promedio aritmético de todos los nodos (centroide).
  /// Si no hay nodos, usa (0, 0).
  ///
  /// Este valor se usa en GraphView para centrar la vista automáticamente
  /// en el primer GraphReady (R5.13).
  void _computeBarycenter(LayoutResult layout) {
    if (layout.nodes.isEmpty) {
      _barycenter = Offset.zero;
      return;
    }

    // Buscar self-node — su posición es el centro de referencia ideal
    for (final node in layout.nodes) {
      if (node.isSelf) {
        _barycenter = Offset(node.x, node.y);
        return;
      }
    }

    // Fallback: centroide de todos los nodos
    double sumX = 0, sumY = 0;
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
