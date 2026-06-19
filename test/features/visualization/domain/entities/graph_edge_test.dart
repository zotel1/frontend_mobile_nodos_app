import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';

void main() {
  group('GraphEdge', () {
    test('supports equality by fromId, toId, thickness', () {
      final edge1 = GraphEdge(fromId: 1, toId: 2, thickness: 2.0);
      final edge2 = GraphEdge(fromId: 1, toId: 2, thickness: 2.0);

      expect(edge1, equals(edge2));
    });

    test('supports inequality when fromId differs', () {
      final edge1 = GraphEdge(fromId: 1, toId: 2, thickness: 2.0);
      final edge2 = GraphEdge(fromId: 3, toId: 2, thickness: 2.0);

      expect(edge1, isNot(equals(edge2)));
    });

    test('supports inequality when toId differs', () {
      final edge1 = GraphEdge(fromId: 1, toId: 2, thickness: 2.0);
      final edge2 = GraphEdge(fromId: 1, toId: 3, thickness: 2.0);

      expect(edge1, isNot(equals(edge2)));
    });

    test('supports inequality when thickness differs', () {
      final edge1 = GraphEdge(fromId: 1, toId: 2, thickness: 1.0);
      final edge2 = GraphEdge(fromId: 1, toId: 2, thickness: 3.0);

      expect(edge1, isNot(equals(edge2)));
    });

    test('props list contains correct fields', () {
      final edge = GraphEdge(fromId: 10, toId: 20, thickness: 2.5);

      expect(edge.props, [10, 20, 2.5]);
    });

    test('thickness derivation from coDetections', () {
      expect(GraphEdge.thicknessFromCount(1), 1.0);
      expect(GraphEdge.thicknessFromCount(2), 2.0);
      expect(GraphEdge.thicknessFromCount(3), 2.0);
      expect(GraphEdge.thicknessFromCount(4), 3.0);
      expect(GraphEdge.thicknessFromCount(10), 3.0);
    });
  });
}
