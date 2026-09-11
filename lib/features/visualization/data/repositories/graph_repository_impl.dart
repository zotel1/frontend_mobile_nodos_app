import 'dart:math';

import 'package:drift/drift.dart' hide Column;
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/repositories/graph_repository.dart';

/// Implementación de [GraphRepository] usando NodeRepository y Drift.
///
/// ARCH-001:
/// - el dispositivo local ya no se representa mediante id=-1;
/// - el self-node es un Node persistente real de SQLite;
/// - isSelf define comportamiento visual, no el valor del ID.
///
/// Las aristas directas se derivan de [connections].
/// Las aristas transitivas se infieren mediante self-join SQL.
class GraphRepositoryImpl implements GraphRepository {
  final NodeRepository _nodeRepository;
  final AppDatabase _db;

  GraphRepositoryImpl(this._nodeRepository, this._db);

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Grafo principal
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  @override
  Future<LayoutResult> buildGraph(
    int scanSessionId, {
    String? myDeviceUuid,
    String? userName,
    String? userColor,
  }) async {
    // Nodos detectados durante esta sesión.
    final sessionRows = await (_db.select(
      _db.scanSessionNodes,
    )..where((table) => table.sessionId.equals(scanSessionId))).get();

    final sessionNodeIds = sessionRows.map((row) => row.nodeId).toSet();

    // ARCH-001:
    // El self-node ya es persistente y no pertenece necesariamente
    // a scan_session_nodes porque no fue "detectado" por el scanner.
    final selfNode = await _nodeRepository.getSelfNode();

    final externalIds = sessionNodeIds.where((id) => id != selfNode?.id);

    final nodePromises = externalIds.map(
      (id) => _nodeRepository.getNodeById(id),
    );

    final loadedNodes = await Future.wait(nodePromises);

    final externalNodes = loadedNodes
        .whereType<Node>()
        .where((node) => !node.isSelf)
        .toList();

    // Los IDs visibles del grafo incluyen:
    // - dispositivos detectados en esta sesión;
    // - self-node persistente.
    //
    // Esto es fundamental para que una conexión self ↔ remoto
    // pueda recuperarse desde la tabla connections.
    final visibleNodeIds = <int>{
      ...externalNodes.where((node) => node.id != null).map((node) => node.id!),
      if (selfNode?.id != null) selfNode!.id!,
    };

    final directEdges = await _getDirectEdges(visibleNodeIds);

    final transitiveEdges = await _getTransitiveEdges(visibleNodeIds);

    final edges = <GraphEdge>[...directEdges, ...transitiveEdges];

    // Cantidad de relaciones por Node.id.
    final connectionCounts = <int, int>{};

    for (final edge in edges) {
      connectionCounts[edge.fromId] = (connectionCounts[edge.fromId] ?? 0) + 1;

      connectionCounts[edge.toId] = (connectionCounts[edge.toId] ?? 0) + 1;
    }

    final graphNodes = <GraphNode>[];

    // ────────────────────────────────────────────────────────
    // Self-node persistente
    // ────────────────────────────────────────────────────────
    if (selfNode != null && selfNode.id != null) {
      final selfColor = _parseColor(selfNode.color ?? userColor);

      graphNodes.add(
        GraphNode(
          id: selfNode.id,
          x: 1000.0,
          y: 1000.0,
          z: 0.0,
          proximity: ProximityLevel.close,
          name: selfNode.name ?? userName ?? 'Mi dispositivo',
          suggestedName: selfNode.suggestedName,
          connectionCount: connectionCounts[selfNode.id!] ?? 0,
          isSelf: true,
          connectable: false,
          userColor: selfColor,
          estimatedDistance: 0.0,
        ),
      );
    }

    // Si no hay externos, devolvemos únicamente el self-node si existe.
    if (externalNodes.isEmpty) {
      return LayoutResult(
        nodes: graphNodes,
        edges: edges,
        iterations: 0,
        converged: false,
      );
    }

    // ────────────────────────────────────────────────────────
    // Posicionamiento inicial de nodos externos por proximidad
    // ────────────────────────────────────────────────────────

    final Map<String, List<int>> ringGroups = {};

    for (var i = 0; i < externalNodes.length; i++) {
      final node = externalNodes[i];

      final lastRssi = node.rssiHistory.isNotEmpty
          ? node.rssiHistory.last
          : -100;

      final distance = rssiToDistance(lastRssi);

      final ringRadius = _ringRadiusForDistance(distance);

      final ringKey = ringRadius.toStringAsFixed(0);

      ringGroups.putIfAbsent(ringKey, () => []);

      ringGroups[ringKey]!.add(i);
    }

    const centerX = 1000.0;
    const centerY = 1000.0;

    for (final entry in ringGroups.entries) {
      final indices = entry.value;
      final radius = double.parse(entry.key);

      for (var j = 0; j < indices.length; j++) {
        final index = indices[j];
        final node = externalNodes[index];

        if (node.id == null) {
          continue;
        }

        final angle = (2 * pi * j) / indices.length;

        final x = (centerX + radius * cos(angle)).clamp(50.0, 1950.0);

        final y = (centerY + radius * sin(angle)).clamp(50.0, 1950.0);

        final lastRssi = node.rssiHistory.isNotEmpty
            ? node.rssiHistory.last
            : -100;

        final proximity = rssiToProximity(lastRssi);

        graphNodes.add(
          GraphNode(
            id: node.id,
            x: x,
            y: y,
            z: 0.0,
            proximity: proximity,
            name: node.name,
            suggestedName: node.suggestedName,
            connectionCount: connectionCounts[node.id!] ?? 0,
            isSelf: false,
            connectable: node.connectable,
            userColor: _parseColor(node.color),
            estimatedDistance: node.estimatedDistance,
          ),
        );
      }
    }

    return LayoutResult(
      nodes: graphNodes,
      edges: edges,
      iterations: 0,
      converged: false,
    );
  }

