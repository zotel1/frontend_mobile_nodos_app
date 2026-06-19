import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';

/// Stub implementation of [BleAdvertiserDataSource].
///
/// flutter_ble_peripheral v2.1.1 API may vary — full implementation deferred
/// to Phase 2 after real-device validation.
class FlutterBlePeripheralDataSource implements BleAdvertiserDataSource {
  bool _advertising = false;

  @override
  Future<void> startAdvertise(String deviceUuid, String serviceUuid) async {
    if (_advertising) return;
    _advertising = true;
    // TODO(phase-2): integrate flutter_ble_peripheral.startAdvertising()
  }

  @override
  Future<void> stopAdvertise() async {
    if (!_advertising) return;
    _advertising = false;
    // TODO(phase-2): integrate flutter_ble_peripheral.stopAdvertising()
  }
}
