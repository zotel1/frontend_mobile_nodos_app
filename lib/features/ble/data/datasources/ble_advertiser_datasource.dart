abstract class BleAdvertiserDataSource {
  /// Inicia el advertising BLE con los metadatos de identidad del dispositivo.
  ///
  /// [deviceUuid] — UUIDv4 del dispositivo local.
  /// [name] — nombre del usuario (ej. "Mi dispositivo").
  /// [color] — color del usuario en hex (ej. "#2196F3").
  Future<void> startAdvertise(
      String deviceUuid, String name, String color);
  Future<void> stopAdvertise();
}
