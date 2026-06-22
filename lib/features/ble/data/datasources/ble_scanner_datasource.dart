import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

abstract class BleScannerDataSource {
  Stream<List<BleDevice>> get scanResults;
  Stream<bool> get bluetoothState;
  Future<void> startScan({List<String>? serviceUuids});
  Future<void> stopScan();

  /// Libera los recursos internos del datasource (streams, suscripciones).
  ///
  /// QUÉ: cierra el StreamController interno y cancela cualquier
  /// suscripción activa de escaneo BLE.
  ///
  /// POR QUÉ: sin este método, los StreamControllers nunca se cierran
  /// y quedan como memory leak cuando el datasource ya no se usa (P1).
  /// La interfaz lo declara para permitir limpieza polimórfica desde
  /// la capa de repositorio o BLoC.
  void dispose();
}
