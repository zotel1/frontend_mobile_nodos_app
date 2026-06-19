import 'dart:math';

import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/repositories/graph_repository.dart';

/// Implementación de [GraphRepository] usando NodeRepository y Drift.
///
/// Obtiene nodos desde NodeRepository (datos ya normalizados) y
/// deriva aristas desde la tabla scan_session_nodes de Drift.
/// Las posiciones iniciales de los nodos se distribuyen en círculo
/// hasta que CalculateLayout (PR2) aplique Fruchterman-Reingold.
class GraphRepositoryImpl implements GraphRepository {
  final NodeRepository _nodeRepository;
  final AppDatabase _db;

  GraphRepositoryImpl(this._nodeRepository, this._db);

  @override
  Future<LayoutResult> buildGraph(int scanSessionId) async {
    // 1. Obtener todos los nodos detectados en esta sesión
    final sessionRows = await (_db.select(_db.scanSessionNodes)
          ..where((t) => t.sessionId.equals(scanSessionId)))
        .get();

    if (sessionRows.isEmpty) {
      return const LayoutResult(
        nodes: [],
        edges: [],
        iterations: 0,
        converged: false,
      );
    }

    // 2. Obtener entidades Node para cada scan_session_node
    final nodeIds = sessionRows.map((r) => r.nodeId).toSet().toList();
    final nodePromises = nodeIds.map((id) => _nodeRepository.getNodeById(id));
    final nodes = await Future.wait(nodePromises);

    // 3. Crear GraphNode con posiciones iniciales en círculo
    final graphNodes = <GraphNode>[];
    final nodeIdToIndex = <int, int>{};
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node == null) continue;

      // Posición inicial circular (será refinada por FR en PR2)
      final angle = (2 * pi * i) / nodes.length;
      final centerX = 1000.0;
      final centerY = 1000.0;
      final radius = 300.0;
      final x = centerX + radius * cos(angle);
      final y = centerY + radius * sin(angle);

      // Proximidad desde último RSSI
      final lastRssi = node.rssiHistory.isNotEmpty ? node.rssiHistory.last : -100;
      final proximity = rssiToProximity(lastRssi);

      graphNodes.add(GraphNode(
        id: node.id,
        x: x,
        y: y,
        proximity: proximity,
        name: node.name,
      ));
      nodeIdToIndex[node.id!] = i;
    }

    // 4. Derivar aristas: cada par de nodos en la misma sesión es una arista
    final edges = <GraphEdge>[];
    for (var i = 0; i < nodeIds.length; i++) {
      for (var j = i + 1; j < nodeIds.length; j++) {
        edges.add(GraphEdge(
          fromId: nodeIds[i],
          toId: nodeIds[j],
          thickness: GraphEdge.thicknessFromCount(1),
        ));
      }
    }

    return LayoutResult(
      nodes: graphNodes,
      edges: edges,
      iterations: 0,
      converged: false,
    );
  }

  @override
  Future<List<GraphEdge>> getEdges(int sessionId) async {
    final sessionRows = await (_db.select(_db.scanSessionNodes)
          ..where((t) => t.sessionId.equals(sessionId)))
        .get();

    if (sessionRows.length < 2) return [];

    final nodeIds = sessionRows.map((r) => r.nodeId).toSet().toList();
    final edges = <GraphEdge>[];

    // Derivar aristas entre todos los pares de nodos en la sesión
    for (var i = 0; i < nodeIds.length; i++) {
      for (var j = i + 1; j < nodeIds.length; j++) {
        edges.add(GraphEdge(
          fromId: nodeIds[i],
          toId: nodeIds[j],
          thickness: GraphEdge.thicknessFromCount(1),
        ));
      }
    }

    return edges;
  }
}
