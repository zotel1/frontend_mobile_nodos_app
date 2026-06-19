import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

void main() {
  group('LayoutResult', () {
    final testNodes = [
      GraphNode(id: 1, x: 0.0, y: 0.0, proximity: ProximityLevel.close),
      GraphNode(id: 2, x: 100.0, y: 100.0, proximity: ProximityLevel.medium),
    ];
    final testEdges = [
      GraphEdge(fromId: 1, toId: 2, thickness: 2.0),
    ];

    test('supports equality by nodes, edges, iterations, converged', () {
      final result1 = LayoutResult(
        nodes: testNodes,
        edges: testEdges,
        iterations: 50,
        converged: true,
      );
      final result2 = LayoutResult(
        nodes: testNodes,
        edges: testEdges,
        iterations: 50,
        converged: true,
      );

      expect(result1, equals(result2));
    });

    test('supports inequality when nodes differ', () {
      final result1 = LayoutResult(
        nodes: testNodes,
        edges: testEdges,
        iterations: 50,
        converged: true,
      );
      final result2 = LayoutResult(
        nodes: [
          GraphNode(id: 3, x: 0.0, y: 0.0, proximity: ProximityLevel.far),
        ],
        edges: testEdges,
        iterations: 50,
        converged: true,
      );

      expect(result1, isNot(equals(result2)));
    });

    test('supports inequality when edges differ', () {
      final result1 = LayoutResult(
        nodes: testNodes,
        edges: testEdges,
        iterations: 50,
        converged: true,
      );
      final result2 = LayoutResult(
        nodes: testNodes,
        edges: [],
        iterations: 50,
        converged: true,
      );

      expect(result1, isNot(equals(result2)));
    });

    test('supports inequality when iterations differ', () {
      final result1 = LayoutResult(
        nodes: testNodes,
        edges: testEdges,
        iterations: 50,
        converged: true,
      );
      final result2 = LayoutResult(
        nodes: testNodes,
        edges: testEdges,
        iterations: 100,
        converged: true,
      );

      expect(result1, isNot(equals(result2)));
    });

    test('supports inequality when converged differs', () {
      final result1 = LayoutResult(
        nodes: testNodes,
        edges: testEdges,
        iterations: 50,
        converged: true,
      );
      final result2 = LayoutResult(
        nodes: testNodes,
        edges: testEdges,
        iterations: 50,
        converged: false,
      );

      expect(result1, isNot(equals(result2)));
    });

    test('props list contains correct fields', () {
      final result = LayoutResult(
        nodes: testNodes,
        edges: testEdges,
        iterations: 30,
        converged: true,
      );

      expect(result.props.length, 4);
      expect(result.props[0], testNodes);
      expect(result.props[1], testEdges);
      expect(result.props[2], 30);
      expect(result.props[3], true);
    });

    test('empty layout result is valid', () {
      final result = LayoutResult(
        nodes: const [],
        edges: const [],
        iterations: 0,
        converged: false,
      );

      expect(result.nodes, isEmpty);
      expect(result.edges, isEmpty);
      expect(result.iterations, 0);
      expect(result.converged, false);
    });
  });
}
