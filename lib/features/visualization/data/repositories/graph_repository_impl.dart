import 'dart:math';

import 'package:drift/drift.dart' hide Column;
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/repositories/graph_repository.dart';

/// Implementación de [GraphRepository] usando NodeRepository y Drift.
///
/// PR2: las aristas ahora se derivan de la tabla [connections] en vez de
/// co-detecciones en scan_session_nodes (R5.1). Las aristas directas
/// provienen de conexiones reales (A↔B mutuamente conectados).
/// Las aristas transitivas (1-hop) se infieren vía SQL self-join (R5.3)
/// y se marcan con EdgeType.transitive para renderizado dashed.
///
/// El método legacy [buildGraphCoDetection] se preserva para rollback.
class GraphRepositoryImpl implements GraphRepository {
  final NodeRepository _nodeRepository;
  final AppDatabase _db;

  GraphRepositoryImpl(this._nodeRepository, this._db);

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // PR2: Nuevo buildGraph — usa tabla connections
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  @override
  Future<LayoutResult> buildGraph(int scanSessionId,
      {String? myDeviceUuid}) async {
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
    final nodeIds = sessionRows.map((r) => r.nodeId).toList();
    final nodePromises = nodeIds.map((id) => _nodeRepository.getNodeById(id));
    final nodeEntities = await Future.wait(nodePromises);

    final sessionNodeIdSet = nodeIds.toSet();

    // 3. Derivar aristas directas desde la tabla connections (R5.1).
    final directEdges = await _getDirectEdges(sessionNodeIdSet);

    // 4. Derivar aristas transitivas 1-hop (R5.3).
    final transitiveEdges = await _getTransitiveEdges(sessionNodeIdSet);

    // 5. Merge: directas + transitivas.
    //    Las transitivas usan thickness menor (0.5) y edgeType: transitive.
    final edges = <GraphEdge>[...directEdges, ...transitiveEdges];

    // 6. Calcular connectionCount: cuántas aristas tiene cada nodo.
    //    LinkedIn Maps style — determina el radio del nodo.
    final connectionCounts = <int, int>{};
    for (final edge in edges) {
      connectionCounts[edge.fromId] =
          (connectionCounts[edge.fromId] ?? 0) + 1;
      connectionCounts[edge.toId] =
          (connectionCounts[edge.toId] ?? 0) + 1;
    }

    // 7. Crear GraphNode con posiciones iniciales en círculo y
    //    metadata propagada desde Node (connectable, userColor, distance).
    final graphNodes = <GraphNode>[];
    final validNodeEntities = nodeEntities.where((n) => n != null).toList();
    for (var i = 0; i < validNodeEntities.length; i++) {
      final node = validNodeEntities[i]!;

      // Posición inicial circular (será refinada por FR)
      final angle = (2 * pi * i) / validNodeEntities.length;
      final centerX = 1000.0;
      final centerY = 1000.0;
      final radius = 300.0;
      final x = centerX + radius * cos(angle);
      final y = centerY + radius * sin(angle);

      // Proximidad desde último RSSI
      final lastRssi = node.rssiHistory.isNotEmpty ? node.rssiHistory.last : -100;
      final proximity = rssiToProximity(lastRssi);

      // PR2: userColor desde Node.color (formato hex string "#FF2196F3")
      final int? userColor = node.color != null
          ? int.tryParse(node.color!.replaceFirst('#', '0xFF'))
          : null;

      graphNodes.add(GraphNode(
        id: node.id,
        x: x,
        y: y,
        proximity: proximity,
        name: node.name,
        suggestedName: node.suggestedName,
        connectionCount: connectionCounts[node.id!] ?? 0,
        isSelf: myDeviceUuid != null && node.bleAddress == myDeviceUuid,
        connectable: node.connectable,
        userColor: userColor,
        estimatedDistance: node.estimatedDistance,
      ));
    }

    return LayoutResult(
      nodes: graphNodes,
      edges: edges,
      iterations: 0,
      converged: false,
    );
  }

