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

      expect(edge.props, [10, 20, 2.5, EdgeType.direct]);
    });

    test('thickness derivation from coDetections', () {
      expect(GraphEdge.thicknessFromCount(1), 1.0);
      expect(GraphEdge.thicknessFromCount(2), 2.0);
      expect(GraphEdge.thicknessFromCount(3), 2.0);
      expect(GraphEdge.thicknessFromCount(4), 3.0);
      expect(GraphEdge.thicknessFromCount(10), 3.0);
    });

    // ─── PR2 T2.1: EdgeType enum y edgeType field ─────────────────
    // QUÉ: EdgeType distingue aristas directas (conexión real)
    // de transitivas (1-hop: A→B, B→C ⇒ A—C).
    // POR QUÉ: R5.3 — 1-hop transitive edges must render dashed at 50% opacity.

    test('PR2: EdgeType enum tiene valores direct y transitive', () {
      expect(EdgeType.values, containsAll([EdgeType.direct, EdgeType.transitive]));
      expect(EdgeType.direct.index, isNot(equals(EdgeType.transitive.index)));
    });

    test('PR2: edgeType default es direct', () {
      final edge = GraphEdge(fromId: 1, toId: 2, thickness: 1.0);
      expect(edge.edgeType, equals(EdgeType.direct));
    });

    test('PR2: edgeType puede ser transitive', () {
      final edge = GraphEdge(
        fromId: 1, toId: 3,
        thickness: 0.5,
        edgeType: EdgeType.transitive,
      );
      expect(edge.edgeType, equals(EdgeType.transitive));
    });

    test('PR2: edgeType está en props para equality', () {
      final edgeA = GraphEdge(
        fromId: 1, toId: 2, thickness: 1.0,
        edgeType: EdgeType.transitive,
      );
      final edgeB = GraphEdge(
        fromId: 1, toId: 2, thickness: 1.0,
        edgeType: EdgeType.transitive,
      );
      final edgeC = GraphEdge(
        fromId: 1, toId: 2, thickness: 1.0,
        edgeType: EdgeType.direct,
      );

      expect(edgeA, equals(edgeB));
      expect(edgeA, isNot(equals(edgeC)));
    });
  });
}
