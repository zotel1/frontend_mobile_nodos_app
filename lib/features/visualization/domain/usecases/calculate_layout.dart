import 'dart:math' as math;

import 'package:dartz/dartz.dart';

import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/models/graph_data.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/algorithms/layout_algorithm.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Caso de uso encargado de calcular la distribución espacial del grafo.
///
/// La física concreta se delega a [LayoutAlgorithm]. Esta clase únicamente
/// prepara el estado inicial, reutiliza posiciones previas y determina los
/// parámetros de layout apropiados para el tamaño actual del grafo.
///
/// Tanto 2D como 3D utilizan la misma estrategia de configuración para
/// mantener paridad funcional entre ambas visualizaciones.
class CalculateLayout {
  final LayoutAlgorithm layoutAlgorithm;

  const CalculateLayout({required this.layoutAlgorithm});

  /// Ejecuta el algoritmo de layout sobre [layout].
  ///
  /// [width] y [height] representan el espacio disponible en 2D.
  ///
  /// Si [depth] es mayor que cero, el algoritmo trabaja en modo 3D.
  ///
  /// Cuando existe [priorLayout], las posiciones conocidas se reutilizan
  /// para evitar que el grafo completo cambie de lugar cada vez que aparece
  /// o desaparece un dispositivo.
  ///
  /// Los nodos nuevos conservan la posición inicial proporcionada por el
  /// repositorio y posteriormente son integrados por el algoritmo de fuerzas.
  Future<Either<Failure, LayoutResult>> call(
    LayoutResult layout,
    double width,
    double height, {
    double depth = 0.0,
    LayoutResult? priorLayout,
    int? seed,
  }) async {
    try {
      // El layout actual siempre es la fuente de verdad respecto del
      // conjunto de nodos y aristas.
      //
      // Nunca debemos reemplazarlo directamente por priorLayout porque el
      // cache puede contener menos nodos que el scan actual.
      var source = layout;

      final hasCache = _hasUsableCache(priorLayout);

      if (priorLayout != null) {
        source = _mergePreviousPositions(
          current: source,
          previous: priorLayout,
        );
      }

      final physics = _calculatePhysics(
        nodeCount: source.nodes.length,
        width: width,
        height: height,
        depth: depth,
        hasCache: hasCache,
      );

      final params = layoutResultToParams(
        source,
        width,
        height,
        depth: depth,
        iterations: physics.iterations,
        k: physics.idealDistance,
        temperature: physics.temperature,
        coolingFactor: physics.coolingFactor,
        seed: seed,
      );

      final resultMap = await layoutAlgorithm.calculate(params);

      // Se utiliza `layout` como original para preservar la metadata
      // más reciente de los nodos. `source` contiene posiciones previas,
      // pero la información funcional actual pertenece al layout nuevo.
      final result = paramsToLayoutResult(resultMap, layout);

      return Right(result);
    } catch (e) {
      return Left(UnexpectedFailure('Error al calcular layout del grafo: $e'));
    }
  }

  /// Determina si existe al menos una posición previa aprovechable.
  bool _hasUsableCache(LayoutResult? priorLayout) {
    if (priorLayout == null) {
      return false;
    }

    return priorLayout.nodes.any(
      (node) => node.x != 0.0 || node.y != 0.0 || node.z != 0.0,
    );
  }

  /// Combina el conjunto de nodos actual con posiciones previamente
  /// calculadas.
  ///
  /// Solo se reutiliza posición cuando el nodo existe en ambos layouts.
  ///
  /// Toda la metadata procede del nodo actual para evitar restaurar
  /// información BLE obsoleta desde el cache.
  LayoutResult _mergePreviousPositions({
    required LayoutResult current,
    required LayoutResult previous,
  }) {
    final previousById = <int, GraphNode>{};

    for (final node in previous.nodes) {
      final id = node.id;

      if (id != null) {
        previousById[id] = node;
      }
    }

    final mergedNodes = current.nodes.map((node) {
      final id = node.id;

      if (id == null) {
        return node;
      }

      final previousNode = previousById[id];

      if (previousNode == null) {
        // Nodo nuevo:
        // conserva la posición inicial proporcionada por el repositorio.
        return node;
      }

      return GraphNode(
        id: node.id,

        // Solo las coordenadas provienen del cache.
        x: previousNode.x,
        y: previousNode.y,
        z: previousNode.z,

        // Toda la metadata continúa siendo la más reciente.
        proximity: node.proximity,
        name: node.name,
        suggestedName: node.suggestedName,
        connectionCount: node.connectionCount,
        isSelf: node.isSelf,
        connectable: node.connectable,
        userColor: node.userColor,
        estimatedDistance: node.estimatedDistance,
      );
    }).toList();

    return LayoutResult(
      nodes: mergedNodes,
      edges: current.edges,
      iterations: current.iterations,
      converged: current.converged,
    );
  }

