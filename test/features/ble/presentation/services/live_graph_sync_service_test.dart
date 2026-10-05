import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/active_graph_exchange_service.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/graph_exchange_session_manager.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/services/live_graph_sync_service.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/transport/ble_message_reassembler.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

void main() {
  late FakeNodeRepository nodeRepository;
  late FakeBleRepository bleRepository;
  late FakeUserRepository userRepository;
  late FakeBleConnectionRepository connectionRepository;
  late ActiveGraphExchangeService activeGraph;
  late GraphExchangeSessionManager sessions;
  late LiveGraphSyncService liveSync;

  setUp(() {
    nodeRepository = FakeNodeRepository();
    bleRepository = FakeBleRepository();
    userRepository = FakeUserRepository();
    connectionRepository = FakeBleConnectionRepository();
    activeGraph = ActiveGraphExchangeService(
      nodeRepository: nodeRepository,
      userRepository: userRepository,
      bleRepository: bleRepository,
    );
    sessions = GraphExchangeSessionManager();
    liveSync = LiveGraphSyncService(
      activeGraphExchange: activeGraph,
      sessionManager: sessions,
      connectionRepository: connectionRepository,
    )..start();
  });

  tearDown(() async {
    await liveSync.dispose();
    await nodeRepository.close();
  });

  test('publishes a changed local snapshot to an active peer', () async {
    nodeRepository.nodes['remote-a'] = _node('remote-a', 2);
    sessions.activate('peer-a', remoteId: 'remote-a');

    await activeGraph.markConnected('remote-a');
    await _flushAsyncWork();

    expect(connectionRepository.writes, hasLength(1));
    expect(connectionRepository.writes.single.remoteId, 'remote-a');
  });

  test('frames a large graph according to the negotiated MTU', () async {
    connectionRepository.mtuValue = 23;
    for (var index = 0; index < 30; index++) {
      nodeRepository.nodes['remote-$index'] = _node('remote-$index', index + 2);
    }
    sessions.activate('peer-a', remoteId: 'remote-a');

    await activeGraph.markConnected('remote-a');
    await _flushAsyncWork();

    final reassembler = BleMessageReassembler(scheduleCleanup: false);
    Uint8List? payload;
    for (final write in connectionRepository.writes) {
      payload = reassembler.add(write.payload);
    }

    expect(connectionRepository.writes.length, greaterThan(1));
    expect(payload, isNotNull);
  });

  test('does not resend an identical snapshot', () async {
    nodeRepository.nodes['remote-a'] = _node('remote-a', 2);
    sessions.activate('peer-a', remoteId: 'remote-a');

    await activeGraph.markConnected('remote-a');
    await activeGraph.publishCurrentSnapshot();
    await _flushAsyncWork();

    expect(connectionRepository.writes, hasLength(1));
  });

  test('publishes a changed snapshot to two active peers', () async {
    nodeRepository.nodes['remote-a'] = _node('remote-a', 2);
    nodeRepository.nodes['remote-b'] = _node('remote-b', 3);
    sessions.activate('peer-a', remoteId: 'remote-a');
    sessions.activate('peer-b', remoteId: 'remote-b');

    await activeGraph.markConnected('remote-a');
    await activeGraph.markConnected('remote-b');
    await _flushAsyncWork();

    expect(
      connectionRepository.writes.map((write) => write.remoteId),
      containsAll(<String>['remote-a', 'remote-b']),
    );
  });

  test('skips invalidated peers', () async {
    nodeRepository.nodes['remote-a'] = _node('remote-a', 2);
    nodeRepository.nodes['remote-b'] = _node('remote-b', 3);
    nodeRepository.nodes['remote-c'] = _node('remote-c', 4);
    sessions.activate('peer-a', remoteId: 'remote-a');
    sessions.activate('peer-b', remoteId: 'remote-b');

    await activeGraph.markConnected('remote-a');
    sessions.invalidatePeer('peer-b');
    await activeGraph.markConnected('remote-b');
    await activeGraph.markConnected('remote-c');
    await _flushAsyncWork();

    expect(
      connectionRepository.writes.map((write) => write.remoteId),
      isNot(contains('remote-b')),
    );
    expect(
      connectionRepository.writes.map((write) => write.remoteId),
      contains('remote-a'),
    );
  });

  test('continues publishing when one peer write fails', () async {
    nodeRepository.nodes['remote-a'] = _node('remote-a', 2);
    nodeRepository.nodes['remote-b'] = _node('remote-b', 3);
    nodeRepository.nodes['remote-c'] = _node('remote-c', 4);
    connectionRepository.failingRemoteIds.add('remote-a');
    sessions.activate('peer-a', remoteId: 'remote-a');
    sessions.activate('peer-b', remoteId: 'remote-b');

    await activeGraph.markConnected('remote-a');
    await activeGraph.markConnected('remote-b');
    await _flushAsyncWork();

    expect(
      connectionRepository.writes.map((write) => write.remoteId),
      contains('remote-b'),
    );

    connectionRepository.failingRemoteIds.clear();
    await activeGraph.markConnected('remote-c');
    await _flushAsyncWork();

    expect(
      connectionRepository.writes.map((write) => write.remoteId),
      contains('remote-a'),
    );
  });

  test('re-sends the same payload for a newly activated session', () async {
    nodeRepository.nodes['remote-a'] = _node('remote-a', 2);
    sessions.activate('peer-a', remoteId: 'remote-a');

    await activeGraph.markConnected('remote-a');
    await _flushAsyncWork();
    sessions.invalidatePeer('peer-a');
    sessions.activate('peer-a', remoteId: 'remote-a');

    await liveSync.sendInitialSnapshot(
      remoteId: 'remote-a',
      payload: await activeGraph.buildCurrentPayload(),
    );

    expect(connectionRepository.writes, hasLength(2));
  });

  test('builds only direct local relations, never remote snapshots', () async {
    nodeRepository.nodes['remote-a'] = _node('remote-a', 2);
    sessions.activate('peer-a', remoteId: 'remote-a');

    await activeGraph.markConnected('remote-a');
    final payload = await activeGraph.buildCurrentPayload();

    expect(payload.ownerUuid, 'local-owner');
    expect(payload.connections, hasLength(1));
    expect(payload.connections.single.deviceUuid, 'remote-a');
  });

  test('lifecycle invalidation stops later publications', () async {
    nodeRepository.nodes['remote-a'] = _node('remote-a', 2);
    sessions.activate('peer-a', remoteId: 'remote-a');

    await activeGraph.markConnected('remote-a');
    await _flushAsyncWork();
    final writesBeforeClear = connectionRepository.writes.length;

    sessions.clear();
    nodeRepository.nodes['remote-b'] = _node('remote-b', 3);
    await activeGraph.markConnected('remote-b');
    await _flushAsyncWork();

    expect(connectionRepository.writes.length, writesBeforeClear);
  });

  test('active graph queue recovers after a failed publication', () async {
    nodeRepository.nodes['remote-a'] = _node('remote-a', 2);
    nodeRepository.nodes['remote-b'] = _node('remote-b', 3);
    bleRepository.failUpdates = true;

    await expectLater(
      activeGraph.markConnected('remote-a'),
      throwsA(isA<StateError>()),
    );

    bleRepository.failUpdates = false;
    await activeGraph.markConnected('remote-b');

    expect(bleRepository.graphPayloads, hasLength(1));
  });
}

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Node _node(String remoteId, int id) {
  final now = DateTime(2026);
  return Node(
    id: id,
    deviceUuid: remoteId,
    bleAddress: remoteId,
    name: remoteId,
    firstSeen: now,
    lastSeen: now,
    connectable: true,
  );
}

