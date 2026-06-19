import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/ble/ble_manager.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_blue_plus_datasource.dart';

void main() {
  final now = DateTime(2026, 6, 18, 12, 0, 0);

  ScanResult createResult({
    String deviceId = 'AA:BB:CC:DD:EE:FF',
    String? deviceUuid,
    int rssi = -50,
    double distance = 1.0,
    ProximityLevel proximity = ProximityLevel.close,
    DateTime? timestamp,
  }) {
    return ScanResult(
      deviceId: deviceId,
      deviceUuid: deviceUuid,
      rssi: rssi,
      distance: distance,
      proximity: proximity,
      timestamp: timestamp ?? now,
    );
  }

  group('FlutterBluePlusDataSource', () {
    late StreamController<List<ScanResult>> streamController;

    setUp(() {
      streamController = StreamController<List<ScanResult>>.broadcast();
    });

    tearDown(() async {
      await streamController.close();
    });

    test('implements BleScannerDataSource', () {
      final dataSource = FlutterBluePlusDataSource.test(streamController.stream);
      expect(dataSource, isA<BleScannerDataSource>());
    });

    test('scanResults emits when injected stream pushes data', () async {
      final dataSource = FlutterBluePlusDataSource.test(
        streamController.stream,
      );

      final emitted = <List<ScanResult>>[];
      final subscription = dataSource.scanResults.listen(emitted.add);

      final result = createResult(deviceId: 'AA:BB:CC:DD:EE:FF', rssi: -55);
      streamController.add([result]);

      // Allow microtask to process stream event
      await Future.delayed(Duration.zero);

      expect(emitted.length, 1);
      expect(emitted.first.length, 1);
      expect(emitted.first.first.deviceId, 'AA:BB:CC:DD:EE:FF');
      expect(emitted.first.first.rssi, -55);

      await subscription.cancel();
    });

    test('scanResults emits multiple events for multiple stream pushes',
        () async {
      final dataSource = FlutterBluePlusDataSource.test(
        streamController.stream,
      );

      final emitted = <List<ScanResult>>[];
      final subscription = dataSource.scanResults.listen(emitted.add);

      final result1 = createResult(deviceId: 'AA', rssi: -50);
      final result2 = createResult(deviceId: 'BB', rssi: -60);

      streamController.add([result1]);
      await Future.delayed(Duration.zero);
      streamController.add([result2]);
      await Future.delayed(Duration.zero);

      expect(emitted.length, 2);
      expect(emitted[0].first.deviceId, 'AA');
      expect(emitted[1].first.deviceId, 'BB');

      await subscription.cancel();
    });

    test('scanResults does not emit when empty list is pushed', () async {
      final dataSource = FlutterBluePlusDataSource.test(
        streamController.stream,
      );

      final emitted = <List<ScanResult>>[];
      final subscription = dataSource.scanResults.listen(emitted.add);

      streamController.add([]);
      await Future.delayed(Duration.zero);

      expect(emitted, isEmpty);

      await subscription.cancel();
    });

    test('startScan does not throw', () async {
      final dataSource = FlutterBluePlusDataSource.test(
        streamController.stream,
      );

      // startScan should not throw when called
      await dataSource.startScan(serviceUuids: [
        '4fafc201-1fb5-459e-8fcc-c5c9c331914b',
      ]);
    });

    test('stopScan does not throw', () async {
      final dataSource = FlutterBluePlusDataSource.test(
        streamController.stream,
      );

      await dataSource.stopScan();
    });

    test('startScan then stopScan does not throw', () async {
      final dataSource = FlutterBluePlusDataSource.test(
        streamController.stream,
      );

      await dataSource.startScan();
      await dataSource.stopScan();
    });
  });
}
