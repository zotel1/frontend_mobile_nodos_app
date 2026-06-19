import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';

import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/algorithms/fruchterman_reingold.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/models/graph_data.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Caso de uso: calcula el layout del grafo con Fruchterman-Reingold en un Isolate.
///
/// Orquesta la ejecución del algoritmo FR en un Isolate separado usando [compute].
/// Esto evita que el cálculo intensivo de fuerzas (O(|V|²+|E|) por iteración)
/// bloquee el hilo principal de la UI, manteniendo los 60fps.
///
/// Usa `GraphData` para serializar las entidades de dominio a
/// `Map<String, dynamic>` (compatible con el límite entre Isolates)
/// y deserializar el resultado.
class CalculateLayout {
  const CalculateLayout();

  /// Ejecuta el layout FR sobre [layout] en un canvas de [width]×[height].
  ///
  /// Si [priorLayout] tiene posiciones previas, se reutilizan como punto de
  /// partida (menos iteraciones necesarias para converger).
  /// Retorna [Right] con el nuevo [LayoutResult] o [Left] con un [Failure]
  /// si el Isolate falla.
  Future<Either<Failure, LayoutResult>> call(
    LayoutResult layout,
    double width,
    double height, {
    LayoutResult? priorLayout,
    int? seed,
  }) async {
    try {
      // Usar posiciones previas si existen (cache de layout)
      final source = priorLayout ?? layout;

      // Determinar iteraciones: menos si hay cache de posiciones
      final hasCache = priorLayout != null &&
          priorLayout.nodes.any((n) => n.x != 0.0 || n.y != 0.0);
      final iterations = hasCache ? 30 : 100;
      final temperature = hasCache ? width / 20 : width / 10;

      // Serializar para cruzar el límite del Isolate
      final params = layoutResultToParams(
        source,
        width,
        height,
        iterations: iterations,
        k: 150.0,
        temperature: temperature,
        coolingFactor: 0.95,
        seed: seed,
      );

      // Ejecutar FR en un Isolate separado. compute() se encarga de
      // spawnear el Isolate, enviar params, ejecutar calculateFRLayout,
      // y retornar el resultado al hilo principal.
      final resultMap =
          await compute(calculateFRLayout, params);

      // Reconstruir LayoutResult desde el Map retornado por el Isolate
      final result = paramsToLayoutResult(resultMap, layout);

      return Right(result);
    } catch (e) {
      // Capturar errores del Isolate (spawn fallido, excepción en FR, etc.)
      return Left(UnexpectedFailure(
        'Error al calcular layout del grafo: $e',
      ));
    }
  }
}
