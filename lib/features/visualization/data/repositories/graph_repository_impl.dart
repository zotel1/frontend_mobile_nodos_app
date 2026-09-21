import 'dart:math';

import 'package:drift/drift.dart' hide Column;
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
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
/// Graph Exchange:
/// - `connections` continúa representando relaciones locales persistentes;
/// - `remote_relations` representa snapshots recibidos desde otros Nodos;
/// - los extremos remotos se materializan en `nodes` para obtener IDs locales;
/// - las relaciones remotas se representan mediante [EdgeType.reported];
/// - nunca se copian relaciones remotas hacia `connections`.
///
/// Las aristas directas se derivan de `connections`.
/// Las aristas transitivas se infieren mediante self-join SQL.
/// Las aristas reportadas se derivan de `remote_relations`.
class GraphRepositoryImpl implements GraphRepository {
  final NodeRepository _nodeRepository;
  final AppDatabase _db;
  final RemoteRelationRepository _remoteRelationRepository;

  GraphRepositoryImpl(
    this._nodeRepository,
    this._db,
    this._remoteRelationRepository,
  );

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

    final sessionExternalNodes = loadedNodes
        .whereType<Node>()
        .where((node) => !node.isSelf)
        .toList();

    // ────────────────────────────────────────────────────────
    // Graph Exchange
    // ────────────────────────────────────────────────────────
    //
    // Materializamos los extremos de remote_relations dentro de nodes
    // para que toda la visualización continúe trabajando exclusivamente
    // con Node.id reales de SQLite.
    //
    // IMPORTANTE:
    // Esto NO crea connections ni scan_session_nodes.
    final remoteGraph = await _loadRemoteGraph();

    // Un mismo nodo puede:
    // - haber sido detectado localmente;
    // - aparecer además dentro de un snapshot remoto.
    //
    // Se deduplica exclusivamente por Node.id ya reconciliado/persistido.
    final externalNodesById = <int, Node>{};

    for (final node in sessionExternalNodes) {
      final id = node.id;

      if (id != null) {
        externalNodesById[id] = node;
      }
    }

    for (final node in remoteGraph.nodes) {
      final id = node.id;

      if (id != null && id != selfNode?.id) {
        // Si ya fue observado localmente, conservamos esa representación
        // porque posee información de transporte/RSSI más rica.
        externalNodesById.putIfAbsent(id, () => node);
      }
    }

    final externalNodes = externalNodesById.values.toList();

    // Los IDs visibles del grafo incluyen:
    // - dispositivos detectados en esta sesión;
    // - dispositivos materializados desde Graph Exchange;
    // - self-node persistente.
    final visibleNodeIds = <int>{
      ...externalNodes.map((node) => node.id!),
      if (selfNode?.id != null) selfNode!.id!,
    };

    final directEdges = await _getDirectEdges(visibleNodeIds);

    final transitiveEdges = await _getTransitiveEdges(visibleNodeIds);

    // Una relación reportada solamente se dibuja si ambos extremos
    // pertenecen al grafo visible actual.
    final reportedEdges = remoteGraph.edges
        .where(
          (edge) =>
              visibleNodeIds.contains(edge.fromId) &&
              visibleNodeIds.contains(edge.toId),
        )
        .toList();

    final edges = <GraphEdge>[
      ...directEdges,
      ...transitiveEdges,
      ...reportedEdges,
    ];

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

    // Ahora este early return considera también nodos recibidos mediante
    // Graph Exchange. Si A25 reporta Watch/JBL, externalNodes ya no estará
    // vacío aunque esos dispositivos no pertenezcan a scan_session_nodes.
    if (externalNodes.isEmpty) {
      return LayoutResult(
        nodes: graphNodes,
        edges: edges,
        iterations: 0,
        converged: false,
      );
    }

    // ────────────────────────────────────────────────────────
    // Posicionamiento inicial de nodos externos
    // ────────────────────────────────────────────────────────
    //
    // Los nodos observados localmente conservan posicionamiento basado
    // en RSSI.
    //
    // Los nodos conocidos únicamente mediante Graph Exchange no tienen
    // RSSI local. Se ubican inicialmente en un anillo remoto neutral y
    // posteriormente la física de visualización puede estabilizarlos.
    final Map<String, List<int>> ringGroups = {};

