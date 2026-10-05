import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

void main() {
  late AppDatabase db;
  late NodeDriftDataSource dataSource;

  setUp(() {
    db = AppDatabase.inMemory();
    dataSource = NodeDriftDataSource(db);
  });

  tearDown(() => db.close());

  test(
    'same deviceUuid with a new transport reuses the persistent Node',
    () async {
      final original = await _insertNode(
        dataSource,
        deviceUuid: 'stable-peer',
        transportId: 'AA:BB:CC:DD:EE:FF',
      );

      await dataSource.upsertNode(
        _node(
          deviceUuid: 'stable-peer',
          transportId: '6A7B0E4D-1234-4EAB-9ABC-1234567890AB',
        ),
      );

      final nodes = await db.select(db.nodes).get();
      final persisted = await dataSource.getNodeByDeviceUuid('stable-peer');

      expect(nodes, hasLength(1));
      expect(persisted!.id, original.id);
      expect(persisted.bleAddress, '6A7B0E4D-1234-4EAB-9ABC-1234567890AB');
    },
  );

  test(
    'placeholder identity discovery merges into the UUID node and keeps connections',
    () async {
      final canonical = await _insertNode(
        dataSource,
        deviceUuid: 'stable-peer',
        transportId: 'old-transport',
      );
      final placeholder = await _insertNode(
        dataSource,
        transportId: 'new-transport',
      );
      final other = await _insertNode(
        dataSource,
        deviceUuid: 'other-peer',
        transportId: 'other-transport',
      );

      await db
          .into(db.connections)
          .insert(
            ConnectionsCompanion.insert(
              fromNodeId: placeholder.id!,
              toNodeId: other.id!,
              createdAt: DateTime(2026),
            ),
          );

      final reconciled = await dataSource.reconcileNodeIdentity(
        placeholder.id!,
        deviceUuid: 'stable-peer',
        name: 'Peer',
        color: '#112233',
      );

      final nodes = await db.select(db.nodes).get();
      final connections = await db.select(db.connections).get();

      expect(reconciled!.id, canonical.id);
      expect(reconciled.bleAddress, 'new-transport');
      expect(nodes, hasLength(2));
      expect(connections.single.fromNodeId, canonical.id);
      expect(connections.single.toNodeId, other.id);
    },
  );

  test(
    'new deviceUuid creates a new Node when the transport belonged to another UUID',
    () async {
      final oldNode = await _insertNode(
        dataSource,
        deviceUuid: 'old-peer',
        transportId: 'recycled-transport',
      );

      final newNode = await dataSource.reconcileNodeIdentity(
        oldNode.id!,
        deviceUuid: 'new-peer',
        name: 'New Peer',
        color: '#445566',
      );

      final oldPersisted = await dataSource.getNodeByDeviceUuid('old-peer');
      final newPersisted = await dataSource.getNodeByDeviceUuid('new-peer');

      expect(newNode!.id, isNot(oldNode.id));
      expect(oldPersisted!.bleAddress, isNull);
      expect(newPersisted!.bleAddress, 'recycled-transport');
    },
  );

  test(
    'recycled transport never merges two stable UUIDs and preserves old connections',
    () async {
      final oldNode = await _insertNode(
        dataSource,
        deviceUuid: 'old-peer',
        transportId: 'transport-recycled',
      );
      final newNode = await _insertNode(
        dataSource,
        deviceUuid: 'new-peer',
        transportId: 'new-peer-old-transport',
      );
      final other = await _insertNode(
        dataSource,
        deviceUuid: 'third-peer',
        transportId: 'third-transport',
      );

      await db
          .into(db.connections)
          .insert(
            ConnectionsCompanion.insert(
              fromNodeId: oldNode.id!,
              toNodeId: other.id!,
              createdAt: DateTime(2026),
            ),
          );

      final reconciled = await dataSource.reconcileNodeIdentity(
        oldNode.id!,
        deviceUuid: 'new-peer',
        name: 'New Peer',
        color: '#AABBCC',
      );

      final oldPersisted = await dataSource.getNodeByDeviceUuid('old-peer');
      final newPersisted = await dataSource.getNodeByDeviceUuid('new-peer');
      final connections = await db.select(db.connections).get();

      expect(reconciled!.id, newNode.id);
      expect(oldPersisted!.id, oldNode.id);
      expect(oldPersisted.deviceUuid, 'old-peer');
      expect(oldPersisted.bleAddress, isNull);
      expect(newPersisted!.bleAddress, 'transport-recycled');
      expect(connections.single.fromNodeId, oldNode.id);
      expect(connections.single.toNodeId, other.id);
    },
  );
}

Future<Node> _insertNode(
  NodeDriftDataSource dataSource, {
  String? deviceUuid,
  required String transportId,
}) async {
  await dataSource.upsertNode(
    _node(deviceUuid: deviceUuid, transportId: transportId),
  );
  return (deviceUuid == null
      ? await dataSource.getNodeByBleAddress(transportId)
      : await dataSource.getNodeByDeviceUuid(deviceUuid))!;
}

Node _node({String? deviceUuid, required String transportId}) {
  final now = DateTime(2026);
  return Node(
    deviceUuid: deviceUuid,
    bleAddress: transportId,
    firstSeen: now,
    lastSeen: now,
    rssiHistory: const [-60],
    connectable: true,
  );
}
