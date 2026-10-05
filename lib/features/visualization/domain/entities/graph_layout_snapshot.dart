import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Immutable logical layout shared by every graph renderer.
class GraphLayoutSnapshot extends Equatable {
  final LayoutResult layout;
  final int revision;

  const GraphLayoutSnapshot({required this.layout, this.revision = 0});

  List<GraphNode> get nodes => layout.nodes;
  List<GraphEdge> get edges => layout.edges;

  /// Canonical topology identity, independent of node ordering.
  String get topologySignature {
    final nodeIds = nodes.map((node) => node.id).whereType<int>().toList()
      ..sort();
    final edgeKeys = edges.map((edge) {
      final first = edge.fromId < edge.toId ? edge.fromId : edge.toId;
      final second = edge.fromId < edge.toId ? edge.toId : edge.fromId;
      return '$first:$second:${edge.edgeType.name}';
    }).toList()..sort();
    return '${nodeIds.join(',')}|${edgeKeys.join(',')}';
  }

  /// Stable seed for the same topology, independent of process hash randomization.
  static int stableSeedFor(LayoutResult layout) {
    var hash = 2166136261;
    final signature = GraphLayoutSnapshot(layout: layout).topologySignature;
    for (final codeUnit in signature.codeUnits) {
      hash = ((hash ^ codeUnit) * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  @override
  List<Object?> get props => [layout, revision];
}
