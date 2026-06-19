import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';

/// Resultado del layout del grafo.
///
/// Agrega los nodos posicionados, las aristas derivadas, la cantidad
/// de iteraciones ejecutadas por Fruchterman-Reingold, y si convergió
/// antes de alcanzar el máximo de iteraciones.
class LayoutResult extends Equatable {
  /// Nodos con sus posiciones (x, y) calculadas.
  final List<GraphNode> nodes;

  /// Aristas entre nodos co-detectados.
  final List<GraphEdge> edges;

  /// Iteraciones ejecutadas por el algoritmo FR.
  final int iterations;

  /// true si el algoritmo convergió (delta < epsilon) antes del máximo.
  final bool converged;

  const LayoutResult({
    required this.nodes,
    required this.edges,
    required this.iterations,
    required this.converged,
  });

  @override
  List<Object?> get props => [nodes, edges, iterations, converged];
}
