import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

abstract class BleRepository {
  Stream<List<BleDevice>> get scanResults;
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> startAdvertise(String deviceUuid, String name, String color);
  Future<void> stopAdvertise();
  Stream<bool> get bluetoothState;

  /// Cierra la sesión de escaneo activa estableciendo [endedAt].
  ///
  /// QUÉ hace: finaliza el ciclo de vida de la sesión de escaneo
  /// cuando el usuario detiene el scan o BT se apaga.
  ///
  /// POR QUÉ: sin este método las sesiones quedan con endedAt=null
  /// permanentemente, distorsionando estadísticas de historial.
  Future<void> endScanSession();
}