class FakeUserRepository implements UserRepository {
  @override
  Future<User?> getUserProfile() async => User(
    uuid: 'local-owner',
    name: 'Local',
    color: '#123456',
    deviceType: 'Nodo',
    createdAt: DateTime(2026),
  );

  @override
  Future<void> createUser(User user) async {}

  @override
  Future<void> setLocalNodeId(int nodeId) async {}

  @override
  Future<void> updateColor(String color) async {}

  @override
  Future<void> updateName(String name) async {}
}

class FakeNodeRepository implements NodeRepository {
  final Map<String, Node> nodes = <String, Node>{};
  final StreamController<List<Node>> _nodesController =
      StreamController<List<Node>>.broadcast();

  @override
  Stream<List<Node>> observeNodes() => _nodesController.stream;

  Future<void> close() => _nodesController.close();

  @override
  Future<Node?> getNodeByBleAddress(String bleAddress) async =>
      nodes[bleAddress];

  @override
  Future<Node?> getNodeByDeviceUuid(String deviceUuid) async =>
      nodes[deviceUuid];

  @override
  Future<Node?> getNodeById(int id) async =>
      nodes.values.where((node) => node.id == id).firstOrNull;

  @override
  Future<Node?> getNodeByRemoteRef(String remoteRef) async => null;

