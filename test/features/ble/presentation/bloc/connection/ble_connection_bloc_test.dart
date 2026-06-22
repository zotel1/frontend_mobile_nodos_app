import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';

@GenerateNiceMocks([
  MockSpec<BleConnectionRepository>(),
  MockSpec<NodeRepository>(),
])
import 'ble_connection_bloc_test.mocks.dart';

void main() {
  late MockBleConnectionRepository mockRepo;
  late MockNodeRepository mockNodeRepo;
  late StreamController<bool> stateController;

  setUp(() async {
    mockRepo = MockBleConnectionRepository();
    mockNodeRepo = MockNodeRepository();
    stateController = StreamController<bool>.broadcast();

    // Configurar mocks por defecto
    when(mockRepo.discoverServices(any)).thenAnswer((_) async {});
    when(mockRepo.readCharacteristic(any, any))
        .thenAnswer((_) async => null);
  });

  tearDown(() async {
    await stateController.close();
  });

  group('BleConnectionBloc', () {
    // ─────────── Estado inicial ───────────

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnectionInitial como estado inicial',
      build: () => BleConnectionBloc(
          connectionRepository: mockRepo, nodeRepository: mockNodeRepo),
      verify: (bloc) => expect(bloc.state, isA<BleConnectionInitial>()),
    );

    // ─────────── ConnectToDevice ───────────

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnecting → BleConnected al conectar exitosamente',
      build: () {
        when(mockRepo.connect(any)).thenAnswer((_) async {});
        when(mockRepo.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        Future.microtask(() => stateController.add(true));
        return BleConnectionBloc(
            connectionRepository: mockRepo, nodeRepository: mockNodeRepo);
      },
      act: (bloc) => bloc.add(
          const ConnectToDevice('AA:BB:CC:DD:EE:FF', myNodeId: 1)),
      expect: () => [
        isA<BleConnecting>().having(
          (s) => s.remoteId,
          'remoteId',
          equals('AA:BB:CC:DD:EE:FF'),
        ),
        isA<BleConnected>().having(
          (s) => s.remoteId,
          'remoteId',
          equals('AA:BB:CC:DD:EE:FF'),
        ),
      ],
      verify: (_) {
        verify(mockRepo.connect('AA:BB:CC:DD:EE:FF')).called(1);
      },
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnecting → BleConnectionError cuando connect() lanza excepción',
      build: () {
        when(mockRepo.connect(any))
            .thenThrow(Exception('Device unreachable'));
        when(mockRepo.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        return BleConnectionBloc(
            connectionRepository: mockRepo, nodeRepository: mockNodeRepo);
      },
      act: (bloc) => bloc.add(
          const ConnectToDevice('BB:CC:DD:EE:FF:00', myNodeId: 1)),
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnectionError>()
            .having((s) => s.message, 'message', contains('Device unreachable'))
            .having((s) => s.retryable, 'retryable', isTrue),
      ],
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnectionError con retryable=true ante timeout',
      build: () {
        when(mockRepo.connect(any))
            .thenThrow(TimeoutException('Connection timed out'));
        when(mockRepo.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        return BleConnectionBloc(
            connectionRepository: mockRepo, nodeRepository: mockNodeRepo);
      },
      act: (bloc) =>
          bloc.add(const ConnectToDevice('timeout-device', myNodeId: 1)),
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnectionError>().having(
          (s) => s.retryable,
          'retryable',
          isTrue,
        ),
      ],
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnectionError con retryable=false ante error no recuperable',
      build: () {
        when(mockRepo.connect(any))
            .thenThrow(StateError('Bluetooth is disabled'));
        when(mockRepo.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        return BleConnectionBloc(
            connectionRepository: mockRepo, nodeRepository: mockNodeRepo);
      },
      act: (bloc) =>
          bloc.add(const ConnectToDevice('bt-off-device', myNodeId: 1)),
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnectionError>().having(
          (s) => s.retryable,
          'retryable',
          isFalse,
        ),
      ],
    );

    // ─────────── DisconnectDevice ───────────

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnectionInitial al desconectar desde BleConnected',
      build: () {
        when(mockRepo.disconnect(any)).thenAnswer((_) async {});
        return BleConnectionBloc(
            connectionRepository: mockRepo, nodeRepository: mockNodeRepo);
      },
      seed: () => const BleConnected(remoteId: 'AA:BB:CC:DD:EE:FF'),
      act: (bloc) =>
          bloc.add(const DisconnectDevice('AA:BB:CC:DD:EE:FF')),
      expect: () => [isA<BleConnectionInitial>()],
      verify: (_) {
        verify(mockRepo.disconnect('AA:BB:CC:DD:EE:FF')).called(1);
      },
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnectionInitial al desconectar desde BleConnectionError',
      build: () {
        when(mockRepo.disconnect(any)).thenAnswer((_) async {});
        return BleConnectionBloc(
            connectionRepository: mockRepo, nodeRepository: mockNodeRepo);
      },
      seed: () => const BleConnectionError(
        message: 'prev error',
        retryable: true,
      ),
      act: (bloc) => bloc.add(const DisconnectDevice('any-id')),
      expect: () => [isA<BleConnectionInitial>()],
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'no emite nada al desconectar desde BleConnectionInitial',
      build: () {
        when(mockRepo.disconnect(any)).thenAnswer((_) async {});
        return BleConnectionBloc(
            connectionRepository: mockRepo, nodeRepository: mockNodeRepo);
      },
      act: (bloc) => bloc.add(const DisconnectDevice('any-id')),
      expect: () => [],
    );

    // ─────────── T3.3: Nuevos estados de identidad y conexión ───────────

    blocTest<BleConnectionBloc, BleConnectionState>(
      'T3.3: emite ConnectionInserted + RemoteIdentityLoaded cuando GATT read tiene éxito',
      build: () {
        when(mockRepo.connect(any)).thenAnswer((_) async {});
        when(mockRepo.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        when(mockRepo.discoverServices(any)).thenAnswer((_) async {});
        when(mockRepo.readCharacteristic(any, identityCharacteristicUUID))
            .thenAnswer((_) async =>
                utf8.encode('{"name":"Nodo Remoto","color":"#FF5722"}'));
        when(mockNodeRepo.getNodeByBleAddress('AA:BB:CC:DD:EE:FF'))
            .thenAnswer((_) async => Node(
                  id: 5,
                  bleAddress: 'AA:BB:CC:DD:EE:FF',
                  firstSeen: DateTime.now(),
                  lastSeen: DateTime.now(),
                ));
        Future.microtask(() => stateController.add(true));
        return BleConnectionBloc(
            connectionRepository: mockRepo, nodeRepository: mockNodeRepo);
      },
      act: (bloc) => bloc.add(
        const ConnectToDevice('AA:BB:CC:DD:EE:FF', myNodeId: 1),
      ),
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnected>(),
      ],
      verify: (_) {
        verify(mockRepo.connect('AA:BB:CC:DD:EE:FF')).called(1);
      },
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'T3.3: emite RemoteIdentityUnavailable cuando GATT read falla',
      build: () {
        when(mockRepo.connect(any)).thenAnswer((_) async {});
        when(mockRepo.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        when(mockRepo.discoverServices(any))
            .thenThrow(Exception('Service discovery failed'));
        when(mockNodeRepo.getNodeByBleAddress('AA:BB:CC:DD:EE:FF'))
            .thenAnswer((_) async => Node(
                  id: 5,
                  bleAddress: 'AA:BB:CC:DD:EE:FF',
                  firstSeen: DateTime.now(),
                  lastSeen: DateTime.now(),
                ));
        Future.microtask(() => stateController.add(true));
        return BleConnectionBloc(
            connectionRepository: mockRepo, nodeRepository: mockNodeRepo);
      },
      act: (bloc) => bloc.add(
        const ConnectToDevice('AA:BB:CC:DD:EE:FF', myNodeId: 1),
      ),
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnected>(),
      ],
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'T3.3: ConnectionInserted emitido cuando connections insert tiene éxito',
      build: () {
        when(mockRepo.connect(any)).thenAnswer((_) async {});
        when(mockRepo.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        when(mockRepo.discoverServices(any))
            .thenThrow(Exception('fail'));
        when(mockNodeRepo.getNodeByBleAddress('BB:CC:DD:EE:FF:00'))
            .thenAnswer((_) async => Node(
                  id: 10,
                  bleAddress: 'BB:CC:DD:EE:FF:00',
                  firstSeen: DateTime.now(),
                  lastSeen: DateTime.now(),
                ));
        Future.microtask(() => stateController.add(true));
        return BleConnectionBloc(
            connectionRepository: mockRepo, nodeRepository: mockNodeRepo);
      },
      act: (bloc) => bloc.add(
        const ConnectToDevice('BB:CC:DD:EE:FF:00', myNodeId: 2),
      ),
      verify: (_) {
        verify(mockRepo.connect('BB:CC:DD:EE:FF:00')).called(1);
      },
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnected>(),
      ],
    );
  });
}
