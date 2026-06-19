import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    hide ScanResult;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/ble/ble_manager.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

/// A fake BLE adapter that emits controlled scan results and adapter states.
class _FakeBleAdapter implements BleAdapter {
  final _scanResultsController = StreamController<List<ScanResult>>.broadcast();
  final _adapterStateController =
      StreamController<BluetoothAdapterState>.broadcast();

  bool scanning = false;
  bool advertising = false;
  List<String>? lastScanUuids;
  String? lastAdvertiseServiceUuid;
  String? lastAdvertiseDeviceUuid;

  @override
  Stream<List<ScanResult>> get scanResults => _scanResultsController.stream;

  @override
  Stream<BluetoothAdapterState> get adapterState =>
      _adapterStateController.stream;

  @override
  Future<void> startScan({required List<String> serviceUuids}) async {
    scanning = true;
    lastScanUuids = serviceUuids;
  }

  @override
  Future<void> stopScan() async {
    scanning = false;
  }

  @override
  Future<void> startAdvertise({
    required String serviceUuid,
    required String deviceUuid,
  }) async {
    advertising = true;
    lastAdvertiseServiceUuid = serviceUuid;
    lastAdvertiseDeviceUuid = deviceUuid;
  }

  @override
  Future<void> stopAdvertise() async {
    advertising = false;
  }

  /// Emits a list of [ScanResult]s onto the scan stream.
  void emitScanResults(List<ScanResult> results) {
    _scanResultsController.add(results);
  }

  /// Emits an adapter state.
  void emitAdapterState(BluetoothAdapterState state) {
    _adapterStateController.add(state);
  }

  /// Closes all stream controllers.
  void dispose() {
    _scanResultsController.close();
    _adapterStateController.close();
  }
}

void main() {
  group('BleManager — BLS-001 / BLA-001', () {
    late _FakeBleAdapter adapter;
    late BleManager manager;

    setUp(() {
      adapter = _FakeBleAdapter();
      manager = BleManager(adapter: adapter);
    });

    tearDown(() {
      adapter.dispose();
    });

    test('startScan() → sets isScanning true and forwards Service UUID', () async {
      expect(manager.isScanning, isFalse);

      await manager.startScan();

      expect(manager.isScanning, isTrue);
      expect(adapter.scanning, isTrue);
      expect(adapter.lastScanUuids, contains(serviceUuid));
    });

    test('stopScan() → sets isScanning false', () async {
      await manager.startScan();
      expect(manager.isScanning, isTrue);

      await manager.stopScan();

      expect(manager.isScanning, isFalse);
      expect(adapter.scanning, isFalse);
    });

    test('scanResults stream emits data from the adapter', () async {
      final results = <List<ScanResult>>[];
      final sub = manager.scanResults.listen(results.add);

      final testResult = ScanResult(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        deviceUuid: 'test-uuid-1234',
        rssi: -60,
        distance: 3.16,
        proximity: ProximityLevel.close,
        timestamp: DateTime(2026, 6, 18, 12, 0),
      );

      adapter.emitScanResults([testResult]);

      await Future<void>.delayed(Duration.zero);

      expect(results, hasLength(1));
      expect(results.first, hasLength(1));
      expect(results.first.first.deviceId, 'AA:BB:CC:DD:EE:FF');
      expect(results.first.first.rssi, -60);

      await sub.cancel();
    });

    test('scanResults filters devices with RSSI ≤ -85', () async {
      final results = <List<ScanResult>>[];
      final sub = manager.scanResults.listen(results.add);

      final goodDevice = ScanResult(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        deviceUuid: 'uuid-1',
        rssi: -60,
        distance: 3.16,
        proximity: ProximityLevel.close,
        timestamp: DateTime(2026),
      );

      final borderlineDevice = ScanResult(
        deviceId: 'BB:BB:CC:DD:EE:FF',
        deviceUuid: 'uuid-2',
        rssi: -85,
        distance: 56.0,
        proximity: ProximityLevel.medium,
        timestamp: DateTime(2026),
      );

      final weakDevice = ScanResult(
        deviceId: 'CC:BB:CC:DD:EE:FF',
        deviceUuid: 'uuid-3',
        rssi: -95,
        distance: 177.0,
        proximity: ProximityLevel.far,
        timestamp: DateTime(2026),
      );

      adapter.emitScanResults([goodDevice, borderlineDevice, weakDevice]);

      await Future<void>.delayed(Duration.zero);

      expect(results, hasLength(1));
      final filtered = results.first;
      expect(filtered, hasLength(2));
      expect(filtered.any((r) => r.rssi == -60), isTrue);
      expect(filtered.any((r) => r.rssi == -85), isTrue);
      expect(filtered.any((r) => r.rssi == -95), isFalse);

      await sub.cancel();
    });

    test('bluetoothState stream emits adapter states', () async {
      final states = <BluetoothAdapterState>[];
      final sub = manager.bluetoothState.listen(states.add);

      adapter.emitAdapterState(BluetoothAdapterState.on);
      adapter.emitAdapterState(BluetoothAdapterState.off);

      await Future<void>.delayed(Duration.zero);

      expect(states, hasLength(2));
      expect(states.first, BluetoothAdapterState.on);
      expect(states.last, BluetoothAdapterState.off);

      await sub.cancel();
    });

    test('startAdvertise() → sets isAdvertising true and forwards UUID',
        () async {
      expect(manager.isAdvertising, isFalse);

      await manager.startAdvertise('device-uuid-abc');

      expect(manager.isAdvertising, isTrue);
      expect(adapter.advertising, isTrue);
      expect(adapter.lastAdvertiseServiceUuid, serviceUuid);
      expect(adapter.lastAdvertiseDeviceUuid, 'device-uuid-abc');
    });

    test('stopAdvertise() → sets isAdvertising false', () async {
      await manager.startAdvertise('device-uuid');
      expect(manager.isAdvertising, isTrue);

      await manager.stopAdvertise();

      expect(manager.isAdvertising, isFalse);
      expect(adapter.advertising, isFalse);
    });
  });
}
