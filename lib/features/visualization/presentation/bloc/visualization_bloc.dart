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

  /// Último conjunto de IDs de nodo procesados.
  /// Se usa para evitar reconstrucciones cuando los mismos dispositivos
  /// se anuncian repetidamente durante el escaneo continuo (F1: dedup).
  final Set<int> _lastNodeIds = {};

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

  /// Indica si el conjunto de IDs de nodo del evento actual coincide
  /// exactamente con el último conjunto procesado.
  ///
  /// Usa [Set.equals] para comparación semántica en vez de comparar
  /// longitud + containsAll (equivalente pero más verboso).
  /// PR2: extraído a getter privado para claridad (R5.16).
  bool _nodeIdsStable(Set<int> currentIds) {
    return _lastNodeIds.length == currentIds.length &&
        _lastNodeIds.containsAll(currentIds);
  }

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
    // F1: Dedup por IDs de nodo — si los mismos dispositivos se anuncian
    // repetidamente, no reiniciar el contador de debounce. Esto previene
    // el starvation: durante escaneo continuo, cada paquete de advertisement
    // disparaba BuildGraphRequested con los mismos nodos, reseteando el
    // debounce y evitando que el grafo se construya.
    final currentIds = event.nodes
        .where((n) => n.id != null)
        .map((n) => n.id!)
        .toSet();

    // PR2: _nodeIdsStable usa lógica de Set.equals para claridad
    if (_lastNodeIds.isNotEmpty && _nodeIdsStable(currentIds)) {
      return; // Mismos nodos que el request anterior: ignorar
    }

    // Actualizar el cache de últimos IDs ANTES de incrementar el contador
    _lastNodeIds
      ..clear()
      ..addAll(currentIds);
    _debounceSeq++;
    final int currentSeq = _debounceSeq;

    await Future<void>.delayed(_debounceDuration);

    if (currentSeq != _debounceSeq || isClosed) return;

    await processBuildRequest(event, emit);
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
      final buildResult = await _buildGraph(
        event.scanSessionId,
        myDeviceUuid: event.myDeviceUuid,
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

      // Paso 2: Calcular layout con FR, reusando cache si existe
      final calcResult = await _calculateLayout(
        initialLayout,
        _canvasWidth,
        _canvasHeight,
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

  /// PR2: Calcula el barycenter (centro geométrico) del cluster de nodos.
  ///
  /// El barycenter es el promedio aritmético de las posiciones (x, y)
  /// de todos los nodos en el layout. Si no hay nodos, se usa (0, 0).
  /// Este valor se usa en GraphView para centrar la vista automáticamente
  /// en el primer GraphReady (R5.13).
  void _computeBarycenter(LayoutResult layout) {
    if (layout.nodes.isEmpty) {
      _barycenter = Offset.zero;
      return;
    }
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
