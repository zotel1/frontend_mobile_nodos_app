import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_identity.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/ble_identity_discovery_service.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';

void main() {
  final device = BleDevice(
    deviceId: 'peer-1',
    rssi: -45,
    distance: 1,
    proximity: ProximityLevel.close,
    timestamp: DateTime(2026),
    connectable: true,
    serviceUuids: [serviceUuid],
    deviceType: 'Nodo',
    kind: BleDeviceKind.nodos,
  );

  test('identifies and reconciles metadata without creating a link', () async {
    final gatt = _FakeGatt(
      NodosIdentity(
        version: 1,
        uuid: 'stable-peer-uuid',
        name: 'Peer Nodo',
        color: '#112233',
      ).toBytes(),
    );
    final nodes = _FakeNodeRepository();
    final service = BleIdentityDiscoveryService(
      gatt: gatt,
      nodeRepository: nodes,
    );

    final identity = await service.identify(device);

    expect(identity?.version, 1);
    expect(identity?.uuid, 'stable-peer-uuid');
    expect(identity?.name, 'Peer Nodo');
    expect(identity?.color, '#112233');
    expect(nodes.persisted.single.name, 'Peer Nodo');
    expect(nodes.persisted.single.deviceUuid, 'stable-peer-uuid');
    expect(nodes.connectionWrites, isEmpty);
    expect(gatt.calls, ['connect', 'discover', 'read', 'disconnect']);
  });

  test('serializes discovery and ignores duplicate requests', () async {
    final gatt = _FakeGatt(const [1]);
    final nodes = _FakeNodeRepository();
    final service = BleIdentityDiscoveryService(
      gatt: gatt,
      nodeRepository: nodes,
    );

    final first = service.identify(device);
    final duplicate = service.identify(device);
    await Future.wait([first, duplicate]);

    expect(gatt.connectCount, 1);
  });
}

class _FakeGatt implements BleGattDataSource {
  final List<int> payload;
  final List<String> calls = [];
  int connectCount = 0;

  _FakeGatt(this.payload);

  @override
  Future<void> connect(String remoteId) async {
    calls.add('connect');
    connectCount++;
  }

  @override
  Future<void> disconnect(String remoteId) async => calls.add('disconnect');

  @override
  Future<bool> isConnected(String remoteId) async => true;

  @override
  Stream<bool> connectionState(String remoteId) => Stream.value(true);

  @override
  Future<List<BleServiceInfo>> discoverServices(String remoteId) async {
    calls.add('discover');
    return const [];
  }

  @override
  Future<List<int>?> readCharacteristic(
    String remoteId,
    String characteristicUuid,
  ) async {
    calls.add('read');
    return payload;
  }

  @override
  Future<bool> writeCharacteristic(
    String remoteId,
    String characteristicUuid,
    List<int> payload,
  ) async => false;

  @override
  Future<List<int>?> writeAndWaitForResponse(
    String remoteId,
    String characteristicUuid,
    List<int> requestPayload, {
    Duration timeout = const Duration(seconds: 30),
  }) async => null;
}

class _FakeNodeRepository implements NodeRepository {
  final List<Node> persisted = [];
  final List<String> connectionWrites = [];

  @override
  Stream<List<Node>> observeNodes() => Stream.value(persisted);
  @override
  Future<Node?> getNodeById(int id) async => _find((n) => n.id == id);
  @override
  Future<Node?> getNodeByBleAddress(String address) async =>
      _find((n) => n.bleAddress == address);
  @override
  Future<Node?> getNodeByDeviceUuid(String uuid) async =>
      _find((n) => n.deviceUuid == uuid);
  @override
  Future<Node?> getNodeByRemoteRef(String ref) async => null;
  @override
  Future<Node?> getSelfNode() async => null;
  @override
  Future<void> upsertNode(Node node) async {
    final value = node.id == null ? node.copyWith(id: 1) : node;
    persisted
      ..removeWhere((n) => n.bleAddress == value.bleAddress)
      ..add(value);
  }

  @override
  Future<Node?> reconcileNodeIdentity(
    int nodeId, {
    required String deviceUuid,
    required String name,
    required String color,
  }) async {
    final index = persisted.indexWhere((n) => n.id == nodeId);
    persisted[index] = persisted[index].copyWith(
      deviceUuid: deviceUuid,
      name: name,
      color: color,
    );
    return persisted[index];
  }

  @override
  Future<void> updateNodeMetadata(
    int id, {
    String? name,
    String? color,
  }) async {}
  @override
  Future<void> clearAllNodes() async {}

  Node? _find(bool Function(Node) predicate) {
    for (final node in persisted) {
      if (predicate(node)) return node;
    }
    return null;
  }
}
