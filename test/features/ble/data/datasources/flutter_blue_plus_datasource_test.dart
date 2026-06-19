import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_blue_plus_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

void main() {
  final now = DateTime(2026, 6, 18, 12, 0, 0);

  BleDevice createBleDevice({
    String deviceId = 'AA:BB:CC:DD:EE:FF',
    String? deviceUuid,
    int rssi = -50,
    double distance = 1.0,
    ProximityLevel proximity = ProximityLevel.close,
    DateTime? timestamp,
  }) {
    return BleDevice(
      deviceId: deviceId,
      deviceUuid: deviceUuid,
      rssi: rssi,
      distance: distance,
      proximity: proximity,
      timestamp: timestamp ?? now,
    );
  }

  group('FlutterBluePlusDataSource', () {
    late StreamController<List<BleDevice>> streamController;

    setUp(() {
      streamController = StreamController<List<BleDevice>>.broadcast();
    });

    tearDown(() async {
      await streamController.close();
    });

    test('implements BleScannerDataSource', () {
      final dataSource =
          FlutterBluePlusDataSource.test(streamController.stream);
      expect(dataSource, isA<BleScannerDataSource>());
    });

    test('scanResults emits when injected stream pushes data', () async {
      final dataSource = FlutterBluePlusDataSource.test(
        streamController.stream,
      );

      final emitted = <List<BleDevice>>[];
      final subscription = dataSource.scanResults.listen(emitted.add);

      final device =
          createBleDevice(deviceId: 'AA:BB:CC:DD:EE:FF', rssi: -55);
      streamController.add([device]);

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

      final emitted = <List<BleDevice>>[];
      final subscription = dataSource.scanResults.listen(emitted.add);

      final device1 = createBleDevice(deviceId: 'AA', rssi: -50);
      final device2 = createBleDevice(deviceId: 'BB', rssi: -60);

      streamController.add([device1]);
      await Future.delayed(Duration.zero);
      streamController.add([device2]);
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

      final emitted = <List<BleDevice>>[];
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

  group('bluetoothState', () {
    test('emite true cuando btStateStream emite true (adaptador encendido)',
        () async {
      final btController = StreamController<bool>.broadcast();
      final dataSource = FlutterBluePlusDataSource.test(
        Stream<List<BleDevice>>.empty(),
        btStateStream: btController.stream,
      );

      final states = <bool>[];
      final sub = dataSource.bluetoothState.listen(states.add);

      btController.add(true);
      await Future.delayed(Duration.zero);

      expect(states, [true]);

      await sub.cancel();
      await btController.close();
    });

    test('emite false cuando btStateStream emite false (adaptador apagado)',
        () async {
      final btController = StreamController<bool>.broadcast();
      final dataSource = FlutterBluePlusDataSource.test(
        Stream<List<BleDevice>>.empty(),
        btStateStream: btController.stream,
      );

      final states = <bool>[];
      final sub = dataSource.bluetoothState.listen(states.add);

      btController.add(false);
      await Future.delayed(Duration.zero);

      expect(states, [false]);

      await sub.cancel();
      await btController.close();
    });

    test('emite múltiples valores cuando btStateStream alterna', () async {
      final btController = StreamController<bool>.broadcast();
      final dataSource = FlutterBluePlusDataSource.test(
        Stream<List<BleDevice>>.empty(),
        btStateStream: btController.stream,
      );

      final states = <bool>[];
      final sub = dataSource.bluetoothState.listen(states.add);

      btController.add(true);
      await Future.delayed(Duration.zero);
      btController.add(false);
      await Future.delayed(Duration.zero);
      btController.add(true);
      await Future.delayed(Duration.zero);

      expect(states, [true, false, true]);

      await sub.cancel();
      await btController.close();
    });
  });
}
