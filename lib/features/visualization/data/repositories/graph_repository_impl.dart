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
/// deriva aristas desde la tabla scan_session_nodes de Drift usando
/// co-detecciones reales (T2.1-T2.3).
///
/// Las aristas ya NO son clique completo: solo se crean entre pares
/// de nodos que fueron detectados juntos en al menos una sesión.
/// El grosor de cada arista se deriva de la cantidad de co-detecciones.
///
/// Las posiciones iniciales de los nodos se distribuyen en círculo
/// hasta que CalculateLayout aplique Fruchterman-Reingold.
class GraphRepositoryImpl implements GraphRepository {
  final NodeRepository _nodeRepository;
  final AppDatabase _db;

  GraphRepositoryImpl(this._nodeRepository, this._db);

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T2.1: Co-deteccion counting query
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Obtiene el conteo de co-detecciones para todos los pares de nodos.
  ///
  /// QUÉ: consulta scan_session_nodes uniéndola consigo misma para
  /// encontrar pares de nodos que aparecieron en las mismas sesiones.
  /// El conteo usa COUNT(DISTINCT session_id) para evitar duplicados.
  ///
  /// POR QUÉ: las aristas del grafo deben reflejar relaciones reales,
  /// no un clique completo. Solo los nodos co-detectados deben tener
  /// aristas visibles.
  ///
  /// Retorna un Map donde la clave es "menorId-mayorId" (ordenado para
  /// evitar duplicados invertidos) y el valor es el conteo de sesiones
  /// compartidas.
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
  // T2.2-T2.3: buildGraph con co-detection edges reales
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
    final nodeIds = sessionRows.map((r) => r.nodeId).toSet().toList();
    final nodePromises = nodeIds.map((id) => _nodeRepository.getNodeById(id));
    final nodeEntities = await Future.wait(nodePromises);

    // 3. Derivar aristas desde co-detecciones reales.
    //    Ya NO es un clique completo — solo pares con count > 0.
    //    El grosor de cada arista usa thicknessFromCount() con el
    //    conteo real de co-detecciones.
    final coDetectionCounts = await getCoDetectionCounts();
    final edges = <GraphEdge>[];

    // Para nodos de esta sesión, buscar aristas en los conteos globales
    final sessionNodeIdSet = nodeIds.toSet();
    for (final entry in coDetectionCounts.entries) {
      final parts = entry.key.split('-');
      final id1 = int.parse(parts[0]);
      final id2 = int.parse(parts[1]);

      // Solo crear arista si AMBOS nodos están en esta sesión
      if (sessionNodeIdSet.contains(id1) && sessionNodeIdSet.contains(id2)) {
        edges.add(GraphEdge(
          fromId: id1,
          toId: id2,
          thickness: GraphEdge.thicknessFromCount(entry.value),
        ));
      }
    }

    // 4. Calcular connectionCount: cuántas aristas tiene cada nodo.
    //    LinkedIn Maps style — determina el radio del nodo.
    final connectionCounts = <int, int>{};
    for (final edge in edges) {
      connectionCounts[edge.fromId] =
          (connectionCounts[edge.fromId] ?? 0) + 1;
      connectionCounts[edge.toId] =
          (connectionCounts[edge.toId] ?? 0) + 1;
    }

    // 5. Crear GraphNode con posiciones iniciales en círculo y
    //    connectionCount computado.
    final graphNodes = <GraphNode>[];
    final nodeIdToIndex = <int, int>{};
    final validNodeEntities = nodeEntities.where((n) => n != null).toList();
    for (var i = 0; i < validNodeEntities.length; i++) {
      final node = validNodeEntities[i]!;

      // Posición inicial circular (será refinada por FR en PR2)
      final angle = (2 * pi * i) / validNodeEntities.length;
      final centerX = 1000.0;
      final centerY = 1000.0;
      final radius = 300.0;
      final x = centerX + radius * cos(angle);
      final y = centerY + radius * sin(angle);

      // Proximidad desde último RSSI.
      // T-PR2-008: Si no hay datos de RSSI (rssiHistory vacío), no forzar
      // un valor centinela. Usar rssiToProximity solo cuando hay datos.
      // Sin datos → se usa un valor default de proximidad "far" que es
      // neutral (no falso positivo de "-100").
      final lastRssi = node.rssiHistory.isNotEmpty ? node.rssiHistory.last : null;
      final proximity = lastRssi != null
          ? rssiToProximity(lastRssi)
          : ProximityLevel.far;

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
      nodeIdToIndex[node.id!] = i;
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

    // Usar co-detecciones reales globales (T2.2-T2.3)
    final coDetectionCounts = await getCoDetectionCounts();
    final sessionNodeIdSet = nodeIds.toSet();
    final edges = <GraphEdge>[];

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

    return edges;
  }
}
