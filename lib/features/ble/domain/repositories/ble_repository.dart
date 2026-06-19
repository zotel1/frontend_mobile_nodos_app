import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

abstract class BleRepository {
  Stream<List<BleDevice>> get scanResults;
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> startAdvertise(String deviceUuid);
  Future<void> stopAdvertise();
  Stream<bool> get bluetoothState;
}
