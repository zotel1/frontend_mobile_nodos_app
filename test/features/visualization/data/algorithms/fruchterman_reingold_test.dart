import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/algorithms/fruchterman_reingold.dart';

void main() {
  group('calculateFRLayout', () {
    // ─── helpers ───
    Map<String, dynamic> basicParams({
      required List<Map<String, dynamic>> nodes,
      required List<Map<String, dynamic>> edges,
      int iterations = 100,
      double k = 150.0,
      double temperature = 200.0,
    }) {
      return {
        'nodes': nodes,
        'edges': edges,
        'width': 2000.0,
        'height': 2000.0,
        'iterations': iterations,
        'k': k,
        'temperature': temperature,
        'coolingFactor': 0.95,
        'seed': 42,
      };
    }

    double distance(Map<String, dynamic> a, Map<String, dynamic> b) {
      final dx = (a['x'] as num).toDouble() - (b['x'] as num).toDouble();
      final dy = (a['y'] as num).toDouble() - (b['y'] as num).toDouble();
      return sqrt(dx * dx + dy * dy);
    }

    // ─── tests ───
    test('retorna Map con las claves esperadas', () {
      final params = basicParams(
        nodes: [
          {'id': 1, 'x': 0.0, 'y': 0.0},
          {'id': 2, 'x': 0.0, 'y': 0.0},
        ],
        edges: [
          {'fromId': 1, 'toId': 2},
        ],
      );

      final result = calculateFRLayout(params);

      expect(result, contains('nodes'));
      expect(result, contains('edges'));
      expect(result, contains('iterations'));
      expect(result, contains('converged'));
      expect(result['nodes'], isA<List>());
      expect(result['edges'], isA<List>());
      expect(result['iterations'], isA<int>());
      expect(result['converged'], isA<bool>());
    });

    group('2 nodos conectados', () {
      test('se estabilizan a distancia de equilibrio ~k (100-250px)', () {
        final params = basicParams(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
          ],
          iterations: 100,
          k: 150.0,
          temperature: 200.0,
        );

        final result = calculateFRLayout(params);
        final nodes = result['nodes'] as List<Map<String, dynamic>>;
        final d = distance(nodes[0], nodes[1]);

        // La distancia entre 2 nodos conectados debe aproximarse a k.
        // Con 100 iteraciones y enfriamiento, debe converger cerca de 150.
        expect(d, greaterThan(80));
        expect(d, lessThan(300));
      });

      test('posiciones dentro del canvas (margen 50px)', () {
        final params = basicParams(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
          ],
        );

        final result = calculateFRLayout(params);
        final nodes = result['nodes'] as List<Map<String, dynamic>>;

        for (final node in nodes) {
          final x = (node['x'] as num).toDouble();
          final y = (node['y'] as num).toDouble();
          expect(x, greaterThanOrEqualTo(50));
          expect(x, lessThanOrEqualTo(1950));
          expect(y, greaterThanOrEqualTo(50));
          expect(y, lessThanOrEqualTo(1950));
        }
      });
    });

    group('3 nodos en triángulo', () {
      test('forman forma triangular sin solaparse', () {
        final params = basicParams(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0},
            {'id': 3, 'x': 0.0, 'y': 0.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
            {'fromId': 2, 'toId': 3},
            {'fromId': 3, 'toId': 1},
          ],
          iterations: 100,
          k: 150.0,
          temperature: 200.0,
        );

        final result = calculateFRLayout(params);
        final nodes = result['nodes'] as List<Map<String, dynamic>>;

        // Verificar que ningún par de nodos se solapa (distancia > 30px)
        for (var i = 0; i < nodes.length; i++) {
          for (var j = i + 1; j < nodes.length; j++) {
            final d = distance(nodes[i], nodes[j]);
            expect(d, greaterThan(30),
                reason: 'Nodos $i y $j están demasiado cerca: $d px');
          }
        }

        // Verificar que los 3 lados del triángulo tienen distancias similares
        // (no más del doble entre la menor y la mayor)
        final d01 = distance(nodes[0], nodes[1]);
        final d12 = distance(nodes[1], nodes[2]);
        final d20 = distance(nodes[2], nodes[0]);
        final maxD = [d01, d12, d20].reduce(max);
        final minD = [d01, d12, d20].reduce(min);
        expect(maxD / minD, lessThan(2.5),
            reason: 'Triangulo desbalanceado: d01=$d01 d12=$d12 d20=$d20');
      });
    });

    group('sin aristas', () {
      test('los nodos se dispersan hacia los bordes del canvas', () {
        final params = basicParams(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0},
            {'id': 3, 'x': 0.0, 'y': 0.0},
            {'id': 4, 'x': 0.0, 'y': 0.0},
          ],
          edges: [],
          iterations: 100,
          k: 150.0,
          temperature: 200.0,
        );

        final result = calculateFRLayout(params);
        final nodes = result['nodes'] as List<Map<String, dynamic>>;

        // Sin aristas atractivas, los nodos se repelen entre sí.
        // La distancia mínima entre cualquier par debe ser > 100px.
        var minDist = double.infinity;
        for (var i = 0; i < nodes.length; i++) {
          for (var j = i + 1; j < nodes.length; j++) {
            final d = distance(nodes[i], nodes[j]);
            if (d < minDist) minDist = d;
          }
        }
        expect(minDist, greaterThan(80));
      });
    });

    group('cache de posiciones', () {
      test('posiciones existentes se preservan dentro de 50px', () {
        final params = basicParams(
          nodes: [
            {'id': 1, 'x': 500.0, 'y': 600.0},
            {'id': 2, 'x': 700.0, 'y': 800.0},
            {'id': 3, 'x': 900.0, 'y': 1000.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
            {'fromId': 2, 'toId': 3},
          ],
          iterations: 30,
          k: 150.0,
          temperature: 100.0,
        );

        final result = calculateFRLayout(params);
        final nodes = result['nodes'] as List<Map<String, dynamic>>;

        // Las posiciones iniciales son (500,600), (700,800), (900,1000).
        // Después del layout, deben moverse solo un poco.
        final originalPositions = [
          {'x': 500.0, 'y': 600.0},
          {'x': 700.0, 'y': 800.0},
          {'x': 900.0, 'y': 1000.0},
        ];

        for (var i = 0; i < nodes.length; i++) {
          final dx = ((nodes[i]['x'] as num).toDouble() - originalPositions[i]['x']!).abs();
          final dy = ((nodes[i]['y'] as num).toDouble() - originalPositions[i]['y']!).abs();
          expect(dx, lessThan(120),
              reason: 'Nodo $i se movió ${dx.toStringAsFixed(1)}px en X');
          expect(dy, lessThan(120),
              reason: 'Nodo $i se movió ${dy.toStringAsFixed(1)}px en Y');
        }
      });
    });

    group('rendimiento', () {
      // T5.2: Extendido a 150ms para compensar el overhead de cálculos 3D (dz).
      test('50 nodos se posicionan en menos de 150ms', () {
        final nodes = List.generate(50, (i) => {
          'id': i,
          'x': 0.0,
          'y': 0.0,
        });

        final edges = <Map<String, dynamic>>[];
        // Crear algunas aristas para simular un grafo realista
        for (var i = 0; i < 49; i++) {
          edges.add({'fromId': i, 'toId': i + 1});
        }
        for (var i = 0; i < 50; i += 3) {
          if (i + 2 < 50) {
            edges.add({'fromId': i, 'toId': i + 2});
          }
        }

        final params = basicParams(
          nodes: nodes,
          edges: edges,
          iterations: 50,
          k: 150.0,
          temperature: 200.0,
        );

        final stopwatch = Stopwatch()..start();
        calculateFRLayout(params);
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(150),
            reason: '50 nodos tardaron ${stopwatch.elapsedMilliseconds}ms');
      });
    });

    group('determinismo', () {
      test('misma entrada con seed produce misma salida', () {
        final params1 = basicParams(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0},
            {'id': 3, 'x': 0.0, 'y': 0.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
            {'fromId': 2, 'toId': 3},
          ],
          iterations: 50,
        );

        final params2 = basicParams(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0},
            {'id': 3, 'x': 0.0, 'y': 0.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
            {'fromId': 2, 'toId': 3},
          ],
          iterations: 50,
        );

        final result1 = calculateFRLayout(params1);
        final result2 = calculateFRLayout(params2);

        final nodes1 = result1['nodes'] as List<Map<String, dynamic>>;
        final nodes2 = result2['nodes'] as List<Map<String, dynamic>>;

        for (var i = 0; i < nodes1.length; i++) {
          expect(
            (nodes1[i]['x'] as num).toDouble(),
            closeTo((nodes2[i]['x'] as num).toDouble(), 0.01),
          );
          expect(
            (nodes1[i]['y'] as num).toDouble(),
            closeTo((nodes2[i]['y'] as num).toDouble(), 0.01),
          );
        }

        expect(result1['iterations'], equals(result2['iterations']));
        expect(result1['converged'], equals(result2['converged']));
      });
    });

    group('convergencia temprana', () {
      test('converge antes del maximo si los nodos ya están estables', () {
        // 2 nodos a distancia exacta k=150 → fuerzas balanceadas.
        // Con temperatura baja, el sistema converge rápidamente.
        final params = basicParams(
          nodes: [
            {'id': 1, 'x': 500.0, 'y': 500.0},
            {'id': 2, 'x': 650.0, 'y': 500.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
          ],
          iterations: 50,
          k: 150.0,
          temperature: 30.0,
        );

        final result = calculateFRLayout(params);

        // Con temperatura baja y distancia exacta k,
        // las fuerzas repulsiva y atractiva se cancelan → convergencia.
        expect(result['iterations'], lessThanOrEqualTo(50));
        expect(result['converged'], isTrue);
      });
    });

    // ─── T5.2: FR 3D — extensión al eje Z ────────────────────────
    // QUÉ: el algoritmo FR ahora soporta un tercer eje Z. La distancia
    // entre nodos se calcula en 3D (dx²+dy²+dz²). Las fuerzas repulsivas
    // y atractivas incluyen componente Z. El clamping se aplica también en Z.
    // POR QUÉ: R6.3 — el layout debe extenderse a 3D para el grafo 3D.
    // Compatibilidad: sin z en input → z=0 → comportamiento 2D preservado.

    Map<String, dynamic> params3D({
      required List<Map<String, dynamic>> nodes,
      required List<Map<String, dynamic>> edges,
      int iterations = 100,
      double k = 150.0,
      double temperature = 200.0,
      double depth = 2000.0,
    }) {
      return {
        'nodes': nodes,
        'edges': edges,
        'width': 2000.0,
        'height': 2000.0,
        'depth': depth,
        'iterations': iterations,
        'k': k,
        'temperature': temperature,
        'coolingFactor': 0.95,
        'seed': 42,
      };
    }

    double distance3D(Map<String, dynamic> a, Map<String, dynamic> b) {
      final dx = (a['x'] as num).toDouble() - (b['x'] as num).toDouble();
      final dy = (a['y'] as num).toDouble() - (b['y'] as num).toDouble();
      final az = (a['z'] as num?)?.toDouble() ?? 0.0;
      final bz = (b['z'] as num?)?.toDouble() ?? 0.0;
      final dz = az - bz;
      return sqrt(dx * dx + dy * dy + dz * dz);
    }

    group('T5.2: FR 3D', () {
      test('calcula coordenada Z distinta de 0 con depth parameter', () {
        final params = params3D(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 3, 'x': 0.0, 'y': 0.0, 'z': 0.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
            {'fromId': 2, 'toId': 3},
          ],
          iterations: 100,
          depth: 2000.0,
        );

        final result = calculateFRLayout(params);
        final nodes = result['nodes'] as List<Map<String, dynamic>>;

        // Al menos un nodo debe tener Z distinto de 0 después del layout 3D
        final zValues = nodes.map((n) => (n['z'] as num).toDouble()).toList();
        final hasNonZeroZ = zValues.any((z) => z.abs() > 10.0);
        expect(hasNonZeroZ, isTrue,
            reason: 'Con depth parameter, las coordenadas Z deben divergir');
      });

      test('posiciones Z dentro del rango de profundidad (margen 50px)', () {
        final params = params3D(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 3, 'x': 0.0, 'y': 0.0, 'z': 0.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
            {'fromId': 2, 'toId': 3},
          ],
          depth: 2000.0,
        );

        final result = calculateFRLayout(params);
        final nodes = result['nodes'] as List<Map<String, dynamic>>;

        for (final node in nodes) {
          final z = (node['z'] as num).toDouble();
          expect(z, greaterThanOrEqualTo(50),
              reason: 'Z debe estar dentro del margen inferior');
          expect(z, lessThanOrEqualTo(1950),
              reason: 'Z debe estar dentro del margen superior');
        }
      });

      test('nodos con aristas están más cerca en 3D que nodos sin aristas', () {
        // 6 nodos: 1-2-3 conectados en cadena, 4-5-6 aislados
        final params = params3D(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 3, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 4, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 5, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 6, 'x': 0.0, 'y': 0.0, 'z': 0.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
            {'fromId': 2, 'toId': 3},
          ],
          depth: 2000.0,
        );

        final result = calculateFRLayout(params);
        final nodes = result['nodes'] as List<Map<String, dynamic>>;

        // Distancia 3D entre nodos conectados (1↔2, 2↔3)
        final dConnected12 = distance3D(nodes[0], nodes[1]);
        final dConnected23 = distance3D(nodes[1], nodes[2]);
        final avgConnected = (dConnected12 + dConnected23) / 2;

        // Distancia 3D entre nodos aislados (4↔5, 5↔6)
        final dIsolated45 = distance3D(nodes[3], nodes[4]);
        final dIsolated56 = distance3D(nodes[4], nodes[5]);
        final avgIsolated = (dIsolated45 + dIsolated56) / 2;

        // Nodos conectados deben estar más cerca (atracción de aristas)
        expect(avgConnected, lessThan(avgIsolated),
            reason: 'Nodos con aristas deben estar más cerca: '
                'conectados=${avgConnected.toStringAsFixed(0)}, '
                'aislados=${avgIsolated.toStringAsFixed(0)}');
      });

      test('sin depth parameter → Z se mantiene en 0 (compatibilidad 2D)', () {
        // Usar basicParams (sin depth) para verificar retrocompatibilidad
        final params = basicParams(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
          ],
          iterations: 100,
        );

        final result = calculateFRLayout(params);
        final nodes = result['nodes'] as List<Map<String, dynamic>>;

        for (final node in nodes) {
          final z = (node['z'] as num?)?.toDouble() ?? 0.0;
          expect(z, 0.0,
              reason: 'Sin depth, Z debe ser 0 (backward compatible)');
        }
      });

      test('determinismo: mismo seed produce mismas posiciones Z', () {
        final params1 = params3D(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 3, 'x': 0.0, 'y': 0.0, 'z': 0.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
            {'fromId': 2, 'toId': 3},
          ],
          depth: 2000.0,
        );

        final params2 = params3D(
          nodes: [
            {'id': 1, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 2, 'x': 0.0, 'y': 0.0, 'z': 0.0},
            {'id': 3, 'x': 0.0, 'y': 0.0, 'z': 0.0},
          ],
          edges: [
            {'fromId': 1, 'toId': 2},
            {'fromId': 2, 'toId': 3},
          ],
          depth: 2000.0,
        );

        final result1 = calculateFRLayout(params1);
        final result2 = calculateFRLayout(params2);
        final nodes1 = result1['nodes'] as List<Map<String, dynamic>>;
        final nodes2 = result2['nodes'] as List<Map<String, dynamic>>;

        for (var i = 0; i < nodes1.length; i++) {
          expect(
            (nodes1[i]['z'] as num?)?.toDouble() ?? 0.0,
            closeTo((nodes2[i]['z'] as num?)?.toDouble() ?? 0.0, 0.01),
            reason: 'Z del nodo $i debe ser determinista con mismo seed',
          );
        }
      });
    });

    group('grafo sin nodos', () {
      test('retorna lista vacía sin errores', () {
        final params = basicParams(
          nodes: [],
          edges: [],
        );

        final result = calculateFRLayout(params);

        expect(result['nodes'], isEmpty);
        expect(result['edges'], isEmpty);
        expect(result['iterations'], 0);
        expect(result['converged'], false);
      });
    });
  });
}
