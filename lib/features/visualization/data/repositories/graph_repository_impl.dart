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
      {String? myDeviceUuid, String? userName, String? userColor}) async {
    // Obtener todos los nodos detectados en esta sesión
    final sessionRows = await (_db.select(_db.scanSessionNodes)
          ..where((t) => t.sessionId.equals(scanSessionId)))
        .get();

    // ── Parsear userColor de hex string a ARGB int ──
    // userColor llega como hex string "#E91E63" desde el perfil.
    // Se convierte a 0xFFE91E63 para almacenar en GraphNode.userColor.
    final int? userColorInt = userColor != null
        ? int.tryParse(userColor.replaceFirst('#', '0xFF'))
        : null;

    // ── Self-node sintético (REQ-SN-01) ──
    // Siempre se crea al inicio de la lista, incluso con 0 nodos externos.
    // id=-1 no colisiona con IDs de Drift (≥1 por autoincrement).
    // Posición centro (1000, 1000) — anclado, no se mueve con FR.
    final graphNodes = <GraphNode>[];
    graphNodes.add(GraphNode(
      id: -1,
      x: 1000.0,
      y: 1000.0,
      z: 0.0,
      proximity: ProximityLevel.close,
      name: userName ?? 'Mi dispositivo',
      connectionCount: 0,
      isSelf: true,
      connectable: false,
      userColor: userColorInt,
    ));

    // Si no hay nodos externos, retornar SOLO el self-node.
    // Ya no se retorna LayoutResult vacío — siempre ≥1 nodo.
    if (sessionRows.isEmpty) {
      return LayoutResult(
        nodes: graphNodes,
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

    // 7. Agregar nodos externos a la lista (ya contiene el self-node).
    //    metadata propagada desde Node (connectable, userColor, distance).
    final validNodeEntities = nodeEntities.where((n) => n != null).toList();

    // ── Posiciones iniciales por proximidad (REQ-GL-01) ──
    // Reemplaza el anillo único de 300px por anillos concéntricos
    // basados en rssiToDistance(). Nodos más cercanos (RSSI fuerte)
    // se posicionan en anillos interiores; nodos lejanos en exteriores.
    // La distribución angular es equiespaciada dentro de cada anillo.
    //
    // Agrupar nodos por anillo para distribuir el ángulo equiespaciadamente
    final Map<String, List<int>> ringGroups = {};
    final Map<int, double> nodeRingRadii = {};
    for (var i = 0; i < validNodeEntities.length; i++) {
      final node = validNodeEntities[i]!;
      final lastRssi =
          node.rssiHistory.isNotEmpty ? node.rssiHistory.last : -100;
      final dist = rssiToDistance(lastRssi);

      // Mapear distancia estimada → radio del anillo (interpolado)
      final ringRadius = _ringRadiusForDistance(dist);
      final ringKey = ringRadius.toStringAsFixed(0);
      ringGroups.putIfAbsent(ringKey, () => []);
      ringGroups[ringKey]!.add(i);
      nodeRingRadii[i] = ringRadius;
    }

    // Posicionar nodos en sus anillos con ángulo equiespaciado
    final centerX = 1000.0;
    final centerY = 1000.0;
    for (final entry in ringGroups.entries) {
      final indices = entry.value;
      final radius = double.parse(entry.key);
      for (var j = 0; j < indices.length; j++) {
        final idx = indices[j];
        final node = validNodeEntities[idx]!;
        final angle = (2 * pi * j) / indices.length;
        final x = centerX + radius * cos(angle);
        final y = centerY + radius * sin(angle);

        // Proximidad desde último RSSI
        final lastRssi =
            node.rssiHistory.isNotEmpty ? node.rssiHistory.last : -100;
        final proximity = rssiToProximity(lastRssi);

        // PR2: userColor desde Node.color
        final int? nodeUserColor = node.color != null
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
          userColor: nodeUserColor,
          estimatedDistance: node.estimatedDistance,
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

  /// Mapea una distancia estimada en metros al radio del anillo
  /// correspondiente para el layout inicial (REQ-GL-01).
  ///
  /// Rangos:
  /// | Distancia estimada | Radio del anillo |
  /// |---|---|
  /// | 0–0.5m | 80–150px |
  /// | 0.5–2m | 150–400px |
  /// | 2–5m | 400–900px |
  /// | 5–10m | 900–1500px |
  /// | >10m o sin RSSI | 1500–1850px |
  ///
  /// Usa [_interpolate] para mapeo lineal dentro de cada rango.
  double _ringRadiusForDistance(double distanceMeters) {
    if (distanceMeters <= 0.5) {
      return _interpolate(distanceMeters, 0.0, 0.5, 80.0, 150.0);
    }
    if (distanceMeters <= 2.0) {
      return _interpolate(distanceMeters, 0.5, 2.0, 150.0, 400.0);
    }
    if (distanceMeters <= 5.0) {
      return _interpolate(distanceMeters, 2.0, 5.0, 400.0, 900.0);
    }
    if (distanceMeters <= 10.0) {
      return _interpolate(distanceMeters, 5.0, 10.0, 900.0, 1500.0);
    }
    // >10m o sin datos RSSI → anillo exterior
    return _interpolate(
        distanceMeters.clamp(10.0, 20.0), 10.0, 20.0, 1500.0, 1850.0);
  }

  /// Interpolación lineal entre [inMin]→[outMin] y [inMax]→[outMax].
  ///
  /// QUÉ: mapea un valor [value] del rango de entrada al rango de salida.
  /// Clampea [value] al rango [inMin, inMax] para evitar extrapolación.
  ///
  /// POR QUÉ: necesaria para mapear distancias continuas en metros a
  /// radios de anillo continuos en píxeles para el layout inicial.
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
        connectable: node.connectable,
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
