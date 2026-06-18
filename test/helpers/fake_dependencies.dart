import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide ScanResult;
import 'package:frontend_mobile_nodos_app/ble/ble_manager.dart';
import 'package:frontend_mobile_nodos_app/services/secure_storage.dart';

/// Fake BLE adapter that emits controlled scan results and adapter states
/// for widget tests.
class FakeBleAdapter implements BleAdapter {
  final _scanResultsController = StreamController<List<ScanResult>>.broadcast();
  final _adapterStateController =
      StreamController<BluetoothAdapterState>.broadcast();

  bool scanning = false;

  @override
  Stream<List<ScanResult>> get scanResults => _scanResultsController.stream;

  @override
  Stream<BluetoothAdapterState> get adapterState =>
      _adapterStateController.stream;

  @override
  Future<void> startScan({required List<String> serviceUuids}) async {
    scanning = true;
  }

  @override
  Future<void> stopScan() async {
    scanning = false;
  }

  @override
  Future<void> startAdvertise({
    required String serviceUuid,
    required String deviceUuid,
  }) async {}

  @override
  Future<void> stopAdvertise() async {}

  /// Emits scan results onto the scan stream.
  void emitScanResults(List<ScanResult> results) {
    _scanResultsController.add(results);
  }

  /// Emits an adapter state change.
  void emitAdapterState(BluetoothAdapterState state) {
    _adapterStateController.add(state);
  }

  /// Closes all stream controllers.
  void dispose() {
    _scanResultsController.close();
    _adapterStateController.close();
  }
}

/// In-memory SecureStorage implementation for tests.
class FakeSecureStorage extends SecureStorage {
  String? _uuid;

  @override
  Future<String?> getDeviceUuid() async => _uuid;

  @override
  Future<void> saveDeviceUuid(String uuid) async {
    _uuid = uuid;
  }

  @override
  Future<void> clearDeviceUuid() async {
    _uuid = null;
  }
}
