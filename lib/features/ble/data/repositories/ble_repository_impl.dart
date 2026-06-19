import 'dart:async';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

class BleRepositoryImpl implements BleRepository {
  final BleScannerDataSource _scanner;
  final BleAdvertiserDataSource _advertiser;

  BleRepositoryImpl({
    required BleScannerDataSource scanner,
    required BleAdvertiserDataSource advertiser,
  })  : _scanner = scanner,
        _advertiser = advertiser;

  @override
  Stream<List<BleDevice>> get scanResults => _scanner.scanResults;

  @override
  Future<void> startScan() => _scanner.startScan(
        serviceUuids: [serviceUuid],
      );

  @override
  Future<void> stopScan() => _scanner.stopScan();

  @override
  Future<void> startAdvertise(String deviceUuid) =>
      _advertiser.startAdvertise(deviceUuid, serviceUuid);

  @override
  Future<void> stopAdvertise() => _advertiser.stopAdvertise();

  /// Delegación directa al scanner: el stream de estado BT viene
  /// de [FlutterBluePlusDataSource.bluetoothState], que a su vez
  /// deriva de [FlutterBluePlus.adapterState].
  @override
  Stream<bool> get bluetoothState => _scanner.bluetoothState;
}
