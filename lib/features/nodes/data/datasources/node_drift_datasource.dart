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
    return _db
        .select(_db.nodes)
        .watch()
        .map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<Node?> getNodeById(int id) async {
    final row = await (_db.select(
      _db.nodes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();

    return row != null ? _toDomain(row) : null;
  }

  @override
  Future<Node?> getNodeByBleAddress(String bleAddress) async {
    final row = await (_db.select(
      _db.nodes,
    )..where((t) => t.bleAddress.equals(bleAddress))).getSingleOrNull();

    return row != null ? _toDomain(row) : null;
  }

  @override
  Future<Node?> getNodeByDeviceUuid(String deviceUuid) async {
    final row = await (_db.select(
      _db.nodes,
    )..where((t) => t.deviceUuid.equals(deviceUuid))).getSingleOrNull();

    return row != null ? _toDomain(row) : null;
  }

  @override
  Future<Node?> getSelfNode() async {
    final row =
        await (_db.select(_db.nodes)
              ..where((t) => t.isSelf.equals(true))
              ..limit(1))
            .getSingleOrNull();

    return row != null ? _toDomain(row) : null;
  }

  @override
  Future<void> upsertNode(Node node) async {
    final existing = await _findExistingNode(node);

    if (existing != null) {
      await _updateExisting(existing, node);
      return;
    }

    try {
      await _db.into(_db.nodes).insert(_toCompanion(node, isInsert: true));
    } catch (_) {
      // Puede ocurrir si dos operaciones concurrentes intentan insertar
      // el mismo deviceUuid o bleAddress.
      final raced = await _findExistingNode(node);

      if (raced == null) {
        rethrow;
      }

      await _updateExisting(raced, node);
    }
  }

  /// Busca un registro existente utilizando la prioridad de identidad:
  ///
  /// 1. id persistente;
  /// 2. deviceUuid estable Nodos;
  /// 3. bleAddress / remoteId.
  ///
  /// Esto evita utilizar bleAddress como identidad universal.
  Future<NodeRow?> _findExistingNode(Node node) async {
    if (node.id != null) {
      final byId = await (_db.select(
        _db.nodes,
      )..where((t) => t.id.equals(node.id!))).getSingleOrNull();

      if (byId != null) return byId;
    }

    if (node.deviceUuid != null) {
      final byUuid = await (_db.select(
        _db.nodes,
      )..where((t) => t.deviceUuid.equals(node.deviceUuid!))).getSingleOrNull();

      if (byUuid != null) return byUuid;
    }

    if (node.bleAddress != null) {
      final byBle = await (_db.select(
        _db.nodes,
      )..where((t) => t.bleAddress.equals(node.bleAddress!))).getSingleOrNull();

      if (byBle != null) return byBle;
    }

    return null;
  }

  Future<void> _updateExisting(NodeRow existing, Node incoming) async {
    final companion = _toCompanion(incoming, isInsert: false).copyWith(
      // Freeze on first detection.
      suggestedName: Value(existing.suggestedName ?? incoming.suggestedName),

      // No perder una identidad estable ya conocida.
      deviceUuid: Value(incoming.deviceUuid ?? existing.deviceUuid),

      // No perder la dirección BLE conocida si el update viene
      // desde una entidad que no dispone de transporte BLE.
      bleAddress: Value(incoming.bleAddress ?? existing.bleAddress),

      // Una vez identificado como self no debe degradarse accidentalmente.
      isSelf: Value(existing.isSelf || incoming.isSelf),
    );

    await (_db.update(
      _db.nodes,
    )..where((t) => t.id.equals(existing.id))).write(companion);
  }

  @override
  Future<void> deleteNode(int id) async {
    await (_db.delete(_db.nodes)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> deleteAllNodes() async {
    // BUG-002 corregirá la semántica de esta operación.
    // Por ahora preservamos el comportamiento existente.
    await _db.delete(_db.nodes).go();
  }

  // ── Mappers ────────────────────────────────────────────────

  Node _toDomain(NodeRow row) {
    final history = <int>[];

    if (row.rssiHistory != null && row.rssiHistory!.isNotEmpty) {
      try {
        final decoded = jsonDecode(row.rssiHistory!) as List<dynamic>;

        history.addAll(decoded.cast<int>());
      } on FormatException {
        // JSON corrupto → historial vacío.
      } on TypeError {
        // JSON válido pero con estructura inesperada.
      }
    }

    return Node(
      id: row.id,
      deviceUuid: row.deviceUuid,
      bleAddress: row.bleAddress,
      isSelf: row.isSelf,
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

  NodesCompanion _toCompanion(Node node, {required bool isInsert}) {
    final lastRssi = node.rssiHistory.isNotEmpty ? node.rssiHistory.last : null;

    final proximityZone = lastRssi != null
        ? rssiToProximity(lastRssi).name
        : null;

    final historyJson = node.rssiHistory.isNotEmpty
        ? jsonEncode(node.rssiHistory)
        : null;

    if (isInsert) {
      return NodesCompanion.insert(
        deviceUuid: Value(node.deviceUuid),
        bleAddress: Value(node.bleAddress),
        isSelf: Value(node.isSelf),
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

    return NodesCompanion(
      deviceUuid: Value(node.deviceUuid),
      bleAddress: Value(node.bleAddress),
      isSelf: Value(node.isSelf),
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
}