  /// Obtiene aristas directas desde la tabla [connections] para los nodos
  /// de la sesión activa.
  ///
  /// QUÉ: consulta SELECT * FROM connections WHERE from_node_id IN (?) OR
  /// to_node_id IN (?), filtrando para que ambos extremos estén en
  /// [sessionNodeIds].
  ///
  /// POR QUÉ: R5.1 — edges must come from connections table, not co-detection.
  /// Solo se crean aristas entre pares de nodos que tienen una conexión
  /// mutua registrada (ambos extremos están en la sesión activa).
  Future<List<GraphEdge>> _getDirectEdges(Set<int> sessionNodeIds) async {
    if (sessionNodeIds.isEmpty) return [];

    final query = 'SELECT from_node_id, to_node_id FROM connections '
        'WHERE from_node_id IN (${_idsPlaceholder(sessionNodeIds)}) '
        'OR to_node_id IN (${_idsPlaceholder(sessionNodeIds)})';

    // Usar variables posicionales con los IDs expandidos dos veces
    final idsList = sessionNodeIds.toList();
    final variables = [
      for (final id in idsList) Variable.withInt(id),
      for (final id in idsList) Variable.withInt(id),
    ];

    final rows = await _db.customSelect(
      query,
      variables: variables,
    ).get();

    final edges = <GraphEdge>[];
    for (final row in rows) {
      final fromId = row.read<int>('from_node_id');
      final toId = row.read<int>('to_node_id');

      // Ambos extremos deben estar en la sesión activa
      if (sessionNodeIds.contains(fromId) && sessionNodeIds.contains(toId)) {
        edges.add(GraphEdge(
          fromId: fromId,
          toId: toId,
          thickness: 1.0,
          edgeType: EdgeType.direct,
        ));
      }
    }
    return edges;
  }

  /// Infiere aristas transitivas 1-hop: si A→B y B→C existen en
  /// [connections], genera A—C con [EdgeType.transitive].
  ///
  /// QUÉ: SQL self-join sobre connections para encontrar pares (A, C)
  /// donde A está conectado a B y B a C, pero A≠C. Ambos A y C deben
  /// estar en [sessionNodeIds].
  ///
  /// POR QUÉ: R5.3 — 1-hop transitive edges must render dashed at 50%
  /// opacity. Esto revela relaciones indirectas entre nodos que comparten
  /// una conexión en común.
  ///
  /// Retorna lista de GraphEdge con edgeType: transitive y thickness 0.5.
  Future<List<GraphEdge>> _getTransitiveEdges(Set<int> sessionNodeIds) async {
    if (sessionNodeIds.length < 2) return [];

    final query = '''
      SELECT DISTINCT a.from_node_id, b.to_node_id
      FROM connections a
      JOIN connections b ON a.to_node_id = b.from_node_id
      WHERE a.from_node_id IN (${_idsPlaceholder(sessionNodeIds)})
        AND b.to_node_id IN (${_idsPlaceholder(sessionNodeIds)})
        AND b.to_node_id != a.from_node_id
    ''';

    final idsList = sessionNodeIds.toList();
    final variables = [
      for (final id in idsList) Variable.withInt(id),
      for (final id in idsList) Variable.withInt(id),
    ];

    final rows = await _db.customSelect(
      query,
      variables: variables,
    ).get();

    final edges = <GraphEdge>[];
    for (final row in rows) {
      final fromId = row.read<int>('from_node_id');
      final toId = row.read<int>('to_node_id');

      // Ambos extremos deben estar en la sesión activa
      if (sessionNodeIds.contains(fromId) && sessionNodeIds.contains(toId)) {
        edges.add(GraphEdge(
          fromId: fromId,
          toId: toId,
          thickness: 0.5,
          edgeType: EdgeType.transitive,
        ));
      }
    }
    return edges;
  }

