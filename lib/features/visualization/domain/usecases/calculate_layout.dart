import 'package:dartz/dartz.dart';

import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/models/graph_data.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/algorithms/layout_algorithm.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Caso de uso: calcula el layout del grafo usando el algoritmo inyectado.
///
/// Orquesta la ejecución del algoritmo de layout inyectado vía
/// [LayoutAlgorithm] interface. No conoce la implementación concreta
/// ni si se ejecuta en un Isolate — eso es responsabilidad de la capa
/// de datos (FruchtermanReingold llama compute() internamente).
///
/// Recibe [layoutAlgorithm] por constructor (AD-31: el dominio depende
/// de interfaces, no de implementaciones concretas). La capa de DI
/// inyecta [FruchtermanReingold] como implementación concreta.
///
/// Usa `GraphData` para serializar las entidades de dominio a
/// `Map<String, dynamic>` y deserializar el resultado.
class CalculateLayout {
  final LayoutAlgorithm layoutAlgorithm;

  const CalculateLayout({required this.layoutAlgorithm});

  /// Ejecuta el layout sobre [layout] en un canvas de [width]×[height].
  ///
  /// [depth]: profundidad del canvas para modo 3D. Default 0 → modo 2D.
  /// Si [priorLayout] tiene posiciones previas, se reutilizan como punto de
  /// partida (menos iteraciones necesarias para converger).
  /// Retorna [Right] con el nuevo [LayoutResult] o [Left] con un [Failure]
  /// si el algoritmo falla.
  Future<Either<Failure, LayoutResult>> call(
    LayoutResult layout,
    double width,
    double height, {
    double depth = 0.0,
    LayoutResult? priorLayout,
    int? seed,
  }) async {
    try {
      // Siempre usar el layout actual con TODOS los nodos.
      // BUG-FIX: priorLayout ?? layout truncaba el set de nodos cuando
      // el cache tenía menos nodos que el layout actual (ej: primer scan
      // con 3 nodos, segundo con 7 → _lastLayout (3) se usaba como source
      // y los 4 nodos nuevos nunca llegaban al Isolate).
      LayoutResult source = layout;

      // Si hay cache, inyectar posiciones previas SOLO para nodos
      // que existan en ambos sets (mismo id). Los nodos nuevos conservan
      // su posición inicial del anillo (calculada en GraphRepositoryImpl).
      //
      // Determinar iteraciones: menos si hay cache de posiciones
      final hasCache = priorLayout != null &&
          priorLayout.nodes.any((n) => n.x != 0.0 || n.y != 0.0);
      final iterations = hasCache ? 30 : 100;
      final temperature = hasCache ? width / 20 : width / 10;

      if (priorLayout != null) {
        final priorMap = <int, GraphNode>{};
        for (final n in priorLayout.nodes) {
          if (n.id != null) priorMap[n.id!] = n;
        }
        final mergedNodes = source.nodes.map((node) {
          final prior = node.id != null ? priorMap[node.id] : null;
          if (prior != null) {
            // Reutilizar posición previa para nodos ya existentes
            return GraphNode(
              id: node.id,
              x: prior.x,
              y: prior.y,
              z: prior.z,
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
          // Nodo nuevo: conserva su posición inicial del anillo
          return node;
        }).toList();
        source = LayoutResult(
          nodes: mergedNodes,
          edges: source.edges,
          iterations: source.iterations,
          converged: source.converged,
        );
      }

      // Serializar para pasar al algoritmo (compatible con Isolate si
      // la implementación concreta usa compute() internamente).
      final params = layoutResultToParams(
        source,
        width,
        height,
        depth: depth,
        iterations: iterations,
        k: 150.0,
        temperature: temperature,
        coolingFactor: 0.95,
        seed: seed,
      );

      // Delegar al algoritmo inyectado (AD-31).
      // FruchtermanReingold llama compute(calculateFRLayout, params)
      // internamente para ejecutar en un Isolate. El dominio no sabe
      // ni necesita saber este detalle de implementación.
      final resultMap = await layoutAlgorithm.calculate(params);

      // Reconstruir LayoutResult desde el Map retornado por el algoritmo
      final result = paramsToLayoutResult(resultMap, layout);

      return Right(result);
    } catch (e) {
      // Capturar errores del algoritmo (spawn fallido, excepción, etc.)
      return Left(UnexpectedFailure(
        'Error al calcular layout del grafo: $e',
      ));
    }
  }
}

