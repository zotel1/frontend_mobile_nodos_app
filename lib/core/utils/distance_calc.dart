import 'dart:math';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';

/// Proximity levels classified from RSSI signal strength.
enum ProximityLevel { close, medium, far }

/// Converts BLE RSSI value to estimated distance in meters.
///
/// Uses the simplified log-distance path loss model:
///   distance = 10 ^ ((txPower - rssi) / (10 * pathLossExponent))
///
/// Where:
/// - [txPower] is the assumed RSSI at 1 meter (from app_config.dart).
/// - [pathLossExponent] is the n factor in the Friis formula (n=2.0 for
///   free-space, higher for indoor environments).
///
/// For rssi >= 0 (invalid/no signal), returns [double.infinity].
///
/// Si se provee [txPowerLevel], se usa ese valor en lugar de la constante
/// [txPower] de configuración. Esto permite calcular distancia con la
/// potencia de transmisión real anunciada por el dispositivo BLE, que
/// puede diferir del valor asumido (-50 dBm).
double rssiToDistance(int rssi, {int? txPowerLevel}) {
  // Clamp: rssi >= 0 indicates invalid/no signal reading.
  if (rssi >= 0) {
    return double.infinity;
  }
  final effectiveTxPower = txPowerLevel ?? txPower;
  return pow(10, (effectiveTxPower - rssi) / (10 * pathLossExponent))
      .toDouble();
}

/// Classifies an RSSI reading into a [ProximityLevel].
///
/// Thresholds:
/// - rssi > -70 → [ProximityLevel.close]
/// - -70 >= rssi >= -85 → [ProximityLevel.medium]
/// - rssi < -85 → [ProximityLevel.far]
/// - rssi >= 0 → [ProximityLevel.far] (invalid signal)
ProximityLevel rssiToProximity(int rssi) {
  if (rssi >= 0) {
    return ProximityLevel.far;
  }
  if (rssi > -70) {
    return ProximityLevel.close;
  }
  if (rssi >= -85) {
    return ProximityLevel.medium;
  }
  return ProximityLevel.far;
}