  @override
  Future<Node?> getSelfNode() async => null;

  @override
  Future<Node?> reconcileNodeIdentity(
    int nodeId, {
    required String deviceUuid,
    required String name,
    required String color,
  }) async => nodes[deviceUuid];

  @override
  Future<void> updateNodeMetadata(
    int id, {
    String? name,
    String? color,
  }) async {}

  @override
  Future<void> upsertNode(Node node) async {}

  @override
  Future<void> clearAllNodes() async {}
}

class FakeBleRepository implements BleRepository {
  final List<Uint8List> graphPayloads = <Uint8List>[];
  bool failUpdates = false;

  @override
  Stream<bool> get bluetoothState => Stream<bool>.empty();

  @override
  Future<void> endScanSession() async {}

  @override
  Stream<BleIncomingGattWrite> get incomingLinkRequests =>
      Stream<BleIncomingGattWrite>.empty();

  @override
  Stream<BleIncomingGattWrite> get incomingPeerGraphPayloads =>
      Stream<BleIncomingGattWrite>.empty();

  @override
  Stream<List<BleDevice>> get scanResults => Stream<List<BleDevice>>.empty();

  @override
  Future<void> sendLinkResponse(Uint8List payload) async {}

  @override
  Future<void> startAdvertise(
    String deviceUuid,
    String name,
    String color,
  ) async {}

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopAdvertise() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> updateGraphPayload(Uint8List payload) async {
    if (failUpdates) {
      throw StateError('advertising payload update failed');
    }
    graphPayloads.add(Uint8List.fromList(payload));
  }
}

class FakeBleConnectionRepository implements BleConnectionRepository {
  final List<GraphWrite> writes = <GraphWrite>[];
  final Set<String> failingRemoteIds = <String>{};
  int mtuValue = 512;

  @override
  Future<void> connect(String remoteId) async {}

  @override
  Stream<bool> connectionState(String remoteId) => Stream<bool>.empty();

  @override
  Stream<List<int>> characteristicValueStream(
    String remoteId,
    String characteristicUuid,
  ) => Stream<List<int>>.empty();

  @override
  Future<int> mtu(String remoteId) async => mtuValue;

  @override
  Future<void> disconnect(String remoteId) async {}

  @override
  Future<void> discoverServices(String remoteId) async {}

  @override
  Future<List<int>?> readCharacteristic(
    String remoteId,
    String characteristicUuid,
  ) async => null;

  @override
  Future<void> saveConnection(int fromNodeId, int toNodeId) async {}

  @override
  Future<List<int>?> writeAndWaitForResponse(
    String remoteId,
    String characteristicUuid,
    List<int> requestPayload, {
    Duration timeout = const Duration(seconds: 30),
  }) async => null;

  @override
  Future<bool> writeCharacteristic(
    String remoteId,
    String characteristicUuid,
    List<int> payload,
  ) async {
    if (failingRemoteIds.contains(remoteId)) {
      throw StateError('write failed for $remoteId');
    }
    writes.add(
      GraphWrite(
        remoteId: remoteId,
        characteristicUuid: characteristicUuid,
        payload: Uint8List.fromList(payload),
      ),
    );
    return true;
  }
}

class GraphWrite {
  final String remoteId;
  final String characteristicUuid;
  final Uint8List payload;

  const GraphWrite({
    required this.remoteId,
    required this.characteristicUuid,
    required this.payload,
  });
}
