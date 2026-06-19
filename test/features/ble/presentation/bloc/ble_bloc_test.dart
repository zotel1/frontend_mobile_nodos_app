import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

@GenerateNiceMocks([MockSpec<BleRepository>()])
import 'ble_bloc_test.mocks.dart';

void main() {
  late MockBleRepository mockRepository;

  final testBleDevice = BleDevice(
    deviceId: 'AA:BB:CC:DD:EE:FF',
    deviceUuid: '4fafc201-1fb5-459e-8fcc-c5c9c331914b',
    rssi: -45,
    distance: 0.56,
    proximity: ProximityLevel.close,
    timestamp: DateTime(2026, 1, 1),
  );

  setUp(() {
    mockRepository = MockBleRepository();
  });

  group('BleBloc', () {
    blocTest<BleBloc, BleState>(
      'emits [BleInitial] as initial state',
      build: () => BleBloc(repository: mockRepository),
      verify: (bloc) => expect(bloc.state, isA<BleInitial>()),
    );

    blocTest<BleBloc, BleState>(
      'emits [BleScanning] when StartScan is added',
      build: () {
        when(mockRepository.startScan()).thenAnswer((_) async {});
        when(mockRepository.scanResults)
            .thenAnswer((_) => Stream<List<BleDevice>>.empty());
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(StartScan()),
      expect: () => [isA<BleScanning>()],
      verify: (_) => verify(mockRepository.startScan()).called(1),
    );

    blocTest<BleBloc, BleState>(
      'emits [BleStopped] when StopScan is added',
      build: () {
        when(mockRepository.stopScan()).thenAnswer((_) async {});
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(StopScan()),
      expect: () => [isA<BleStopped>()],
      verify: (_) => verify(mockRepository.stopScan()).called(1),
    );

    blocTest<BleBloc, BleState>(
      'emits [BleAdvertising] when StartAdvertise is added',
      build: () {
        when(mockRepository.startAdvertise(any))
            .thenAnswer((_) async {});
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const StartAdvertise('test-uuid')),
      expect: () => [isA<BleAdvertising>()],
      verify: (_) =>
          verify(mockRepository.startAdvertise('test-uuid')).called(1),
    );

    blocTest<BleBloc, BleState>(
      'emits [BleStopped] when StopAdvertise is added',
      build: () {
        when(mockRepository.stopAdvertise()).thenAnswer((_) async {});
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(StopAdvertise()),
      expect: () => [isA<BleStopped>()],
      verify: (_) => verify(mockRepository.stopAdvertise()).called(1),
    );

    blocTest<BleBloc, BleState>(
      'emits [BluetoothOff] when BluetoothStateChanged(false) is added',
      build: () => BleBloc(repository: mockRepository),
      act: (bloc) => bloc.add(const BluetoothStateChanged(false)),
      expect: () => [isA<BluetoothOff>()],
    );

    blocTest<BleBloc, BleState>(
      'emits [BleStopped] when BluetoothStateChanged(true) is added after being off',
      seed: () => const BluetoothOff(),
      build: () => BleBloc(repository: mockRepository),
      act: (bloc) => bloc.add(const BluetoothStateChanged(true)),
      expect: () => [isA<BleStopped>()],
    );

    blocTest<BleBloc, BleState>(
      'emits [BleError] when repository.startScan() throws',
      build: () {
        when(mockRepository.startScan())
            .thenThrow(Exception('BT hardware error'));
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(StartScan()),
      expect: () => [
        isA<BleError>().having(
          (s) => s.message,
          'message',
          contains('BT hardware error'),
        ),
      ],
    );

    blocTest<BleBloc, BleState>(
      'processes scanResults stream and emits BleScanning with devices',
      build: () {
        final scanController =
            StreamController<List<BleDevice>>();
        when(mockRepository.scanResults)
            .thenAnswer((_) => scanController.stream);
        when(mockRepository.startScan()).thenAnswer((_) async {
          scanController.add([testBleDevice]);
        });
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(StartScan()),
      expect: () => [
        isA<BleScanning>(),
        isA<BleScanning>().having(
          (s) => s.devices.length,
          'has 1 device',
          1,
        ),
      ],
    );

    blocTest<BleBloc, BleState>(
      'handles scan stream errors by emitting BleError',
      build: () {
        final scanController =
            StreamController<List<BleDevice>>();
        when(mockRepository.scanResults)
            .thenAnswer((_) => scanController.stream);
        when(mockRepository.startScan()).thenAnswer((_) async {
          scanController.addError(Exception('Stream error'));
        });
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(StartScan()),
      expect: () => [
        isA<BleScanning>(),
        isA<BleError>().having(
          (s) => s.message,
          'message',
          contains('Stream error'),
        ),
      ],
    );

    blocTest<BleBloc, BleState>(
      'handles StopScan when no scan is active (no-op on cancel)',
      build: () {
        when(mockRepository.stopScan()).thenAnswer((_) async {});
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(StopScan()),
      expect: () => [isA<BleStopped>()],
    );

    blocTest<BleBloc, BleState>(
      'handles StartAdvertise with different UUIDs',
      build: () {
        when(mockRepository.startAdvertise(any))
            .thenAnswer((_) async {});
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) =>
          bloc.add(const StartAdvertise('another-uuid-123')),
      expect: () => [isA<BleAdvertising>()],
      verify: (_) =>
          verify(mockRepository.startAdvertise('another-uuid-123'))
              .called(1),
    );
  });
}
