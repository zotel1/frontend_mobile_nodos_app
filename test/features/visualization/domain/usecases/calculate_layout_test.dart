import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/algorithms/fruchterman_reingold.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/models/graph_data.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

void main() {
  // ═══════════ T5.4: depth parameter en CalculateLayout ═══════════
  // QUÉ: CalculateLayout.call() acepta un parámetro depth y lo pasa
  // al algoritmo FR 3D.
  // POR QUÉ: R6.3 — el pipeline 3D necesita que el use case orqueste
  // la profundidad del canvas para el cálculo de Z en FR.

  group('T5.4: CalculateLayout con depth', () {
    // Helper que ejecuta FR sin Isolate (llamada directa) para tests.
    // compute() usa Isolates que no son necesarios para testear la lógica.
    Map<String, dynamic> runFRLayout({
      required LayoutResult layout,
      double width = 2000.0,
      double height = 2000.0,
      double depth = 0.0,
      int? seed = 42,
    }) {
      final params = layoutResultToParams(
        layout,
        width,
        height,
        depth: depth,
        seed: seed,
      );
      return calculateFRLayout(params);
    }

    final testLayout = LayoutResult(
      nodes: [
        const GraphNode(id: 1, x: 0, y: 0, proximity: ProximityLevel.close, z: 0),
        const GraphNode(id: 2, x: 0, y: 0, proximity: ProximityLevel.medium, z: 0),
        const GraphNode(id: 3, x: 0, y: 0, proximity: ProximityLevel.far, z: 0),
      ],
      edges: [
        const GraphEdge(fromId: 1, toId: 2, thickness: 1.0),
        const GraphEdge(fromId: 2, toId: 3, thickness: 1.0),
      ],
      iterations: 0,
      converged: false,
    );

    test('con depth=2000, las coordenadas Z divergen de 0', () {
      final resultMap = runFRLayout(
        layout: testLayout,
        depth: 2000.0,
      );

      final result = paramsToLayoutResult(resultMap, testLayout);
      final zValues = result.nodes.map((n) => n.z).toList();

      // Al menos un nodo debe tener Z distinta de 0 después del layout 3D
      final hasNonZeroZ = zValues.any((z) => z.abs() > 10.0);
      expect(hasNonZeroZ, isTrue,
          reason: 'Con depth, las coordenadas Z deben divergir');
    });

    test('sin depth, las coordenadas Z son 0 (backward compatible)', () {
      final resultMap = runFRLayout(
        layout: testLayout,
        depth: 0.0,
      );

      final result = paramsToLayoutResult(resultMap, testLayout);
      for (final node in result.nodes) {
        expect(node.z, 0.0,
            reason: 'Sin depth, Z debe permanecer 0');
      }
    });

    test('depth se pasa correctamente en el mapa de parámetros', () {
      final layout = LayoutResult(
        nodes: [
          const GraphNode(id: 1, x: 100, y: 200, proximity: ProximityLevel.close),
        ],
        edges: [],
        iterations: 0,
        converged: false,
      );

      final params = layoutResultToParams(
        layout, 2000, 2000,
        depth: 1500.0,
      );

      expect(params['depth'], equals(1500.0));
      expect(params['width'], equals(2000.0));
      expect(params['height'], equals(2000.0));
    });
  });
}
