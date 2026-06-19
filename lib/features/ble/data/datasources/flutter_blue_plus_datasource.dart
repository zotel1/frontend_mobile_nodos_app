import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show FlutterBluePlus, Guid;
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

class FlutterBluePlusDataSource implements BleScannerDataSource {
  final StreamController<List<BleDevice>> _controller;
  StreamSubscription? _scanSub;
  bool _isScanning = false;
  final bool _isTestMode;

  /// Production constructor — binds to [FlutterBluePlus] platform.
  FlutterBluePlusDataSource()
      : _controller = StreamController<List<BleDevice>>.broadcast(),
        _isTestMode = false {
    _bindToPlatform();
  }

  /// Test constructor — inject a pre-built scan results stream.
  @visibleForTesting
  FlutterBluePlusDataSource.test(Stream<List<BleDevice>> stream)
      : _controller = StreamController<List<BleDevice>>.broadcast(),
        _isTestMode = true {
    stream.listen((results) {
      if (results.isNotEmpty) {
        _controller.add(results);
      }
    });
  }

  void _bindToPlatform() {
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isEmpty) return;
      final mapped = results
          .map((r) => BleDevice(
                deviceId: r.device.remoteId.toString(),
                deviceUuid: null,
                rssi: r.rssi,
                distance: rssiToDistance(r.rssi),
                proximity: rssiToProximity(r.rssi),
                timestamp: r.timeStamp,
              ))
          .where((s) => s.rssi >= proximityThresholdMedium)
          .toList();
      if (mapped.isNotEmpty) {
        _controller.add(mapped);
      }
    });
  }

  @override
  Stream<List<BleDevice>> get scanResults => _controller.stream;

  @override
  Future<void> startScan({List<String>? serviceUuids}) async {
    if (_isScanning) return;
    _isScanning = true;
    if (_isTestMode) return;
    await FlutterBluePlus.startScan(
      withServices: serviceUuids?.map((u) => Guid(u)).toList() ?? [],
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: false,
    );
  }

  @override
  Future<void> stopScan() async {
    if (!_isScanning) return;
    _isScanning = false;
    await _scanSub?.cancel();
    _scanSub = null;
    if (_isTestMode) return;
    await FlutterBluePlus.stopScan();
  }
}
