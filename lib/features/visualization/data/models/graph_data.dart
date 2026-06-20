import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Convierte un [LayoutResult] de dominio a un [Map] serializable para el Isolate.
///
/// El algoritmo Fruchterman-Reingold corre en un Isolate separado vía [compute].
/// Como los Isolates no comparten memoria, los datos deben ser serializables
/// (tipos básicos: Map, List, String, num, bool).
///
/// [iterations], [k], [temperature] y [coolingFactor] controlan el
/// comportamiento del algoritmo FR. [seed] opcional para tests deterministas.
/// [depth]: profundidad del canvas 3D. Default 0 → modo 2D.
/// Agregado en T5.4 para pasar el parámetro depth al algoritmo FR 3D.
Map<String, dynamic> layoutResultToParams(
  LayoutResult result,
  double width,
  double height, {
  double depth = 0.0,
  int iterations = 100,
  double k = 150.0,
  double temperature = 200.0,
  double coolingFactor = 0.95,
  int? seed,
}) {
  // T5.3: incluir z en la serialización para el pipeline 3D
  final nodesMap = result.nodes.map((node) => {
    'id': node.id,
    'x': node.x,
    'y': node.y,
    'z': node.z,
  }).toList();

  final edgesMap = result.edges.map((edge) => {
    'fromId': edge.fromId,
    'toId': edge.toId,
  }).toList();

  return {
    'nodes': nodesMap,
    'edges': edgesMap,
    'width': width,
    'height': height,
    'depth': depth,
    'iterations': iterations,
    'k': k,
    'temperature': temperature,
    'coolingFactor': coolingFactor,
    'seed': ?seed,
  };
}

/// Reconstruye un [LayoutResult] de dominio desde el [Map] retornado por
/// el Isolate, preservando los campos del [original] que el algoritmo no
/// modifica (proximity, name, thickness).
///
/// Los nodos se emparejan por su [id]. Solo se incluyen en el resultado
/// los nodos que existen en el [original]; nodos desconocidos se ignoran.
LayoutResult paramsToLayoutResult(
  Map<String, dynamic> result,
  LayoutResult original,
) {
  final resultNodes = result['nodes'] as List<Map<String, dynamic>>;
  final originalNodeMap = <int, GraphNode>{};
  for (final node in original.nodes) {
    if (node.id != null) {
      originalNodeMap[node.id!] = node;
    }
  }

  final updatedNodes = <GraphNode>[];
  for (final rn in resultNodes) {
    final id = (rn['id'] as num).toInt();
    final originalNode = originalNodeMap[id];

    if (originalNode != null) {
      // Preservar campos del original que FR no modifica.
      // T5.3: z se lee del resultado del Isolate (default 0 para 2D).
      updatedNodes.add(GraphNode(
        id: id,
        x: (rn['x'] as num).toDouble(),
        y: (rn['y'] as num).toDouble(),
        z: (rn['z'] as num?)?.toDouble() ?? 0.0,
        proximity: originalNode.proximity,
        name: originalNode.name,
      ));
    }
    // Si el nodo no existe en el original, se ignora (no debería ocurrir)
  }

  return LayoutResult(
    nodes: updatedNodes,
    edges: original.edges,
    iterations: result['iterations'] as int,
    converged: result['converged'] as bool,
  );
}