  /// Genera placeholder SQL `?, ?, ...` para los IDs en [ids].
  String _idsPlaceholder(Set<int> ids) {
    return ids.map((_) => '?').join(', ');
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T2.1: Co-deteccion counting query (legacy, preservado)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Obtiene el conteo de co-detecciones para todos los pares de nodos.
  ///
  /// Legacy: usado por buildGraphCoDetection() para rollback.
  Future<Map<String, int>> getCoDetectionCounts() async {
    final query = '''
      SELECT a.node_id AS node_a, b.node_id AS node_b,
             COUNT(DISTINCT a.session_id) AS co_count
      FROM scan_session_nodes a
      JOIN scan_session_nodes b ON a.session_id = b.session_id
      WHERE a.node_id < b.node_id
      GROUP BY a.node_id, b.node_id
    ''';
    final rows = await _db.customSelect(query).get();
    final result = <String, int>{};
    for (final row in rows) {
      final nodeA = row.read<int>('node_a');
      final nodeB = row.read<int>('node_b');
      final count = row.read<int>('co_count');
      result['$nodeA-$nodeB'] = count;
    }
    return result;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Legacy: buildGraphCoDetection (rollback)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Legacy: construye el grafo usando co-detecciones (scan_session_nodes)
  /// en lugar de la tabla connections.
  ///
  /// Preservado para rollback en caso de que el nuevo modelo de conexiones
  /// presente problemas. NO se usa en el flujo normal después de PR2.
  Future<LayoutResult> buildGraphCoDetection(int scanSessionId,
      {String? myDeviceUuid}) async {
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

    final nodeIds = sessionRows.map((r) => r.nodeId).toSet().toList();
    final nodePromises = nodeIds.map((id) => _nodeRepository.getNodeById(id));
    final nodeEntities = await Future.wait(nodePromises);

    final coDetectionCounts = await getCoDetectionCounts();
    final edges = <GraphEdge>[];

    final sessionNodeIdSet = nodeIds.toSet();
    for (final entry in coDetectionCounts.entries) {
      final parts = entry.key.split('-');
      final id1 = int.parse(parts[0]);
      final id2 = int.parse(parts[1]);

      if (sessionNodeIdSet.contains(id1) && sessionNodeIdSet.contains(id2)) {
        edges.add(GraphEdge(
          fromId: id1,
          toId: id2,
          thickness: GraphEdge.thicknessFromCount(entry.value),
        ));
      }
    }

    final connectionCounts = <int, int>{};
    for (final edge in edges) {
      connectionCounts[edge.fromId] =
          (connectionCounts[edge.fromId] ?? 0) + 1;
      connectionCounts[edge.toId] =
          (connectionCounts[edge.toId] ?? 0) + 1;
    }

    final graphNodes = <GraphNode>[];
    final validNodeEntities = nodeEntities.where((n) => n != null).toList();
    for (var i = 0; i < validNodeEntities.length; i++) {
      final node = validNodeEntities[i]!;

      final angle = (2 * pi * i) / validNodeEntities.length;
      final centerX = 1000.0;
      final centerY = 1000.0;
      final radius = 300.0;
      final x = centerX + radius * cos(angle);
      final y = centerY + radius * sin(angle);

      final lastRssi = node.rssiHistory.isNotEmpty ? node.rssiHistory.last : -100;
      final proximity = rssiToProximity(lastRssi);

      graphNodes.add(GraphNode(
        id: node.id,
        x: x,
        y: y,
        proximity: proximity,
        name: node.name,
        suggestedName: node.suggestedName,
        connectionCount: connectionCounts[node.id!] ?? 0,
        isSelf: myDeviceUuid != null && node.bleAddress == myDeviceUuid,
      ));
    }

    return LayoutResult(
      nodes: graphNodes,
      edges: edges,
      iterations: 0,
      converged: false,
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // getEdges — también usa connections (PR2)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  @override
  Future<List<GraphEdge>> getEdges(int sessionId) async {
    final sessionRows = await (_db.select(_db.scanSessionNodes)
          ..where((t) => t.sessionId.equals(sessionId)))
        .get();

    if (sessionRows.length < 2) return [];

    final nodeIds = sessionRows.map((r) => r.nodeId).toSet();

    return _getDirectEdges(nodeIds);
  }
}
