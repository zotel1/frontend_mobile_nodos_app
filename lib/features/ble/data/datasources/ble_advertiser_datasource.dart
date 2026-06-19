abstract class BleAdvertiserDataSource {
  Future<void> startAdvertise(String deviceUuid, String serviceUuid);
  Future<void> stopAdvertise();
}