    for (var i = 0; i < externalNodes.length; i++) {
      final node = externalNodes[i];

      final double ringRadius;

      if (node.rssiHistory.isNotEmpty) {
        final lastRssi = node.rssiHistory.last;

        final distance = rssiToDistance(lastRssi);

        ringRadius = _ringRadiusForDistance(distance);
      } else {
        ringRadius = 700.0;
      }

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

        final proximity = node.rssiHistory.isNotEmpty
            ? rssiToProximity(node.rssiHistory.last)
            : ProximityLevel.far;

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

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Graph Exchange
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Reconstruye la parte remota del grafo a partir de los snapshots
  /// persistidos en `remote_relations`.
  ///
  /// Cada relación:
  ///
  /// reporterUuid → remoteRef
  ///
  /// se transforma en:
  ///
  /// reporter Node.id → remote Node.id
  ///
  /// utilizando únicamente IDs locales reales de SQLite.
  Future<_RemoteGraphData> _loadRemoteGraph() async {
    final relations = await _remoteRelationRepository.watchAll().first;

    if (relations.isEmpty) {
      return const _RemoteGraphData(nodes: [], edges: []);
    }

    final nodesById = <int, Node>{};
    final edges = <GraphEdge>[];
    final edgeKeys = <String>{};

    for (final relation in relations) {
      final reporterUuid = relation.reporterUuid.trim();

      if (reporterUuid.isEmpty) {
        continue;
      }

      // El reporter debe ser una instalación Nodos conocida.
      //
      // No fabricamos un reporter sin identidad porque normalmente ya fue
      // reconciliado al recibir NodosIdentity antes del graph payload.
      final reporterNode = await _nodeRepository.getNodeByDeviceUuid(
        reporterUuid,
      );

      if (reporterNode == null ||
          reporterNode.id == null ||
          reporterNode.isSelf) {
        continue;
      }

      final remoteNode = await _resolveRemoteNode(relation);

      if (remoteNode == null || remoteNode.id == null) {
        continue;
      }

      if (remoteNode.id == reporterNode.id) {
        continue;
      }

      nodesById[reporterNode.id!] = reporterNode;
      nodesById[remoteNode.id!] = remoteNode;

      final edgeKey = '${reporterNode.id}->${remoteNode.id}';

      if (!edgeKeys.add(edgeKey)) {
        continue;
      }

      edges.add(
        GraphEdge(
          fromId: reporterNode.id!,
          toId: remoteNode.id!,
          thickness: 1.0,
          edgeType: EdgeType.reported,
        ),
      );
    }

    return _RemoteGraphData(nodes: nodesById.values.toList(), edges: edges);
  }

  /// Resuelve el extremo remoto de una relación.
  ///
  /// Existen dos estrategias y NO son intercambiables:
  ///
  /// 1. Nodos:
  ///    identidad global estable mediante deviceUuid.
  ///
  /// 2. BLE genérico:
  ///    identidad namespaced mediante remoteRef.
  ///
  /// Nunca se intenta fusionar un BLE genérico por nombre.
  Future<Node?> _resolveRemoteNode(RemoteRelation relation) async {
    final remoteDeviceUuid = _normalizeNullable(relation.remoteDeviceUuid);
    final remoteRef = relation.remoteRef.trim();

    if (remoteDeviceUuid != null) {
      final existing = await _nodeRepository.getNodeByDeviceUuid(
        remoteDeviceUuid,
      );

      if (existing != null) {
        return existing;
      }

      final now = relation.lastReceivedAt;

      final node = Node(
        deviceUuid: remoteDeviceUuid,
        isSelf: false,
        name: _normalizeNullable(relation.remoteName),
        color: _normalizeNullable(relation.remoteColor),
        firstSeen: now,
        lastSeen: now,
        deviceType: _normalizeNullable(relation.remoteDeviceType),
        connectable: false,
      );

      await _nodeRepository.upsertNode(node);

      return _nodeRepository.getNodeByDeviceUuid(remoteDeviceUuid);
    }

    if (remoteRef.isEmpty) {
      return null;
    }

    final existing = await _nodeRepository.getNodeByRemoteRef(remoteRef);

    if (existing != null) {
      return existing;
    }

    final now = relation.lastReceivedAt;

    final node = Node(
      remoteRef: remoteRef,
      isSelf: false,
      name: _normalizeNullable(relation.remoteName),
      color: _normalizeNullable(relation.remoteColor),
      firstSeen: now,
      lastSeen: now,
      deviceType: _normalizeNullable(relation.remoteDeviceType),
      connectable: false,
    );

    await _nodeRepository.upsertNode(node);

    return _nodeRepository.getNodeByRemoteRef(remoteRef);
  }

  String? _normalizeNullable(String? value) {
    final normalized = value?.trim();

    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
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

/// Resultado interno de materializar la porción remota del grafo.
///
/// No forma parte del dominio público: solamente permite transportar
/// los nodos persistidos y las aristas reportadas durante buildGraph().
class _RemoteGraphData {
  final List<Node> nodes;
  final List<GraphEdge> edges;

  const _RemoteGraphData({required this.nodes, required this.edges});
}
