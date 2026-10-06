import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/active_graph_exchange_service.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/services/ble_lifecycle_coordinator.dart';
import 'package:frontend_mobile_nodos_app/features/ble/platform/ble_background_policy.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

@GenerateNiceMocks([
  MockSpec<BleRepository>(),
  MockSpec<BleConnectionRepository>(),
  MockSpec<NodeRepository>(),
  MockSpec<UserRepository>(),
  MockSpec<ActiveGraphExchangeService>(),
])
import 'ble_lifecycle_coordinator_test.mocks.dart';

class _RemoteRelationLifecycleFake
    implements RemoteRelationRepository, RemoteRelationLifecycle {
  int clearAllCalls = 0;

  @override
  Future<void> clearAllSnapshots() async => clearAllCalls++;

  @override
  Future<void> clearSnapshot(String reporterUuid) async {}

  @override
  Future<List<RemoteRelation>> getSnapshot(String reporterUuid) async => [];

  @override
  Future<void> replaceSnapshot({
    required String reporterUuid,
    required List<NodosGraphConnection> connections,
  }) async {}

  @override
  Stream<List<RemoteRelation>> watchAll() => Stream.value(const []);
}

void main() {
  late MockBleRepository bleRepository;
  late MockBleConnectionRepository connectionRepository;
  late MockNodeRepository nodeRepository;
  late MockUserRepository userRepository;
  late MockActiveGraphExchangeService activeGraphExchange;
  late _RemoteRelationLifecycleFake remoteRelations;
  late StreamController<bool> adapterStates;
  late BleBloc bleBloc;
  late BleConnectionBloc connectionBloc;
  late BleLifecycleCoordinator coordinator;

  setUp(() {
    bleRepository = MockBleRepository();
    connectionRepository = MockBleConnectionRepository();
    nodeRepository = MockNodeRepository();
    userRepository = MockUserRepository();
    activeGraphExchange = MockActiveGraphExchangeService();
    remoteRelations = _RemoteRelationLifecycleFake();
    adapterStates = StreamController<bool>.broadcast();

    when(bleRepository.bluetoothState).thenAnswer((_) => adapterStates.stream);
    when(
      bleRepository.incomingLinkRequests,
    ).thenAnswer((_) => const Stream.empty());
    when(
      bleRepository.incomingPeerGraphPayloads,
    ).thenAnswer((_) => const Stream.empty());
    when(bleRepository.stopScan()).thenAnswer((_) async {});
    when(bleRepository.stopAdvertise()).thenAnswer((_) async {});
    when(bleRepository.endScanSession()).thenAnswer((_) async {});
    when(activeGraphExchange.clear()).thenAnswer((_) async {});

    bleBloc = BleBloc(
      repository: bleRepository,
      userRepository: userRepository,
      remoteRelationRepository: remoteRelations,
      nodeRepository: nodeRepository,
      connectionRepository: connectionRepository,
    );
    connectionBloc = BleConnectionBloc(
      connectionRepository: connectionRepository,
      nodeRepository: nodeRepository,
      userRepository: userRepository,
      activeGraphExchange: activeGraphExchange,
      remoteRelationRepository: remoteRelations,
    );
    coordinator = BleLifecycleCoordinator(
      bleRepository: bleRepository,
      remoteRelationRepository: remoteRelations,
      bleBloc: bleBloc,
      connectionBloc: connectionBloc,
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await bleBloc.close();
    await connectionBloc.close();
    await adapterStates.close();
  });

  test(
    'startup clears stale remote snapshots and reconciles adapter state',
    () async {
      final initialization = coordinator.initialize();
      await Future<void>.delayed(Duration.zero);
      adapterStates.add(true);
      await initialization;

      expect(remoteRelations.clearAllCalls, 1);
      expect(bleBloc.state, isNot(isA<BluetoothOff>()));
    },
  );

  test(
    'Bluetooth OFF cleanup is repeatable and clears active graph state',
    () async {
      final initialization = coordinator.initialize();
      await Future<void>.delayed(Duration.zero);
      adapterStates.add(true);
      await initialization;

      await coordinator.invalidateRuntime();
      await coordinator.invalidateRuntime();

      expect(verify(activeGraphExchange.clear()).callCount, 1);
      expect(remoteRelations.clearAllCalls, 2);
    },
  );

  test('foreground reconciliation does not invent a reconnection', () async {
    final initialization = coordinator.initialize();
    await Future<void>.delayed(Duration.zero);
    adapterStates.add(false);
    await initialization;

    await coordinator.onForeground();

    verifyNever(bleRepository.startScan());
    verifyNever(bleRepository.startAdvertise(any, any, any));
  });

  test('inactive is transient and does not invalidate BLE runtime', () async {
    final initialization = coordinator.initialize();
    await Future<void>.delayed(Duration.zero);
    adapterStates.add(true);
    await initialization;

    coordinator.onInactive();

    await Future<void>.delayed(Duration.zero);
    verifyNever(bleRepository.stopScan());
    verifyNever(bleRepository.stopAdvertise());
    verifyNever(activeGraphExchange.clear());
  });

  test('background cleanup stops runtime and is idempotent', () async {
    final initialization = coordinator.initialize();
    await Future<void>.delayed(Duration.zero);
    adapterStates.add(true);
    await initialization;

    await coordinator.onBackground();
    await coordinator.onBackground();

    verify(bleRepository.stopScan()).called(1);
    verify(bleRepository.stopAdvertise()).called(1);
    verify(activeGraphExchange.clear()).called(1);
  });

  test('background-capable policy does not run foreground cleanup', () async {
    final backgroundCapableCoordinator = BleLifecycleCoordinator(
      bleRepository: bleRepository,
      remoteRelationRepository: remoteRelations,
      bleBloc: bleBloc,
      connectionBloc: connectionBloc,
      backgroundPolicy: const BleBackgroundPolicy.iosBackgroundCapable(),
    );

    await backgroundCapableCoordinator.onBackground();

    verifyNever(bleRepository.stopScan());
    verifyNever(bleRepository.stopAdvertise());
    verifyNever(activeGraphExchange.clear());
  });
}
