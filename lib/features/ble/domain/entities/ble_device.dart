import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

class BleDevice extends Equatable {
  final String deviceId;
  final String? deviceUuid;
  final int rssi;
  final double distance;
  final ProximityLevel proximity;
  final DateTime timestamp;

  /// Nombre anunciado en el advertisement BLE (advName).
  /// Puede diferir del nombre del SO (platformName).
  final String? advName;

  /// Nombre asignado por el sistema operativo al dispositivo.
  final String? platformName;

  /// Potencia de transmisión (txPower) anunciada por el dispositivo.
  /// Null si el dispositivo no la incluye en su advertisement.
  final int? txPowerLevel;

  /// Si el dispositivo acepta conexiones GATT.
  final bool connectable;

  /// UUIDs de servicio anunciados en el advertisement.
  final List<String>? serviceUuids;

  /// Tipo de dispositivo clasificado (ej: "Reloj/Fitness", "Nodo").
  /// Calculado por DeviceClassifier a partir de serviceUuids y manufacturerId.
  final String? deviceType;

  const BleDevice({
    required this.deviceId,
    this.deviceUuid,
    required this.rssi,
    required this.distance,
    required this.proximity,
    required this.timestamp,
    this.advName,
    this.platformName,
    this.txPowerLevel,
    this.connectable = false,
    this.serviceUuids,
    this.deviceType,
  });

  @override
  List<Object?> get props => [
        deviceId,
        deviceUuid,
        rssi,
        distance,
        proximity,
        timestamp,
        advName,
        platformName,
        txPowerLevel,
        connectable,
        serviceUuids,
        deviceType,
      ];
}
