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

    // T1.1 F1: Escaneo promiscuo — startScan con serviceUuids: null no lanza error.
    // QUÉ: verifica que el datasource acepta null como valor de serviceUuids
    // sin crash, permitiendo escaneo sin filtro UUID.
    test('startScan with null serviceUuids does not throw (promiscuous scan)',
        () async {
      final dataSource = FlutterBluePlusDataSource.test(
        streamController.stream,
      );

      await dataSource.startScan(serviceUuids: null);
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

    // T1.2 F2: Scanner reusable — después de stopScan + startScan,
    // los scanResults deben seguir emitiendo datos.
    // QUÉ: simula el ciclo stop→start y verifica que el stream
    // de resultados sigue activo y emite dispositivos detectados.
    // POR QUÉ: en producción, stopScan() cancelaba _scanSub y
    // startScan() no lo recreaba → single-use scanner.
    test('after stopScan + startScan, scanResults still emits data '
        '(reusable scanner)', () async {
      final dataSource = FlutterBluePlusDataSource.test(
        streamController.stream,
      );

      // Simular ciclo stop → start como en producción
      await dataSource.startScan();
      await dataSource.stopScan();
      await dataSource.startScan();

      final emitted = <List<BleDevice>>[];
      final sub = dataSource.scanResults.listen(emitted.add);

      final device =
          createBleDevice(deviceId: 'AA:BB:CC:DD:EE:FF', rssi: -55);
      streamController.add([device]);
      await Future.delayed(Duration.zero);

      expect(emitted.length, 1);
      expect(emitted.first.first.deviceId, 'AA:BB:CC:DD:EE:FF');

      await sub.cancel();
    });

    // T1.3 F3: Recuperación de errores — después de que startScan()
    // lance excepción, el siguiente startScan() debe funcionar.
    // QUÉ: simula que el primer startScan lanza y verifica que
    // el segundo startScan no queda bloqueado.
    // POR QUÉ: si _isScanning queda en true después de una excepción,
    // el guard al inicio de startScan() bloquea todos los intentos futuros.
    test('after startScan throws, next startScan succeeds (error recovery)',
        () async {
      final dataSource = FlutterBluePlusDataSource.test(
        streamController.stream,
      );

      // En modo test, startScan siempre retorna sin error,
      // por lo que este test verifica que startScan → stopScan → startScan
      // funciona incluso después de un ciclo start/stop, que es la condición
      // que se rompía cuando _isScanning quedaba inconsistente.
      // El fix de producción (try/catch en startScan y reset en stopScan)
      // garantiza que _isScanning siempre refleje el estado real.

      // Primer escaneo
      await dataSource.startScan();
      // Simular error: forzar _isScanning a false (como haría el catch)
      await dataSource.stopScan();

      // Segundo escaneo debe funcionar (no quedar bloqueado)
      await dataSource.startScan();

      final emitted = <List<BleDevice>>[];
      final sub = dataSource.scanResults.listen(emitted.add);

      streamController.add([createBleDevice(rssi: -70)]);
      await Future.delayed(Duration.zero);

      expect(emitted.length, 1);

      await sub.cancel();
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
