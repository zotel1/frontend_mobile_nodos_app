import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_layout_snapshot.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

void main() {
  GraphNode node(int id, {double x = 10, double y = 20}) =>
      GraphNode(id: id, x: x, y: y, proximity: ProximityLevel.close);

  LayoutResult layout({List<GraphNode>? nodes, List<GraphEdge>? edges}) =>
      LayoutResult(
        nodes: nodes ?? [node(1), node(2, x: 30)],
        edges: edges ?? const [GraphEdge(fromId: 1, toId: 2, thickness: 1)],
        iterations: 1,
        converged: true,
      );

  test('exposes the same topology and positions to both renderers', () {
    final snapshot = GraphLayoutSnapshot(layout: layout(), revision: 3);

    expect(snapshot.nodes, layout().nodes);
    expect(snapshot.edges, layout().edges);
    expect(snapshot.revision, 3);
  });

  test('is deterministic for the same topology regardless of ordering', () {
    final first = layout();
    final reordered = layout(
      nodes: [node(2, x: 30), node(1)],
      edges: const [GraphEdge(fromId: 2, toId: 1, thickness: 1)],
    );

    expect(
      GraphLayoutSnapshot(layout: first).topologySignature,
      GraphLayoutSnapshot(layout: reordered).topologySignature,
    );
    expect(
      GraphLayoutSnapshot.stableSeedFor(first),
      GraphLayoutSnapshot.stableSeedFor(reordered),
    );
  });

  test('changes its topology identity when a node or edge is added', () {
    final first = GraphLayoutSnapshot(layout: layout());
    final changed = GraphLayoutSnapshot(
      layout: layout(
        nodes: [node(1), node(2, x: 30), node(3, x: 50)],
        edges: const [
          GraphEdge(fromId: 1, toId: 2, thickness: 1),
          GraphEdge(fromId: 2, toId: 3, thickness: 1),
        ],
      ),
    );

    expect(changed.topologySignature, isNot(first.topologySignature));
    expect(
      GraphLayoutSnapshot.stableSeedFor(changed.layout),
      isNot(GraphLayoutSnapshot.stableSeedFor(first.layout)),
    );
  });

  test('preserves edge semantics in the shared snapshot', () {
    final snapshot = GraphLayoutSnapshot(
      layout: layout(
        edges: const [
          GraphEdge(
            fromId: 1,
            toId: 2,
            thickness: 1,
            edgeType: EdgeType.direct,
          ),
          GraphEdge(
            fromId: 2,
            toId: 3,
            thickness: 1,
            edgeType: EdgeType.transitive,
          ),
          GraphEdge(
            fromId: 3,
            toId: 1,
            thickness: 1,
            edgeType: EdgeType.reported,
          ),
        ],
      ),
    );

    expect(snapshot.edges.map((edge) => edge.edgeType), [
      EdgeType.direct,
      EdgeType.transitive,
      EdgeType.reported,
    ]);
  });
}
