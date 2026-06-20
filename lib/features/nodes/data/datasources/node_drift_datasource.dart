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

  // ── Mappers ────────────────────────────────────────────────

  Node _toDomain(NodeRow row) {
    final history = <int>[];
    if (row.rssiHistory != null && row.rssiHistory!.isNotEmpty) {
      final decoded =
          jsonDecode(row.rssiHistory!) as List<dynamic>;
      history.addAll(decoded.cast<int>());
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
    );
  }
}
