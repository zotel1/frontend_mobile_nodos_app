import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/repositories/ble_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';

@GenerateNiceMocks([
  MockSpec<BleScannerDataSource>(),
  MockSpec<BleAdvertiserDataSource>(),
])
import 'ble_repository_impl_test.mocks.dart';

void main() {
  late MockBleScannerDataSource mockScanner;
  late MockBleAdvertiserDataSource mockAdvertiser;
  late BleRepository repository;

  final now = DateTime(2026, 6, 18, 12, 0, 0);

  setUp(() {
    mockScanner = MockBleScannerDataSource();
    mockAdvertiser = MockBleAdvertiserDataSource();
    repository = BleRepositoryImpl(
      scanner: mockScanner,
      advertiser: mockAdvertiser,
    );
  });

  group('BleRepositoryImpl', () {
    test('implements BleRepository', () {
      expect(repository, isA<BleRepository>());
    });

    test(
        'scanResults passes through BleScannerDataSource scan results',
        () async {
      final scanResultsCtrl =
          StreamController<List<BleDevice>>.broadcast();
      when(mockScanner.scanResults).thenAnswer((_) => scanResultsCtrl.stream);

      final emitted = <List<BleDevice>>[];
      final sub = repository.scanResults.listen(emitted.add);

      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        deviceUuid: 'uuid-123',
        rssi: -50,
        distance: 1.0,
        proximity: ProximityLevel.close,
        timestamp: now,
      );
      scanResultsCtrl.add([device]);

      await Future.delayed(Duration.zero);

      expect(emitted.length, 1);
      expect(emitted.first.length, 1);
      final result = emitted.first.first;
      expect(result.deviceId, 'AA:BB:CC:DD:EE:FF');
      expect(result.deviceUuid, 'uuid-123');
      expect(result.rssi, -50);
      expect(result.distance, 1.0);
      expect(result.proximity, ProximityLevel.close);

      await sub.cancel();
      await scanResultsCtrl.close();
    });

    test('startScan delegates to scanner', () async {
      when(mockScanner.startScan(serviceUuids: anyNamed('serviceUuids')))
          .thenAnswer((_) async {});

      await repository.startScan();

      verify(mockScanner.startScan(serviceUuids: anyNamed('serviceUuids')))
          .called(1);
    });

    // T1.1 F1: Escaneo promiscuo sin filtro UUID.
    // QUÉ: startScan() debe llamar al datasource con serviceUuids: null
    // para detectar cualquier dispositivo BLE, no solo los que anuncian el UUID Nodos.
    // POR QUÉ: flutter_ble_peripheral es stub → nadie anuncia el UUID Nodos.
    test('startScan calls datasource with null serviceUuids (promiscuous scan)',
        () async {
      when(mockScanner.startScan(serviceUuids: null))
          .thenAnswer((_) async {});

      await repository.startScan();

      verify(mockScanner.startScan(serviceUuids: null)).called(1);
    });

    test('stopScan delegates to scanner', () async {
      when(mockScanner.stopScan()).thenAnswer((_) async {});

      await repository.stopScan();

      verify(mockScanner.stopScan()).called(1);
    });

    test('startAdvertise delegates to advertiser', () async {
      when(mockAdvertiser.startAdvertise(any, any))
          .thenAnswer((_) async {});

      await repository.startAdvertise('device-uuid');

      verify(mockAdvertiser.startAdvertise('device-uuid', any)).called(1);
    });

    test('stopAdvertise delegates to advertiser', () async {
      when(mockAdvertiser.stopAdvertise()).thenAnswer((_) async {});

      await repository.stopAdvertise();

      verify(mockAdvertiser.stopAdvertise()).called(1);
    });

    test('bluetoothState delega al scanner.bluetoothState', () async {
      final btController = StreamController<bool>.broadcast();
      // Configuramos el mock del scanner para que exponga un stream controlado.
      when(mockScanner.bluetoothState).thenAnswer((_) => btController.stream);

      final states = <bool>[];
      final sub = repository.bluetoothState.listen(states.add);

      // Emitimos false (simula BT apagado) — debe llegar al repositorio.
      btController.add(false);
      await Future.delayed(Duration.zero);

      expect(states, [false]);

      // Emitimos true (BT se enciende) — tambien debe propagarse.
      btController.add(true);
      await Future.delayed(Duration.zero);

      expect(states, [false, true]);

      await sub.cancel();
      await btController.close();
    });
  });
}
