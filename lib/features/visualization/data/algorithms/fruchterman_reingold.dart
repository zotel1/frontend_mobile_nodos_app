import 'dart:math';

/// Calcula el layout del grafo usando el algoritmo de Fruchterman-Reingold.
///
/// Algoritmo dirigido por fuerzas que trata los nodos como partículas
/// que se repelen (Coulomb) y las aristas como resortes que atraen
/// (Hooke). Pensado para grafos de co-detección BLE con 5–50 nodos.
///
/// Elegido sobre Kamada-Kawai (O(n³) inmanejable para >20 nodos) y
/// Eades (convergencia inestable sin enfriamiento). FR ofrece balance
/// O(|V|²+|E|) por iteración con convergencia garantizada por
/// temperatura decreciente (cooling factor 0.95).
///
/// Recibe un [params] con la estructura:
/// ```dart
/// {
///   'nodes': [{id, x, y, z?}, ...],   // x,y,z=0 → posición aleatoria
///   'edges': [{fromId, toId}, ...],
///   'width': 2000.0,
///   'height': 2000.0,
///   'depth': 2000.0,                    // opcional, 3D; fallback a height
///   'iterations': 100,
///   'k': 150.0,                      // distancia ideal entre nodos
///   'temperature': 200.0,            // desplazamiento máximo inicial
///   'coolingFactor': 0.95,
///   'seed': 42,                      // opcional, para tests deterministas
/// }
/// ```
///
/// T5.2: Extendido a 3D. Las distancias ahora incluyen dz.
/// Si no se proporciona `depth`, Z se mantiene en 0 (comportamiento 2D).
///
/// Retorna un Map con nodos reposicionados, aristas, iteraciones reales
/// y flag de convergencia. Esta función es top-level para ser compatible
/// con [compute] de Flutter, que requiere una función accesible desde
/// un Isolate separado.
Map<String, dynamic> calculateFRLayout(Map<String, dynamic> params) {
  // ── Parámetros ──
  final nodes = (params['nodes'] as List)
      .map((n) => Map<String, dynamic>.from(n as Map))
      .toList();
  final edges = (params['edges'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  final width = (params['width'] as num).toDouble();
  final height = (params['height'] as num).toDouble();
  final depth = (params['depth'] as num?)?.toDouble() ?? 0.0;
  final hasDepth = depth > 0.0; // T5.2: flag para modo 3D activo
  final maxIterations = params['iterations'] as int? ?? 100;
  final k = (params['k'] as num?)?.toDouble() ?? 150.0;
  final coolingFactor =
      (params['coolingFactor'] as num?)?.toDouble() ?? 0.95;
  final seed = params['seed'] as int?;

  if (nodes.isEmpty) {
    return {
      'nodes': <Map<String, dynamic>>[],
      'edges': edges,
      'iterations': 0,
      'converged': false,
    };
  }

  // ── Constantes de canvas ──
  const margin = 50.0;
  final areaWidth = width - 2 * margin;
  final areaHeight = height - 2 * margin;
  final areaDepth = hasDepth ? depth - 2 * margin : 0.0;

  // ── 1. Inicializar posiciones aleatorias si x,y,z == 0 ──
  final random = Random(seed);
  for (final node in nodes) {
    final x = (node['x'] as num?)?.toDouble() ?? 0.0;
    final y = (node['y'] as num?)?.toDouble() ?? 0.0;
    if (x == 0.0 && y == 0.0) {
      node['x'] = margin + random.nextDouble() * areaWidth;
      node['y'] = margin + random.nextDouble() * areaHeight;
    }
    // T5.2: Inicializar Z aleatoria si el modo 3D está activo
    final z = (node['z'] as num?)?.toDouble() ?? 0.0;
    if (hasDepth && z == 0.0) {
      node['z'] = margin + random.nextDouble() * areaDepth;
    } else if (node['z'] == null) {
      // Asegurar que z siempre exista en el mapa de salida
      node['z'] = 0.0;
    }
  }

  // ── Pre-construir índice de aristas para O(1) lookup ──
  // Mapa: nodeId → lista de (índice del vecino, delta unitario inicial 0)
  final adjacency = <int, List<int>>{};
  for (var i = 0; i < nodes.length; i++) {
    adjacency[(nodes[i]['id'] as num).toInt()] = [];
  }
  for (final edge in edges) {
    final fromId = (edge['fromId'] as num).toInt();
    final toId = (edge['toId'] as num).toInt();
    adjacency[fromId]?.add(toId);
    adjacency[toId]?.add(fromId);
  }

  // ── Buscar índice de nodo por id ──
  int indexOfId(int id) {
    for (var i = 0; i < nodes.length; i++) {
      if ((nodes[i]['id'] as num).toInt() == id) return i;
    }
    return -1;
  }

  // ── 2. Bucle principal de Fruchterman-Reingold ──
  double temperature = (params['temperature'] as num?)?.toDouble() ??
      (width / 10);
  var converged = false;
  var actualIterations = 0;

  for (var iter = 0; iter < maxIterations; iter++) {
    actualIterations = iter + 1;

    // Inicializar vector de desplazamiento para cada nodo (2D + 3D)
    final displacementX = List<double>.filled(nodes.length, 0.0);
    final displacementY = List<double>.filled(nodes.length, 0.0);
    final displacementZ = hasDepth
        ? List<double>.filled(nodes.length, 0.0)
        : <double>[];

    // ── a. Fuerzas repulsivas: Coulomb entre todos los pares O(|V|²) ──
    // Ley de Coulomb: fr = k² / d
    // Cada nodo repele a todos los demás. La fuerza es inversamente
    // proporcional a la distancia: los nodos muy cercanos se repelen fuerte.
    // T5.2: Distancia ahora incluye dz en modo 3D.
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final dx = (nodes[i]['x'] as num).toDouble() -
            (nodes[j]['x'] as num).toDouble();
        final dy = (nodes[i]['y'] as num).toDouble() -
            (nodes[j]['y'] as num).toDouble();
        double dist2D = dx * dx + dy * dy;

        if (hasDepth) {
          final dz = (nodes[i]['z'] as num).toDouble() -
              (nodes[j]['z'] as num).toDouble();
          dist2D += dz * dz;
        }

        final dist = sqrt(dist2D).clamp(0.01, double.infinity);

        // fr = k² / d  — fuerza repulsiva (Coulomb)
        final fr = (k * k) / dist;

        // El nodo i recibe fuerza en dirección opuesta a j
        displacementX[i] += (dx / dist) * fr;
        displacementY[i] += (dy / dist) * fr;
        // El nodo j recibe fuerza en dirección opuesta a i
        displacementX[j] -= (dx / dist) * fr;
        displacementY[j] -= (dy / dist) * fr;

        // T5.2: Componente Z de la fuerza repulsiva
        if (hasDepth) {
          final dz = (nodes[i]['z'] as num).toDouble() -
              (nodes[j]['z'] as num).toDouble();
          displacementZ[i] += (dz / dist) * fr;
          displacementZ[j] -= (dz / dist) * fr;
        }
      }
    }

    // ── b. Fuerzas atractivas: Hooke solo entre adyacentes O(|E|) ──
    // Ley de Hooke: fa = d² / k
    // Las aristas actúan como resortes que atraen nodos conectados.
    // La fuerza crece con la distancia: nodos lejanos se atraen más.
    // T5.2: Distancia ahora incluye dz en modo 3D.
    for (final edge in edges) {
      final fromIdx = indexOfId((edge['fromId'] as num).toInt());
      final toIdx = indexOfId((edge['toId'] as num).toInt());
      if (fromIdx < 0 || toIdx < 0) continue;

      final dx = (nodes[fromIdx]['x'] as num).toDouble() -
          (nodes[toIdx]['x'] as num).toDouble();
      final dy = (nodes[fromIdx]['y'] as num).toDouble() -
          (nodes[toIdx]['y'] as num).toDouble();
      double dist2D = dx * dx + dy * dy;

      if (hasDepth) {
        final dz = (nodes[fromIdx]['z'] as num).toDouble() -
            (nodes[toIdx]['z'] as num).toDouble();
        dist2D += dz * dz;
      }

      final dist = sqrt(dist2D).clamp(0.01, double.infinity);

      // fa = d² / k  — fuerza atractiva (Hooke)
      final fa = (dist * dist) / k;

      // Atraer fromIdx hacia toIdx (dirección opuesta al vector dx,dy)
      displacementX[fromIdx] -= (dx / dist) * fa;
      displacementY[fromIdx] -= (dy / dist) * fa;
      // Atraer toIdx hacia fromIdx
      displacementX[toIdx] += (dx / dist) * fa;
      displacementY[toIdx] += (dy / dist) * fa;

      // T5.2: Componente Z de la fuerza atractiva
      if (hasDepth) {
        final dz = (nodes[fromIdx]['z'] as num).toDouble() -
            (nodes[toIdx]['z'] as num).toDouble();
        displacementZ[fromIdx] -= (dz / dist) * fa;
        displacementZ[toIdx] += (dz / dist) * fa;
      }
    }

    // ── c. Aplicar desplazamiento con cap de temperatura ──
    // La temperatura limita el desplazamiento máximo en esta iteración.
    // Sin este cap, los nodos oscilarían sin converger.
    // T5.2: El desplazamiento máximo ahora incluye la componente Z.
    var maxDisplacement = 0.0;
    for (var i = 0; i < nodes.length; i++) {
      var disp2D = displacementX[i] * displacementX[i] +
          displacementY[i] * displacementY[i];

      if (hasDepth) {
        disp2D += displacementZ[i] * displacementZ[i];
      }

      final disp = sqrt(disp2D);

      if (disp > maxDisplacement) maxDisplacement = disp;

      if (disp > 0.0) {
        // Cap: el desplazamiento no puede exceder la temperatura
        final scale = disp.clamp(0.0, temperature) / disp;

        final nx = (nodes[i]['x'] as num).toDouble() +
            displacementX[i] * scale;
        final ny = (nodes[i]['y'] as num).toDouble() +
            displacementY[i] * scale;

        // ── d. Clampear al canvas con margen ──
        // Evita que los nodos se escapen del área visible.
        nodes[i]['x'] = nx.clamp(margin, width - margin);
        nodes[i]['y'] = ny.clamp(margin, height - margin);

        // T5.2: Clampear Z si el modo 3D está activo
        if (hasDepth) {
          final nz = (nodes[i]['z'] as num).toDouble() +
              displacementZ[i] * scale;
          nodes[i]['z'] = nz.clamp(margin, depth - margin);
        }
      }
    }

    // ── e. Enfriar temperatura ──
    // Factor multiplicativo 0.95 reduce temperatura gradualmente,
    // congelando las posiciones a medida que se acerca al equilibrio.
    temperature *= coolingFactor;

    // ── f. Convergencia temprana ──
    // Si el desplazamiento máximo es < 1px después de 10 iteraciones,
    // el sistema está en equilibrio y podemos cortar.
    if (maxDisplacement < 1.0 && iter > 10) {
      converged = true;
      break;
    }
  }

  return {
    'nodes': nodes,
    'edges': edges,
    'iterations': actualIterations,
    'converged': converged,
  };
}
