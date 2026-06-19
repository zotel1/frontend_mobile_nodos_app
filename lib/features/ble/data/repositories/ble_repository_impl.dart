import 'dart:async';
import 'package:frontend_mobile_nodos_app/ble/ble_manager.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

class BleRepositoryImpl implements BleRepository {
  final BleScannerDataSource _scanner;
  final BleAdvertiserDataSource _advertiser;

  // ignore: prefer_initializing_formals
  BleRepositoryImpl({
    required BleScannerDataSource scanner,
    required BleAdvertiserDataSource advertiser,
  })  : _scanner = scanner,
        _advertiser = advertiser;

  @override
  Stream<List<BleDevice>> get scanResults => _scanner.scanResults.map(
        (results) => results.map(_toBleDevice).toList(),
      );

  @override
  Future<void> startScan() => _scanner.startScan();

  @override
  Future<void> stopScan() => _scanner.stopScan();

  @override
  Future<void> startAdvertise(String deviceUuid) =>
      _advertiser.startAdvertise(deviceUuid, serviceUuid);

  @override
  Future<void> stopAdvertise() => _advertiser.stopAdvertise();

  @override
  Stream<bool> get bluetoothState async* {
    yield true;
  }

  BleDevice _toBleDevice(ScanResult r) => BleDevice(
        deviceId: r.deviceId,
        deviceUuid: r.deviceUuid,
        rssi: r.rssi,
        distance: r.distance,
        proximity: r.proximity,
        timestamp: r.timestamp,
      );
}