  int? _parseColor(String? color) {
    if (color == null) {
      return null;
    }

    return int.tryParse(color.replaceFirst('#', '0xFF'));
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Layout inicial
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  double _ringRadiusForDistance(double distanceMeters) {
    if (distanceMeters <= 1.0) {
      return _interpolate(distanceMeters, 0.0, 1.0, 80.0, 300.0);
    }

    if (distanceMeters <= 5.0) {
      return _interpolate(distanceMeters, 1.0, 5.0, 300.0, 600.0);
    }

    if (distanceMeters <= 15.0) {
      return _interpolate(distanceMeters, 5.0, 15.0, 600.0, 1000.0);
    }

    return _interpolate(
      distanceMeters.clamp(15.0, 30.0),
      15.0,
      30.0,
      1000.0,
      1400.0,
    );
  }

  static double _interpolate(
    double value,
    double inMin,
    double inMax,
    double outMin,
    double outMax,
  ) {
    final clamped = value.clamp(inMin, inMax);

    final t = (clamped - inMin) / (inMax - inMin);

    return outMin + t * (outMax - outMin);
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Aristas directas
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<List<GraphEdge>> _getDirectEdges(Set<int> visibleNodeIds) async {
    if (visibleNodeIds.isEmpty) {
      return [];
    }

    final query =
        'SELECT from_node_id, to_node_id '
        'FROM connections '
        'WHERE from_node_id IN (${_idsPlaceholder(visibleNodeIds)}) '
        'OR to_node_id IN (${_idsPlaceholder(visibleNodeIds)})';

    final idsList = visibleNodeIds.toList();

    final variables = [
      for (final id in idsList) Variable.withInt(id),
      for (final id in idsList) Variable.withInt(id),
    ];

    final rows = await _db.customSelect(query, variables: variables).get();

    final edges = <GraphEdge>[];

    for (final row in rows) {
      final fromId = row.read<int>('from_node_id');

      final toId = row.read<int>('to_node_id');

      // Dibujamos únicamente relaciones cuyos dos extremos
      // forman parte del grafo visible actual.
      if (visibleNodeIds.contains(fromId) && visibleNodeIds.contains(toId)) {
        edges.add(
          GraphEdge(
            fromId: fromId,
            toId: toId,
            thickness: 1.0,
            edgeType: EdgeType.direct,
          ),
        );
      }
    }

    return edges;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Aristas transitivas
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<List<GraphEdge>> _getTransitiveEdges(Set<int> visibleNodeIds) async {
    if (visibleNodeIds.length < 2) {
      return [];
    }

    final query =
        '''
      SELECT DISTINCT
        a.from_node_id,
        b.to_node_id
      FROM connections a
      JOIN connections b
        ON a.to_node_id = b.from_node_id
      WHERE a.from_node_id IN (${_idsPlaceholder(visibleNodeIds)})
        AND b.to_node_id IN (${_idsPlaceholder(visibleNodeIds)})
        AND b.to_node_id != a.from_node_id
    ''';

    final idsList = visibleNodeIds.toList();

    final variables = [
      for (final id in idsList) Variable.withInt(id),
      for (final id in idsList) Variable.withInt(id),
    ];

    final rows = await _db.customSelect(query, variables: variables).get();

    final edges = <GraphEdge>[];

    for (final row in rows) {
      final fromId = row.read<int>('from_node_id');

      final toId = row.read<int>('to_node_id');

      if (visibleNodeIds.contains(fromId) && visibleNodeIds.contains(toId)) {
        edges.add(
          GraphEdge(
            fromId: fromId,
            toId: toId,
            thickness: 0.5,
            edgeType: EdgeType.transitive,
          ),
        );
      }
    }

    return edges;
  }

  String _idsPlaceholder(Set<int> ids) {
    return ids.map((_) => '?').join(', ');
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Legacy co-detection
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<Map<String, int>> getCoDetectionCounts() async {
    final query = '''
      SELECT
        a.node_id AS node_a,
        b.node_id AS node_b,
        COUNT(DISTINCT a.session_id) AS co_count
      FROM scan_session_nodes a
      JOIN scan_session_nodes b
        ON a.session_id = b.session_id
      WHERE a.node_id < b.node_id
      GROUP BY
        a.node_id,
        b.node_id
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
  // Legacy buildGraphCoDetection
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<LayoutResult> buildGraphCoDetection(
    int scanSessionId, {
    String? myDeviceUuid,
  }) async {
    final sessionRows = await (_db.select(
      _db.scanSessionNodes,
    )..where((table) => table.sessionId.equals(scanSessionId))).get();

    if (sessionRows.isEmpty) {
      return const LayoutResult(
        nodes: [],
        edges: [],
        iterations: 0,
        converged: false,
      );
    }

    final nodeIds = sessionRows.map((row) => row.nodeId).toSet().toList();

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
        edges.add(
          GraphEdge(
            fromId: id1,
            toId: id2,
            thickness: GraphEdge.thicknessFromCount(entry.value),
          ),
        );
      }
    }

    final connectionCounts = <int, int>{};

    for (final edge in edges) {
      connectionCounts[edge.fromId] = (connectionCounts[edge.fromId] ?? 0) + 1;

      connectionCounts[edge.toId] = (connectionCounts[edge.toId] ?? 0) + 1;
    }

    final graphNodes = <GraphNode>[];

    final validNodeEntities = nodeEntities.whereType<Node>().toList();

    for (var i = 0; i < validNodeEntities.length; i++) {
      final node = validNodeEntities[i];

      if (node.id == null) {
        continue;
      }

      final angle = (2 * pi * i) / validNodeEntities.length;

      const centerX = 1000.0;
      const centerY = 1000.0;
      const radius = 300.0;

      final x = centerX + radius * cos(angle);

      final y = centerY + radius * sin(angle);

      final lastRssi = node.rssiHistory.isNotEmpty
          ? node.rssiHistory.last
          : -100;

      final proximity = rssiToProximity(lastRssi);

      graphNodes.add(
        GraphNode(
          id: node.id,
          x: x,
          y: y,
          proximity: proximity,
          name: node.name,
          suggestedName: node.suggestedName,
          connectionCount: connectionCounts[node.id!] ?? 0,
          isSelf: node.isSelf,
          connectable: node.connectable,
          userColor: _parseColor(node.color),
          estimatedDistance: node.estimatedDistance,
        ),
      );
    }

    return LayoutResult(
      nodes: graphNodes,
      edges: edges,
      iterations: 0,
      converged: false,
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // getEdges
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  @override
  Future<List<GraphEdge>> getEdges(int sessionId) async {
    final sessionRows = await (_db.select(
      _db.scanSessionNodes,
    )..where((table) => table.sessionId.equals(sessionId))).get();

    final nodeIds = sessionRows.map((row) => row.nodeId).toSet();

    final selfNode = await _nodeRepository.getSelfNode();

    if (selfNode?.id != null) {
      nodeIds.add(selfNode!.id!);
    }

    if (nodeIds.length < 2) {
      return [];
    }

    return _getDirectEdges(nodeIds);
  }
}
