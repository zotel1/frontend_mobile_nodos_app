import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

class NodeDriftDataSource implements NodeLocalDataSource {
  final AppDatabase _db;

  NodeDriftDataSource(this._db);

  @override
  Stream<List<Node>> watchNodes() {
    return _db.select(_db.nodes).watch().map(
          (rows) => rows.map(_toDomain).toList(),
        );
  }

  @override
  Future<Node?> getNodeById(int id) async {
    final row = await (_db.select(_db.nodes)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null ? _toDomain(row) : null;
  }

  @override
  Future<void> upsertNode(Node node) async {
    final existing = await (_db.select(_db.nodes)
          ..where((t) => t.bleAddress.equals(node.bleAddress)))
        .getSingleOrNull();

    if (existing != null) {
      // Freeze on first detection: preservar suggestedName existente.
      // deviceType se actualiza en cada escaneo (puede cambiar).
      final companion = _toCompanion(node).copyWith(
        suggestedName: Value(existing.suggestedName ?? node.suggestedName),
      );
      await (_db.update(_db.nodes)
            ..where((t) => t.id.equals(existing.id)))
          .write(companion);
    } else {
      await _db.into(_db.nodes).insert(_toInsertCompanion(node));
    }
  }

  @override
  Future<void> deleteNode(int id) async {
    await (_db.delete(_db.nodes)..where((t) => t.id.equals(id))).go();
  }

  /// Elimina todos los nodos de la tabla nodes.
  ///
  /// QUÉ hace: ejecuta DELETE sin WHERE, borrando todas las filas.
  /// POR QUÉ: necesario para el pipeline ClearNodes → NodeListEmpty
  /// cuando se apaga Bluetooth (R5.17). Las conexiones se eliminan
  /// automáticamente por ON DELETE CASCADE.
  @override
  Future<void> deleteAllNodes() async {
    await _db.delete(_db.nodes).go();
  }

  /// Busca un nodo por su dirección BLE.
  ///
  /// QUÉ hace: query SELECT por bleAddress, retorna null si no existe.
  /// POR QUÉ: necesario para el lookup de nodos en el flujo de
  /// inserción de connections (mapear remoteId → nodeId).
  @override
  Future<Node?> getNodeByBleAddress(String bleAddress) async {
    final row = await (_db.select(_db.nodes)
          ..where((t) => t.bleAddress.equals(bleAddress)))
        .getSingleOrNull();
    return row != null ? _toDomain(row) : null;
  }

  // ── Mappers ────────────────────────────────────────────────

  Node _toDomain(NodeRow row) {
    final history = <int>[];
    // T-PR2-007: jsonDecode envuelto en try-catch para manejar JSON corrupto.
    // Si la columna rssiHistory contiene datos inválidos (ej: por un bug
    // de migración o corrupción), retornamos lista vacía en lugar de crashear
    // con FormatException.
    if (row.rssiHistory != null && row.rssiHistory!.isNotEmpty) {
      try {
        final decoded =
            jsonDecode(row.rssiHistory!) as List<dynamic>;
        history.addAll(decoded.cast<int>());
      } on FormatException {
        // JSON corrupto → lista vacía, no crashear
      }
    }

    return Node(
      id: row.id,
      bleAddress: row.bleAddress,
      name: row.name,
      color: row.color,
      firstSeen: row.firstSeen,
      lastSeen: row.lastSeen,
      rssiHistory: history,
      suggestedName: row.suggestedName,
      deviceType: row.deviceType,
      connectable: row.connectable,
      estimatedDistance: row.estimatedDistance,
    );
  }

  NodesCompanion _toCompanion(Node node) {
    final lastRssi =
        node.rssiHistory.isNotEmpty ? node.rssiHistory.last : null;
    final proximityZone =
        lastRssi != null ? rssiToProximity(lastRssi).name : null;
    final historyJson =
        node.rssiHistory.isNotEmpty ? jsonEncode(node.rssiHistory) : null;

    return NodesCompanion(
      bleAddress: Value(node.bleAddress),
      name: Value(node.name),
      color: Value(node.color),
      firstSeen: Value(node.firstSeen),
      lastSeen: Value(node.lastSeen),
      lastRssi: Value(lastRssi),
      proximityZone: Value(proximityZone),
      rssiHistory: Value(historyJson),
      suggestedName: Value(node.suggestedName),
      deviceType: Value(node.deviceType),
      connectable: Value(node.connectable),
      estimatedDistance: Value(node.estimatedDistance),
    );
  }

  NodesCompanion _toInsertCompanion(Node node) {
    final lastRssi =
        node.rssiHistory.isNotEmpty ? node.rssiHistory.last : null;
    final proximityZone =
        lastRssi != null ? rssiToProximity(lastRssi).name : null;
    final historyJson =
        node.rssiHistory.isNotEmpty ? jsonEncode(node.rssiHistory) : null;

    return NodesCompanion.insert(
      bleAddress: node.bleAddress,
      firstSeen: node.firstSeen,
      lastSeen: node.lastSeen,
      name: Value(node.name),
      color: Value(node.color),
      lastRssi: Value(lastRssi),
      proximityZone: Value(proximityZone),
      rssiHistory: Value(historyJson),
      suggestedName: Value(node.suggestedName),
      deviceType: Value(node.deviceType),
      connectable: Value(node.connectable),
      estimatedDistance: Value(node.estimatedDistance),
    );
  }
}
