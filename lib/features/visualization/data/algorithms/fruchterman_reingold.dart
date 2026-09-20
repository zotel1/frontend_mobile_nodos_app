import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:frontend_mobile_nodos_app/features/visualization/domain/algorithms/layout_algorithm.dart';

/// Implementación concreta de [LayoutAlgorithm] usando Fruchterman-Reingold.
///
/// Algoritmo dirigido por fuerzas que trata los nodos como partículas
/// que se repelen y las aristas como resortes que atraen.
///
/// Está pensado para grafos BLE pequeños/medianos y se ejecuta en un
/// Isolate mediante [compute] para no bloquear el hilo principal.
///
/// Soporta:
/// - layout 2D;
/// - layout 3D opcional mediante `depth`;
/// - reutilización de posiciones previas;
/// - nodo local (`isSelf`) anclado;
/// - ejecución determinista mediante `seed` para tests.
///
/// El nodo local participa en el sistema de fuerzas, pero su posición
/// no se modifica. De esta manera actúa como ancla física del grafo.
class FruchtermanReingold implements LayoutAlgorithm {
  const FruchtermanReingold();

  @override
  Future<Map<String, dynamic>> calculate(Map<String, dynamic> params) async {
    return compute(calculateFRLayout, params);
  }
}

/// Calcula el layout usando Fruchterman-Reingold.
///
/// Estructura esperada:
///
/// ```dart
/// {
///   'nodes': [{id, x, y, z?, isSelf?}, ...],
///   'edges': [{fromId, toId}, ...],
///   'width': 2000.0,
///   'height': 2000.0,
///   'depth': 2000.0,       // opcional; 0 = modo 2D
///   'iterations': 100,
///   'k': 150.0,
///   'temperature': 200.0,
///   'coolingFactor': 0.95,
///   'seed': 42,            // opcional
/// }
/// ```
///
/// El nodo marcado con `isSelf == true` permanece anclado, pero participa
/// normalmente en las fuerzas repulsivas y atractivas.
///
/// Esta función es top-level porque debe poder ejecutarse mediante
/// [compute] en un Isolate separado.
Map<String, dynamic> calculateFRLayout(Map<String, dynamic> params) {
  // ─────────────────────────────────────────────────────────────
  // 1. PARÁMETROS
  // ─────────────────────────────────────────────────────────────

  final nodes = (params['nodes'] as List)
      .map((node) => Map<String, dynamic>.from(node as Map))
      .toList();

  final edges = (params['edges'] as List)
      .map((edge) => Map<String, dynamic>.from(edge as Map))
      .toList();

  final width = (params['width'] as num).toDouble();
  final height = (params['height'] as num).toDouble();

  final depth = (params['depth'] as num?)?.toDouble() ?? 0.0;

  final hasDepth = depth > 0.0;

  final maxIterations = params['iterations'] as int? ?? 100;

  final k = (params['k'] as num?)?.toDouble() ?? 150.0;

  final coolingFactor = (params['coolingFactor'] as num?)?.toDouble() ?? 0.95;

  final seed = params['seed'] as int?;

  double temperature =
      (params['temperature'] as num?)?.toDouble() ?? (width / 10);

  if (nodes.isEmpty) {
    return {
      'nodes': <Map<String, dynamic>>[],
      'edges': edges,
      'iterations': 0,
      'converged': false,
    };
  }

  // ─────────────────────────────────────────────────────────────
  // 2. CANVAS
  // ─────────────────────────────────────────────────────────────

  const margin = 50.0;

  final areaWidth = max(0.0, width - (2 * margin));
  final areaHeight = max(0.0, height - (2 * margin));
  final areaDepth = hasDepth ? max(0.0, depth - (2 * margin)) : 0.0;

  final centerX = width / 2;
  final centerY = height / 2;
  final centerZ = hasDepth ? depth / 2 : 0.0;

  // ─────────────────────────────────────────────────────────────
  // 3. IDENTIFICAR SELF-NODE
  // ─────────────────────────────────────────────────────────────

  var selfNodeIdx = -1;

  for (var i = 0; i < nodes.length; i++) {
    if (nodes[i]['isSelf'] == true) {
      selfNodeIdx = i;
      break;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 4. INICIALIZAR POSICIONES
  // ─────────────────────────────────────────────────────────────

  final random = Random(seed);

  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];

    final x = (node['x'] as num?)?.toDouble() ?? 0.0;

    final y = (node['y'] as num?)?.toDouble() ?? 0.0;

    final z = (node['z'] as num?)?.toDouble() ?? 0.0;

    // El nodo local funciona como ancla central.
    //
    // Si todavía no tiene una posición válida, se coloca exactamente
    // en el centro del espacio disponible.
    if (i == selfNodeIdx) {
      if (x == 0.0 && y == 0.0) {
        node['x'] = centerX;
        node['y'] = centerY;
      }

      if (hasDepth) {
        if (z == 0.0) {
          node['z'] = centerZ;
        }
      } else {
        node['z'] = 0.0;
      }

      continue;
    }

    // Los nodos sin posición previa reciben una posición aleatoria.
    if (x == 0.0 && y == 0.0) {
      node['x'] = margin + random.nextDouble() * areaWidth;

      node['y'] = margin + random.nextDouble() * areaHeight;
    }

    if (hasDepth) {
      if (z == 0.0) {
        node['z'] = margin + random.nextDouble() * areaDepth;
      }
    } else {
      node['z'] = 0.0;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 5. ÍNDICE ID → POSICIÓN EN LA LISTA
  // ─────────────────────────────────────────────────────────────

  // Evita recorrer todos los nodos por cada arista.
  //
  // Antes:
  //   indexOfId() → O(|V|) por lookup.
  //
  // Ahora:
  //   Map lookup → O(1).
  final nodeIndexById = <int, int>{};

  for (var i = 0; i < nodes.length; i++) {
    final id = (nodes[i]['id'] as num).toInt();
    nodeIndexById[id] = i;
  }

  // ─────────────────────────────────────────────────────────────
  // 6. BUCLE PRINCIPAL FR
  // ─────────────────────────────────────────────────────────────

  var converged = false;
  var actualIterations = 0;

  for (var iter = 0; iter < maxIterations; iter++) {
    actualIterations = iter + 1;

    final displacementX = List<double>.filled(nodes.length, 0.0);

    final displacementY = List<double>.filled(nodes.length, 0.0);

    final displacementZ = hasDepth
        ? List<double>.filled(nodes.length, 0.0)
        : <double>[];

    // ───────────────────────────────────────────────────────────
    // 6.A FUERZAS REPULSIVAS
    // ───────────────────────────────────────────────────────────
    //
    // fr = k² / d
    //
    // IMPORTANTE:
    // El self-node también participa.
    //
    // Aunque acumule desplazamiento, ese desplazamiento nunca se
    // aplicará posteriormente porque su posición está anclada.

    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final dx =
            (nodes[i]['x'] as num).toDouble() -
            (nodes[j]['x'] as num).toDouble();

        final dy =
            (nodes[i]['y'] as num).toDouble() -
            (nodes[j]['y'] as num).toDouble();

        var distanceSquared = (dx * dx) + (dy * dy);

        double dz = 0.0;

        if (hasDepth) {
          dz =
              (nodes[i]['z'] as num).toDouble() -
              (nodes[j]['z'] as num).toDouble();

          distanceSquared += dz * dz;
        }

        final distance = sqrt(distanceSquared).clamp(0.01, double.infinity);

        final repulsiveForce = (k * k) / distance;

        final normalizedX = dx / distance;
        final normalizedY = dy / distance;

        displacementX[i] += normalizedX * repulsiveForce;

        displacementY[i] += normalizedY * repulsiveForce;

        displacementX[j] -= normalizedX * repulsiveForce;

        displacementY[j] -= normalizedY * repulsiveForce;

        if (hasDepth) {
          final normalizedZ = dz / distance;

          displacementZ[i] += normalizedZ * repulsiveForce;

          displacementZ[j] -= normalizedZ * repulsiveForce;
        }
      }
    }

    // ───────────────────────────────────────────────────────────
    // 6.B FUERZAS ATRACTIVAS
    // ───────────────────────────────────────────────────────────
    //
    // fa = d² / k
    //
    // Las aristas funcionan como resortes.
    //
    // Las conexiones con el nodo local también participan:
    // el nodo remoto es atraído hacia el self-node, mientras que el
    // self-node permanece físicamente anclado.

    for (final edge in edges) {
      final fromId = (edge['fromId'] as num).toInt();

      final toId = (edge['toId'] as num).toInt();

      final fromIdx = nodeIndexById[fromId];
      final toIdx = nodeIndexById[toId];

      if (fromIdx == null || toIdx == null) {
        continue;
      }

      // Una auto-arista no aporta información útil al layout.
      if (fromIdx == toIdx) {
        continue;
      }

      final dx =
          (nodes[fromIdx]['x'] as num).toDouble() -
          (nodes[toIdx]['x'] as num).toDouble();

      final dy =
          (nodes[fromIdx]['y'] as num).toDouble() -
          (nodes[toIdx]['y'] as num).toDouble();

      var distanceSquared = (dx * dx) + (dy * dy);

      double dz = 0.0;

      if (hasDepth) {
        dz =
            (nodes[fromIdx]['z'] as num).toDouble() -
            (nodes[toIdx]['z'] as num).toDouble();

        distanceSquared += dz * dz;
      }

      final distance = sqrt(distanceSquared).clamp(0.01, double.infinity);

      final attractiveForce = (distance * distance) / k;

      final normalizedX = dx / distance;
      final normalizedY = dy / distance;

      displacementX[fromIdx] -= normalizedX * attractiveForce;

      displacementY[fromIdx] -= normalizedY * attractiveForce;

      displacementX[toIdx] += normalizedX * attractiveForce;

      displacementY[toIdx] += normalizedY * attractiveForce;

      if (hasDepth) {
        final normalizedZ = dz / distance;

        displacementZ[fromIdx] -= normalizedZ * attractiveForce;

        displacementZ[toIdx] += normalizedZ * attractiveForce;
      }
    }

    // ───────────────────────────────────────────────────────────
    // 6.C APLICAR DESPLAZAMIENTO
    // ───────────────────────────────────────────────────────────

    var maxAppliedDisplacement = 0.0;

    for (var i = 0; i < nodes.length; i++) {
      // El self-node participa en las fuerzas pero NO se mueve.
      if (i == selfNodeIdx) {
        continue;
      }

      var displacementSquared =
          (displacementX[i] * displacementX[i]) +
          (displacementY[i] * displacementY[i]);

      if (hasDepth) {
        displacementSquared += displacementZ[i] * displacementZ[i];
      }

      final displacement = sqrt(displacementSquared);

      if (displacement <= 0.0) {
        continue;
      }

      // La temperatura limita cuánto puede moverse realmente
      // un nodo durante esta iteración.
      final appliedDisplacement = min(displacement, temperature);

      if (appliedDisplacement > maxAppliedDisplacement) {
        maxAppliedDisplacement = appliedDisplacement;
      }

      final scale = appliedDisplacement / displacement;

      final newX = (nodes[i]['x'] as num).toDouble() + displacementX[i] * scale;

      final newY = (nodes[i]['y'] as num).toDouble() + displacementY[i] * scale;

      nodes[i]['x'] = newX.clamp(margin, width - margin);

      nodes[i]['y'] = newY.clamp(margin, height - margin);

      if (hasDepth) {
        final newZ =
            (nodes[i]['z'] as num).toDouble() + displacementZ[i] * scale;

        nodes[i]['z'] = newZ.clamp(margin, depth - margin);
      }
    }

    // ───────────────────────────────────────────────────────────
    // 6.D ENFRIAMIENTO
    // ───────────────────────────────────────────────────────────

    temperature *= coolingFactor;

    // ───────────────────────────────────────────────────────────
    // 6.E CONVERGENCIA TEMPRANA
    // ───────────────────────────────────────────────────────────
    //
    // Medimos desplazamiento REAL aplicado, no la fuerza bruta
    // acumulada antes del límite de temperatura.

    if (maxAppliedDisplacement < 1.0 && iter > 10) {
      converged = true;
      break;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 7. RESULTADO
  // ─────────────────────────────────────────────────────────────

  return {
    'nodes': nodes,
    'edges': edges,
    'iterations': actualIterations,
    'converged': converged,
  };
}
