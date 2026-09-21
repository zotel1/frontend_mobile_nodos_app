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
  Future<Node?> getNodeByRemoteRef(String remoteRef) async {
    final row =
        await (_db.select(_db.nodes)
              ..where((t) => t.remoteRef.equals(remoteRef))
              ..limit(1))
            .getSingleOrNull();

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
      // la misma identidad estable, dirección BLE o remoteRef.
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
  /// 3. bleAddress / remoteId observado localmente;
  /// 4. remoteRef namespaced recibido mediante Graph Exchange.
  ///
  /// Esto evita utilizar bleAddress como identidad universal y permite
  /// materializar de forma estable dispositivos BLE genéricos conocidos
  /// únicamente a través de otra instalación Nodos.
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

    if (node.remoteRef != null) {
      final byRemoteRef =
          await (_db.select(_db.nodes)
                ..where((t) => t.remoteRef.equals(node.remoteRef!))
                ..limit(1))
              .getSingleOrNull();

      if (byRemoteRef != null) return byRemoteRef;
    }

    return null;
  }

  Future<void> _updateExisting(NodeRow existing, Node incoming) async {
    final companion = _toCompanion(incoming, isInsert: false).copyWith(
      // Freeze on first detection.
      suggestedName: Value(existing.suggestedName ?? incoming.suggestedName),

      // No perder una identidad estable Nodos ya conocida.
      deviceUuid: Value(incoming.deviceUuid ?? existing.deviceUuid),

      // No perder la dirección BLE conocida si el update viene
      // desde una entidad que no dispone de transporte BLE.
      bleAddress: Value(incoming.bleAddress ?? existing.bleAddress),

      // No perder la referencia remota namespaced si el update proviene
      // de otra fuente que no la conoce.
      remoteRef: Value(incoming.remoteRef ?? existing.remoteRef),

      // Una vez identificado como self no debe degradarse accidentalmente.
      isSelf: Value(existing.isSelf || incoming.isSelf),
    );

    await (_db.update(
      _db.nodes,
    )..where((t) => t.id.equals(existing.id))).write(companion);
  }

  @override
  Future<Node?> reconcileNodeIdentity(
    int nodeId, {
    required String deviceUuid,
    required String name,
    required String color,
  }) async {
    return _db.transaction(() async {
      // Nodo detectado mediante la dirección BLE actual.
      final current = await (_db.select(
        _db.nodes,
      )..where((t) => t.id.equals(nodeId))).getSingleOrNull();

      if (current == null) {
        return null;
      }

      // Buscar si esta identidad estable Nodos ya pertenece
      // a otro registro persistido.
      final canonical =
          await (_db.select(_db.nodes)
                ..where((t) => t.deviceUuid.equals(deviceUuid))
                ..limit(1))
              .getSingleOrNull();

      // ─────────────────────────────────────────────────────
      // CASO 1
      // El UUID todavía no pertenece a otro Node.
      //
      // Podemos enriquecer directamente el nodo detectado.
      // ─────────────────────────────────────────────────────
      if (canonical == null || canonical.id == current.id) {
        await (_db.update(
          _db.nodes,
        )..where((t) => t.id.equals(current.id))).write(
          NodesCompanion(
            deviceUuid: Value(deviceUuid),
            name: Value(name),
            color: Value(color),
          ),
        );

        final updated = await (_db.select(
          _db.nodes,
        )..where((t) => t.id.equals(current.id))).getSingle();

        return _toDomain(updated);
      }

      // ─────────────────────────────────────────────────────
      // CASO 2
      // El UUID ya pertenece a otro Node.
      //
      // canonical = identidad persistente conocida.
      // current   = registro creado por la dirección BLE actual.
      //
      // Ambos representan el mismo dispositivo físico.
      // ─────────────────────────────────────────────────────

      final canonicalId = canonical.id;
      final duplicateId = current.id;

      // -----------------------------------------------------
      // 2.1 Reconciliar CONNECTIONS donde el duplicado
      //     aparece como origen.
      //
      // Insertamos primero la relación equivalente utilizando
      // INSERT OR IGNORE para respetar:
      //
      // UNIQUE(from_node_id, to_node_id)
      // -----------------------------------------------------
      final outgoingConnections = await (_db.select(
        _db.connections,
      )..where((t) => t.fromNodeId.equals(duplicateId))).get();

      for (final connection in outgoingConnections) {
        final newToId = connection.toNodeId == duplicateId
            ? canonicalId
            : connection.toNodeId;

        // No crear self-loop después de fusionar identidades.
        if (newToId == canonicalId) {
          continue;
        }

        await _db
            .into(_db.connections)
            .insert(
              ConnectionsCompanion.insert(
                fromNodeId: canonicalId,
                toNodeId: newToId,
                createdAt: connection.createdAt,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }

      // -----------------------------------------------------
      // 2.2 Reconciliar CONNECTIONS donde el duplicado
      //     aparece como destino.
      // -----------------------------------------------------
      final incomingConnections = await (_db.select(
        _db.connections,
      )..where((t) => t.toNodeId.equals(duplicateId))).get();

      for (final connection in incomingConnections) {
        final newFromId = connection.fromNodeId == duplicateId
            ? canonicalId
            : connection.fromNodeId;

        // Tampoco conservar canonical → canonical.
        if (newFromId == canonicalId) {
          continue;
        }

        await _db
            .into(_db.connections)
            .insert(
              ConnectionsCompanion.insert(
                fromNodeId: newFromId,
                toNodeId: canonicalId,
                createdAt: connection.createdAt,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }

      // -----------------------------------------------------
      // 2.3 Reconciliar SCAN SESSION NODES.
      //
      // Cada aparición histórica del duplicado pasa a apuntar
      // al Node canónico.
      //
      // UNIQUE(session_id, node_id) se protege mediante
      // INSERT OR IGNORE.
      // -----------------------------------------------------
      final scanRows = await (_db.select(
        _db.scanSessionNodes,
      )..where((t) => t.nodeId.equals(duplicateId))).get();

      for (final row in scanRows) {
        await _db
            .into(_db.scanSessionNodes)
            .insert(
              ScanSessionNodesCompanion.insert(
                sessionId: row.sessionId,
                nodeId: canonicalId,
                rssi: row.rssi,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }

      // -----------------------------------------------------
      // 2.4 Eliminar el duplicado.
      //
      // Ahora es seguro permitir ON DELETE CASCADE porque
      // connections y scanSessionNodes ya fueron trasladados.
      // -----------------------------------------------------
      await (_db.delete(
        _db.nodes,
      )..where((t) => t.id.equals(duplicateId))).go();

      // -----------------------------------------------------
      // 2.5 Actualizar el Node canónico.
      //
      // La dirección BLE de "current" es la observada ahora,
      // por lo que pasa a ser la dirección de transporte actual.
      //
      // Si alguno de los registros poseía remoteRef, se conserva.
      // -----------------------------------------------------
      await (_db.update(
        _db.nodes,
      )..where((t) => t.id.equals(canonicalId))).write(
        NodesCompanion(
          deviceUuid: Value(deviceUuid),
          bleAddress: Value(current.bleAddress ?? canonical.bleAddress),
          remoteRef: Value(canonical.remoteRef ?? current.remoteRef),
          name: Value(name),
          color: Value(color),
          lastSeen: Value(current.lastSeen),
          connectable: Value(current.connectable),
          estimatedDistance: Value(current.estimatedDistance),
        ),
      );

      final reconciled = await (_db.select(
        _db.nodes,
      )..where((t) => t.id.equals(canonicalId))).getSingle();

      return _toDomain(reconciled);
    });
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
      remoteRef: row.remoteRef,
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
        remoteRef: Value(node.remoteRef),
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
      remoteRef: Value(node.remoteRef),
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
