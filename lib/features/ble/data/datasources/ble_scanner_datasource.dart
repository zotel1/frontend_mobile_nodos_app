import 'package:frontend_mobile_nodos_app/ble/ble_manager.dart';

abstract class BleScannerDataSource {
  Stream<List<ScanResult>> get scanResults;
  Future<void> startScan({List<String>? serviceUuids});
  Future<void> stopScan();
}
