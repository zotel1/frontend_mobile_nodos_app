import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/config/app_config.dart';
import '../core/utils/distance_calc.dart';

/// A BLE scan result with our app-level metadata.
class ScanResult {
  final String deviceId;
  final String? deviceUuid;
  final int rssi;
  final double distance;
  final ProximityLevel proximity;
  final DateTime timestamp;

  const ScanResult({
    required this.deviceId,
    required this.deviceUuid,
    required this.rssi,
    required this.distance,
    required this.proximity,
    required this.timestamp,
  });
}

/// Abstract BLE adapter that [BleManager] delegates to.
///
/// Real implementation: [FlutterBluePlusAdapter]. Test implementation: fake
/// with [StreamController]s.
abstract class BleAdapter {
  Stream<List<ScanResult>> get scanResults;
  Stream<BluetoothAdapterState> get adapterState;

  Future<void> startScan({required List<String> serviceUuids});
  Future<void> stopScan();

  Future<void> startAdvertise({
    required String serviceUuid,
    required String deviceUuid,
  });
  Future<void> stopAdvertise();
}

/// BLE manager that wraps a [BleAdapter] and provides:
/// - scan lifecycle (start/stop with RSSI filtering)
/// - advertise lifecycle (start/stop with device UUID payload)
/// - bluetooth adapter state stream
class BleManager {
  final BleAdapter _adapter;

  bool _scanning = false;
  bool _advertising = false;

  /// Creates a [BleManager] backed by a [FlutterBluePlusAdapter] by default.
  ///
  /// Pass [adapter] to inject a fake for testing.
  BleManager({BleAdapter? adapter})
      : _adapter = adapter ?? FlutterBluePlusAdapter();

  /// Stream of discovered BLE devices (already filtered by RSSI >= -85).
  Stream<List<ScanResult>> get scanResults =>
      _adapter.scanResults.map(_filterByRssi);

  /// Stream of Bluetooth adapter state changes.
  Stream<BluetoothAdapterState> get bluetoothState => _adapter.adapterState;

  /// Whether a BLE scan is currently active.
  bool get isScanning => _scanning;

  /// Whether BLE advertising is currently active.
  bool get isAdvertising => _advertising;

  /// Starts a BLE scan filtered to our Service UUID.
  Future<void> startScan() async {
    if (_scanning) return;
    _scanning = true;
    await _adapter.startScan(serviceUuids: [serviceUuid]);
  }

  /// Stops the active BLE scan.
  Future<void> stopScan() async {
    if (!_scanning) return;
    _scanning = false;
    await _adapter.stopScan();
  }

  /// Starts BLE advertising with our Service UUID and the given device UUID
  /// as manufacturer payload.
  Future<void> startAdvertise(String deviceUuid) async {
    if (_advertising) return;
    _advertising = true;
    await _adapter.startAdvertise(
      serviceUuid: serviceUuid,
      deviceUuid: deviceUuid,
    );
  }

  /// Stops BLE advertising.
  Future<void> stopAdvertise() async {
    if (!_advertising) return;
    _advertising = false;
    await _adapter.stopAdvertise();
  }

  /// Filters out devices with RSSI below the threshold (-85 dBm).
  List<ScanResult> _filterByRssi(List<ScanResult> results) {
    return results.where((r) => r.rssi >= -85).toList();
  }
}

/// Real [BleAdapter] that delegates to [FlutterBluePlus].
///
/// Note: BLE advertising is not directly supported by flutter_blue_plus
/// v1.36+. The `startAdvertise`/`stopAdvertise` methods are stubs for now.
/// Platform-specific advertising will be added in Phase 1.
class FlutterBluePlusAdapter implements BleAdapter {
  final _scanResultsController = StreamController<List<ScanResult>>.broadcast();
  StreamSubscription? _scanSub;

  @override
  Stream<List<ScanResult>> get scanResults => _scanResultsController.stream;

  @override
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  @override
  Future<void> startScan({required List<String> serviceUuids}) async {
    _scanSub = FlutterBluePlus.scanResults.listen((rawResults) {
      if (rawResults.isEmpty) return;
      final mapped = rawResults.map((r) {
        final rssi = r.rssi;
        final distance = rssiToDistance(rssi);
        final proximity = rssiToProximity(rssi);
        return ScanResult(
          deviceId: r.device.remoteId.toString(),
          deviceUuid: null,
          rssi: rssi,
          distance: distance,
          proximity: proximity,
          timestamp: DateTime.now(),
        );
      }).toList();
      _scanResultsController.add(mapped);
    });

    await FlutterBluePlus.startScan(
      withServices: serviceUuids.map((u) => Guid(u)).toList(),
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: false,
    );
  }

  @override
  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();
  }

  @override
  Future<void> startAdvertise({
    required String serviceUuid,
    required String deviceUuid,
  }) async {
    // Advertising is not available in flutter_blue_plus 1.36+.
    // Platform-specific implementation deferred to Phase 1.
  }

  @override
  Future<void> stopAdvertise() async {
    // See startAdvertise note above.
  }
}
