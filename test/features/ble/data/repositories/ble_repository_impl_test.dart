import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/ble/ble_manager.dart';
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
        'scanResults maps BleScannerDataSource scan results to BleDevice entities',
        () async {
      final scanResultsCtrl =
          StreamController<List<ScanResult>>.broadcast();
      when(mockScanner.scanResults).thenAnswer((_) => scanResultsCtrl.stream);

      final emitted = <List<BleDevice>>[];
      final sub = repository.scanResults.listen(emitted.add);

      final scanResult = ScanResult(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        deviceUuid: 'uuid-123',
        rssi: -50,
        distance: 1.0,
        proximity: ProximityLevel.close,
        timestamp: now,
      );
      scanResultsCtrl.add([scanResult]);

      await Future.delayed(Duration.zero);

      expect(emitted.length, 1);
      expect(emitted.first.length, 1);
      final device = emitted.first.first;
      expect(device.deviceId, 'AA:BB:CC:DD:EE:FF');
      expect(device.deviceUuid, 'uuid-123');
      expect(device.rssi, -50);
      expect(device.distance, 1.0);
      expect(device.proximity, ProximityLevel.close);

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

    test('bluetoothState emits true', () async {
      final states = <bool>[];
      final sub = repository.bluetoothState.listen(states.add);

      await Future.delayed(Duration.zero);

      expect(states, contains(true));

      await sub.cancel();
    });
  });
}
