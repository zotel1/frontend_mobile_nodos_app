import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

abstract class BleScannerDataSource {
  Stream<List<BleDevice>> get scanResults;
  Stream<bool> get bluetoothState;
  Future<void> startScan({List<String>? serviceUuids});
  Future<void> stopScan();
}
