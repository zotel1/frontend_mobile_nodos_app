import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

class BleDevice extends Equatable {
  final String deviceId;
  final String? deviceUuid;
  final int rssi;
  final double distance;
  final ProximityLevel proximity;
  final DateTime timestamp;

  const BleDevice({
    required this.deviceId,
    this.deviceUuid,
    required this.rssi,
    required this.distance,
    required this.proximity,
    required this.timestamp,
  });

  @override
  List<Object?> get props =>
      [deviceId, deviceUuid, rssi, distance, proximity, timestamp];
}
