import 'dart:math' as math;

import 'package:dartz/dartz.dart';

import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/models/graph_data.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/algorithms/layout_algorithm.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Caso de uso encargado de calcular y preservar la distribución espacial
/// del grafo.
///
/// El layout tiene dos modos de actualización:
///
/// 1. estabilización física:
///    se ejecuta [LayoutAlgorithm] para distribuir o reajustar el grafo;
///
/// 2. actualización sin física:
///    se conserva exactamente la posición de los nodos existentes y solo
///    se actualiza su metadata.
///
/// Esto permite que cambios frecuentes de RSSI no provoquen movimiento
/// visual innecesario.
class CalculateLayout {
  final LayoutAlgorithm layoutAlgorithm;

  const CalculateLayout({required this.layoutAlgorithm});

  /// Calcula o actualiza el layout.
  ///
  /// [stabilize] controla si debe ejecutarse el algoritmo físico.
  ///
  /// Cuando es `false` y existe [priorLayout]:
  ///
  /// - los nodos existentes conservan exactamente x/y/z;
  /// - la metadata procede del layout actual;
  /// - los nodos nuevos conservan el spawn proporcionado por el repositorio;
  /// - los nodos eliminados desaparecen porque [layout] continúa siendo
  ///   la fuente de verdad estructural;
  /// - no se ejecuta Fruchterman-Reingold.
  ///
  /// Cuando es `true`, se reutilizan primero las posiciones anteriores y
  /// después se ejecuta la física.
  Future<Either<Failure, LayoutResult>> call(
    LayoutResult layout,
    double width,
    double height, {
    double depth = 0.0,
    LayoutResult? priorLayout,
    int? seed,
    bool stabilize = true,
  }) async {
    try {
      var source = layout;

      final hasCache = _hasUsableCache(priorLayout);

      if (priorLayout != null) {
        source = _mergePreviousPositions(
          current: layout,
          previous: priorLayout,
        );
      }

      // Una actualización puramente informativa no debe modificar
      // espacialmente el grafo.
      //
      // `source` ya contiene:
      // - estructura y metadata actuales;
      // - coordenadas anteriores para nodos conocidos;
      // - coordenadas iniciales del repositorio para nodos nuevos.
      if (!stabilize && priorLayout != null) {
        return Right(
          LayoutResult(
            nodes: source.nodes,
            edges: source.edges,
            iterations: 0,
            converged: true,
          ),
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

      // `layout` conserva la metadata más reciente.
      // Las coordenadas calculadas provienen del resultado del algoritmo.
      final result = paramsToLayoutResult(resultMap, layout);

      return Right(result);
    } catch (e) {
      return Left(UnexpectedFailure('Error al calcular layout del grafo: $e'));
    }
  }

  bool _hasUsableCache(LayoutResult? priorLayout) {
    if (priorLayout == null) {
      return false;
    }

    return priorLayout.nodes.any(
      (node) => node.x != 0.0 || node.y != 0.0 || node.z != 0.0,
    );
  }

  /// Fusiona estructura/metadata actual con memoria espacial previa.
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

      // Nodo nuevo:
      // utiliza la posición inicial calculada por GraphRepositoryImpl.
      if (previousNode == null) {
        return node;
      }

      // Nodo existente:
      // memoria espacial anterior + metadata actual.
      return GraphNode(
        id: node.id,
        x: previousNode.x,
        y: previousNode.y,
        z: previousNode.z,
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

    final shortestSide = math.min(safeWidth, safeHeight);

    final area = safeWidth * safeHeight;

    final naturalDistance = math.sqrt(area / safeNodeCount);

    final minIdealDistance = math.max(90.0, shortestSide * 0.10);

    final maxIdealDistance = math.max(
      minIdealDistance,
      math.min(320.0, shortestSide * 0.28),
    );

    var idealDistance = naturalDistance
        .clamp(minIdealDistance, maxIdealDistance)
        .toDouble();

    if (is3D) {
      idealDistance *= 1.08;
    }

    final temperature = hasCache
        ? math.max(idealDistance * 0.45, shortestSide * 0.025)
        : math.max(idealDistance * 1.20, shortestSide * 0.08);

    final iterations = hasCache
        ? _cachedIterations(safeNodeCount)
        : _initialIterations(safeNodeCount);

    final coolingFactor = hasCache ? 0.94 : 0.96;

    return _LayoutPhysics(
      iterations: iterations,
      idealDistance: idealDistance,
      temperature: temperature,
      coolingFactor: coolingFactor,
    );
  }

  int _initialIterations(int nodeCount) {
    if (nodeCount <= 10) {
      return 120;
    }

    if (nodeCount <= 25) {
      return 110;
    }

    return 100;
  }

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
