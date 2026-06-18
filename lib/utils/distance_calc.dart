import 'dart:math';

/// Proximity levels classified from RSSI signal strength.
enum ProximityLevel { close, medium, far }

/// Converts BLE RSSI value to estimated distance in meters.
///
/// Uses the simplified log-distance path loss model:
///   distance = 10 ^ ((txPower - rssi) / (10 * n))
///
/// Where txPower = -50 dBm (assumed RSSI at 1 meter) and n = 2.0
/// (free-space path loss exponent).
///
/// For rssi >= 0 (invalid/no signal), returns [double.infinity].
double rssiToDistance(int rssi) {
  // Clamp: rssi >= 0 indicates invalid/no signal reading.
  if (rssi >= 0) {
    return double.infinity;
  }
  return pow(10, (-50 - rssi) / 20.0).toDouble();
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