  /// Calcula dinámicamente los parámetros físicos del grafo.
  ///
  /// El objetivo es evitar una distancia ideal fija para cualquier cantidad
  /// de nodos.
  ///
  /// Grafos pequeños reciben más espacio visual.
  /// Grafos grandes reducen gradualmente la distancia para seguir entrando
  /// dentro del viewport.
  ///
  /// La misma estrategia se utiliza en 2D y 3D.
  _LayoutPhysics _calculatePhysics({
    required int nodeCount,
    required double width,
    required double height,
    required double depth,
    required bool hasCache,
  }) {
    final safeNodeCount = math.max(nodeCount, 1);

    final safeWidth = math.max(width, 1.0);

    final safeHeight = math.max(height, 1.0);

    final is3D = depth > 0.0;

    // Utilizamos la dimensión más corta como referencia para que el layout
    // funcione correctamente incluso en pantallas muy verticales.
    final shortestSide = math.min(safeWidth, safeHeight);

    // FR tradicionalmente relaciona la distancia ideal con:
    //
    //     sqrt(area / número de nodos)
    //
    // Para Nodos App aplicamos una versión controlada de esa relación.
    // Esto hace que pocos nodos tengan una distribución amplia y que el
    // grafo se compacte progresivamente al aumentar su densidad.
    final area = safeWidth * safeHeight;

    final naturalDistance = math.sqrt(area / safeNodeCount);

    // No permitimos que la distancia ideal crezca indefinidamente en
    // grafos con muy pocos nodos.
    //
    // Tampoco permitimos que caiga tanto como para producir un cúmulo
    // ilegible cuando aparecen muchos dispositivos.
    final minIdealDistance = math.max(90.0, shortestSide * 0.10);

    final maxIdealDistance = math.max(
      minIdealDistance,
      math.min(320.0, shortestSide * 0.28),
    );

    var idealDistance = naturalDistance
        .clamp(minIdealDistance, maxIdealDistance)
        .toDouble();

    // En 3D existe un eje adicional donde distribuir nodos.
    //
    // Una pequeña expansión evita que el grafo tridimensional termine
    // visualmente más compacto que su equivalente 2D.
    if (is3D) {
      idealDistance *= 1.08;
    }

    // Cuando partimos de cero permitimos más movimiento para que el grafo
    // pueda encontrar una configuración orgánica.
    //
    // Cuando existe cache, reducimos la energía para conservar la memoria
    // espacial del usuario y evitar saltos bruscos.
    final temperature = hasCache
        ? math.max(idealDistance * 0.45, shortestSide * 0.025)
        : math.max(idealDistance * 1.20, shortestSide * 0.08);

    // Primera distribución:
    // suficientes iteraciones para formar correctamente el grafo.
    //
    // Re-layout con cache:
    // solo necesitamos que los nodos se reajusten alrededor de las
    // posiciones anteriores.
    final iterations = hasCache
        ? _cachedIterations(safeNodeCount)
        : _initialIterations(safeNodeCount);

    // Un enfriamiento ligeramente más suave que el 0.95 original permite
    // una transición más orgánica antes de congelar el sistema.
    //
    // Con cache usamos un enfriamiento algo más rápido para preservar
    // estabilidad visual.
    final coolingFactor = hasCache ? 0.94 : 0.96;

    return _LayoutPhysics(
      iterations: iterations,
      idealDistance: idealDistance,
      temperature: temperature,
      coolingFactor: coolingFactor,
    );
  }

  /// Iteraciones utilizadas cuando todavía no existe layout previo.
  int _initialIterations(int nodeCount) {
    if (nodeCount <= 10) {
      return 120;
    }

    if (nodeCount <= 25) {
      return 110;
    }

    return 100;
  }

  /// Iteraciones utilizadas para reajustar un layout existente.
  int _cachedIterations(int nodeCount) {
    if (nodeCount <= 10) {
      return 45;
    }

    if (nodeCount <= 25) {
      return 40;
    }

    return 35;
  }
}

/// Configuración física calculada para una ejecución del layout.
///
/// Es privada porque representa un detalle interno de [CalculateLayout],
/// no una entidad del dominio de visualización.
class _LayoutPhysics {
  final int iterations;
  final double idealDistance;
  final double temperature;
  final double coolingFactor;

  const _LayoutPhysics({
    required this.iterations,
    required this.idealDistance,
    required this.temperature,
    required this.coolingFactor,
  });
}
