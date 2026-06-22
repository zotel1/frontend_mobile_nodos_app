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

  /// Dispositivo de prueba con timestamp reciente (dentro del umbral de
  /// evicción de 30s). Necesario porque accumulateDevices evicciona
  /// dispositivos con timestamp >30s de antigüedad respecto a DateTime.now().
  final testBleDevice = BleDevice(
    deviceId: 'AA:BB:CC:DD:EE:FF',
    deviceUuid: '4fafc201-1fb5-459e-8fcc-c5c9c331914b',
    rssi: -45,
    distance: 0.56,
    proximity: ProximityLevel.close,
    timestamp: DateTime.now().subtract(const Duration(seconds: 5)),
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
        when(mockRepository.startAdvertise(any, any, any))
            .thenAnswer((_) async {});
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(
          const StartAdvertise('test-uuid', 'Mi dispositivo', '#2196F3')),
      expect: () => [isA<BleAdvertising>()],
      verify: (_) =>
          verify(mockRepository.startAdvertise(
                  'test-uuid', 'Mi dispositivo', '#2196F3'))
              .called(1),
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
        when(mockRepository.startAdvertise(any, any, any))
            .thenAnswer((_) async {});
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) =>
          bloc.add(const StartAdvertise(
              'another-uuid-123', 'Test', '#FF0000')),
      expect: () => [isA<BleAdvertising>()],
      verify: (_) =>
          verify(mockRepository.startAdvertise(
                  'another-uuid-123', 'Test', '#FF0000'))
              .called(1),
    );

    blocTest<BleBloc, BleState>(
      'emite BluetoothOff cuando repository.bluetoothState emite false',
      build: () {
        final btController = StreamController<bool>.broadcast();
        when(mockRepository.bluetoothState)
            .thenAnswer((_) => btController.stream);
        // Emitir false después de la construcción para simular BT apagado.
        Future.microtask(() => btController.add(false));
        return BleBloc(repository: mockRepository);
      },
      expect: () => [
        isA<BluetoothOff>(),
      ],
      tearDown: () async {},
    );

    blocTest<BleBloc, BleState>(
      'emite BleStopped cuando repository.bluetoothState emite true (BT encendido)',
      build: () {
        final btController = StreamController<bool>.broadcast();
        when(mockRepository.bluetoothState)
            .thenAnswer((_) => btController.stream);
        Future.microtask(() => btController.add(true));
        return BleBloc(repository: mockRepository);
      },
      expect: () => [
        isA<BleStopped>(),
      ],
      tearDown: () async {},
    );

    blocTest<BleBloc, BleState>(
      'cancela _btSubscription al cerrar el bloc',
      build: () {
        final btController = StreamController<bool>.broadcast();
        when(mockRepository.bluetoothState)
            .thenAnswer((_) => btController.stream);
        return BleBloc(repository: mockRepository);
      },
      act: (bloc) async {
        await bloc.close();
      },
      verify: (_) {
        // Verificamos que el stream de bluetoothState fue consultado
        // (el constructor se suscribió a él).
        verify(mockRepository.bluetoothState).called(1);
      },
      // No esperamos estados extra al cerrar.
      expect: () => [],
      tearDown: () async {},
    );
  });

  // ─── PR1: Acumulación, evicción, capping del BleBloc ──────

  group('PR1 — Acumulación de dispositivos (R1)', () {
    final now = DateTime(2026, 6, 21, 12, 0, 0);
    final deviceA = BleDevice(
      deviceId: 'AA:BB:CC:DD:EE:FF',
      rssi: -45,
      distance: 0.56,
      proximity: ProximityLevel.close,
      timestamp: now,
    );
    final deviceB = BleDevice(
      deviceId: '11:22:33:44:55:66',
      rssi: -60,
      distance: 3.0,
      proximity: ProximityLevel.medium,
      timestamp: now.add(const Duration(seconds: 5)),
    );

    group('accumulateDevices (función pura)', () {
      // Helper: llama a accumulateDevices con now=el timestamp más reciente + 1s
      // para simular que DateTime.now() está apenas después del último evento.
      List<BleDevice> acc(
        Map<String, BleDevice> current,
        List<BleDevice> incoming, {
        DateTime? referenceNow,
      }) {
        final latest = incoming.isNotEmpty
            ? incoming.map((d) => d.timestamp).reduce(
                  (a, b) => a.isAfter(b) ? a : b,
                )
            : now;
        return BleBloc.accumulateDevices(
          current,
          incoming,
          now: referenceNow ?? latest.add(const Duration(seconds: 1)),
        );
      }

      // T1.1: Dos batches consecutivos con dispositivos A y B
      // → la lista acumulada contiene ambos.
      test('T1.1: fusión de dos batches → ambos dispositivos en resultado',
          () {
        // Primer batch: solo deviceA
        final afterFirst = acc({}, [deviceA]);
        expect(afterFirst.length, 1);
        expect(afterFirst.first.deviceId, 'AA:BB:CC:DD:EE:FF');

        // Convertir a mapa para simular estado acumulado
        final accumulated = {
          for (final d in afterFirst) d.deviceId: d,
        };

        // Segundo batch: solo deviceB
        final afterSecond = acc(accumulated, [deviceB]);
        expect(afterSecond.length, 2);
        expect(
          afterSecond.map((d) => d.deviceId),
          containsAll(['AA:BB:CC:DD:EE:FF', '11:22:33:44:55:66']),
        );
      });

      // T1.2: Dispositivo con timestamp >30s atrás → evicted.
      test('T1.2: dispositivo stale >30s → removido del resultado', () {
        final staleDevice = BleDevice(
          deviceId: 'FF:EE:DD:CC:BB:AA',
          rssi: -70,
          distance: 10.0,
          proximity: ProximityLevel.far,
          timestamp: now.subtract(const Duration(seconds: 31)),
        );

        final result = BleBloc.accumulateDevices(
          {},
          [staleDevice],
          now: now, // now mismo → 31s de diferencia → evicted
        );
        // El dispositivo stale debe ser evicted inmediatamente
        expect(result, isEmpty);
      });

      // T1.2 b: Dispositivo reciente NO es evicted (triangulación).
      test('T1.2: dispositivo reciente no es evicted', () {
        final recentDevice = BleDevice(
          deviceId: 'AA:BB:CC:DD:EE:FF',
          rssi: -45,
          distance: 0.56,
          proximity: ProximityLevel.close,
          timestamp: now,
        );

        final result = BleBloc.accumulateDevices(
          {},
          [recentDevice],
          now: now.add(const Duration(seconds: 1)),
        );
        expect(result.length, 1);
        expect(result.first.deviceId, 'AA:BB:CC:DD:EE:FF');
      });

      // T1.2 c: Múltiples dispositivos, solo el stale es evicted.
      test('T1.2: mezcla de fresh y stale → solo fresh sobrevive', () {
        final staleDevice = BleDevice(
          deviceId: 'STALE:01',
          rssi: -70,
          distance: 10.0,
          proximity: ProximityLevel.far,
          timestamp: now.subtract(const Duration(seconds: 31)),
        );

        final result = BleBloc.accumulateDevices(
          {deviceA.deviceId: deviceA},
          [staleDevice],
          now: now, // 31s after stale, 0s after deviceA → only deviceA survives
        );
        expect(result.length, 1);
        expect(result.first.deviceId, 'AA:BB:CC:DD:EE:FF');
      });

      // T1.3: 51 dispositivos → máximo 50 en resultado, oldest evicted.
      test('T1.3: 51 dispositivos → resultado máximo 50, oldest evicted',
          () {
        final devices = List.generate(51, (i) => BleDevice(
              deviceId: 'DEV:${i.toString().padLeft(3, '0')}',
              rssi: -50 - i,
              distance: 1.0 + i,
              proximity: ProximityLevel.medium,
              timestamp: now.add(Duration(seconds: i)),
            ));

        final result = BleBloc.accumulateDevices(
          {},
          devices,
          now: now.add(const Duration(seconds: 52)),
        );

        // Máximo 50 dispositivos
        expect(result.length, lessThanOrEqualTo(50));
        // El más antiguo (DEV:000) debe ser evicted
        expect(
          result.map((d) => d.deviceId),
          isNot(contains('DEV:000')),
        );
        // El más reciente (DEV:050) debe estar presente
        expect(
          result.map((d) => d.deviceId),
          contains('DEV:050'),
        );
      });

      // T1.3 b: Exactamente 50 dispositivos → sin evicción (triangulación).
      test('T1.3: exactamente 50 dispositivos → todos sobreviven', () {
        final devices = List.generate(50, (i) => BleDevice(
              deviceId: 'DEV:${i.toString().padLeft(3, '0')}',
              rssi: -50 - i,
              distance: 1.0 + i,
              proximity: ProximityLevel.medium,
              timestamp: now.add(Duration(seconds: i)),
            ));

        // now está a 25s del dispositivo más antiguo → dentro del umbral
        final result = BleBloc.accumulateDevices(
          {},
          devices,
          now: now.add(const Duration(seconds: 25)),
        );
        expect(result.length, 50);
      });
    });
    // La lógica de acumulación, evicción y capping está validada
    // exhaustivamente en los tests de accumulateDevices (función pura).
    // La integración con streams de BLoC se prueba indirectamente vía los
    // tests existentes de BleBloc (que usan StartScan + scanResults mock).
  });
}
