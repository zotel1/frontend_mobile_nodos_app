import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_link_request.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/graph_exchange_session_manager.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'ble_bloc_test.mocks.dart';

void main() {
  test(
    'accepts multiple snapshots only for an ACTIVE reporter session',
    () async {
      final repository = MockBleRepository();
      final connectionRepository = MockBleConnectionRepository();
      final nodeRepository = MockNodeRepository();
      final userRepository = MockUserRepository();
      final relationRepository = MockRemoteRelationRepository();
      final incoming = StreamController<BleIncomingGattWrite>();
      final manager = GraphExchangeSessionManager();

      when(repository.bluetoothState).thenAnswer((_) => Stream.value(true));
      when(repository.incomingLinkRequests).thenAnswer((_) => Stream.empty());
      when(
        repository.incomingPeerGraphPayloads,
      ).thenAnswer((_) => incoming.stream);
      when(repository.stopScan()).thenAnswer((_) async {});
      when(repository.stopAdvertise()).thenAnswer((_) async {});
      when(repository.endScanSession()).thenAnswer((_) async {});
      when(
        relationRepository.replaceSnapshot(
          reporterUuid: anyNamed('reporterUuid'),
          connections: anyNamed('connections'),
        ),
      ).thenAnswer((_) async {});

      final bloc = BleBloc(
        repository: repository,
        userRepository: userRepository,
        remoteRelationRepository: relationRepository,
        nodeRepository: nodeRepository,
        connectionRepository: connectionRepository,
        sessionManager: manager,
      );

      final payload1 = NodosGraphPayload(
        ownerUuid: 'peer-a',
        connections: [NodosGraphConnection.nodos(deviceUuid: 'node-1')],
      );
      final payload2 = const NodosGraphPayload(ownerUuid: 'peer-a');

      incoming.add(
        BleIncomingGattWrite(payload: Uint8List.fromList(payload1.toBytes())),
      );
      await Future<void>.delayed(Duration.zero);
      verifyNever(
        relationRepository.replaceSnapshot(
          reporterUuid: anyNamed('reporterUuid'),
          connections: anyNamed('connections'),
        ),
      );

      manager.activate('peer-a');
      incoming.add(
        BleIncomingGattWrite(payload: Uint8List.fromList(payload1.toBytes())),
      );
      incoming.add(
        BleIncomingGattWrite(payload: Uint8List.fromList(payload2.toBytes())),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      verify(
        relationRepository.replaceSnapshot(
          reporterUuid: 'peer-a',
          connections: anyNamed('connections'),
        ),
      ).called(2);

      await incoming.close();
      await bloc.close();
    },
  );
  test(
    'accepted LinkRequest activates the peer session before graph writes',
    () async {
      final repository = MockBleRepository();
      final connectionRepository = MockBleConnectionRepository();
      final nodeRepository = MockNodeRepository();
      final userRepository = MockUserRepository();
      final relationRepository = MockRemoteRelationRepository();
      final manager = GraphExchangeSessionManager();
      final now = DateTime(2026);
      final localUser = User(
        uuid: 'local-a',
        name: 'Local',
        color: '#111111',
        deviceType: 'Nodo',
        createdAt: now,
      );
      final peer = Node(
        id: 2,
        deviceUuid: 'peer-a',
        firstSeen: now,
        lastSeen: now,
      );
      final self = Node(
        id: 1,
        deviceUuid: 'local-a',
        isSelf: true,
        firstSeen: now,
        lastSeen: now,
      );

      when(repository.bluetoothState).thenAnswer((_) => Stream.value(true));
      when(repository.incomingLinkRequests).thenAnswer((_) => Stream.empty());
      when(
        repository.incomingPeerGraphPayloads,
      ).thenAnswer((_) => Stream.empty());
      when(repository.stopScan()).thenAnswer((_) async {});
      when(repository.stopAdvertise()).thenAnswer((_) async {});
      when(repository.endScanSession()).thenAnswer((_) async {});
      when(userRepository.getUserProfile()).thenAnswer((_) async => localUser);
      when(
        nodeRepository.getNodeByDeviceUuid('peer-a'),
      ).thenAnswer((_) async => peer);
      when(nodeRepository.getSelfNode()).thenAnswer((_) async => self);
      when(nodeRepository.upsertNode(any)).thenAnswer((_) async {});
      when(connectionRepository.saveConnection(1, 2)).thenAnswer((_) async {});
      when(repository.sendLinkResponse(any)).thenAnswer((_) async {});

      final bloc = BleBloc(
        repository: repository,
        userRepository: userRepository,
        remoteRelationRepository: relationRepository,
        nodeRepository: nodeRepository,
        connectionRepository: connectionRepository,
        sessionManager: manager,
      );

      bloc.add(
        LinkRequestReceived(
          const NodosLinkRequest(
            deviceUuid: 'peer-a',
            name: 'Peer',
            color: '#222222',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      bloc.add(const AcceptLinkRequest('peer-a'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(manager.isAuthorized('peer-a'), isTrue);

      await bloc.close();
    },
  );
}
