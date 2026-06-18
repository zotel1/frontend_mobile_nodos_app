/// Shared Service UUID for BLE discovery.
///
/// All Nodos devices advertise on this UUID — it is a protocol identifier,
/// analogous to a port number. Not a secret.
const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

/// Assumed RSSI at 1 meter (dBm). Will be calibrated in Phase 1.
const int txPower = -50;

/// RSSI threshold for "close" proximity (dBm).
const int proximityThresholdClose = -70;

/// RSSI threshold for "medium" proximity (dBm).
const int proximityThresholdMedium = -85;

/// BLE scan active duration per duty cycle period.
const Duration dutyCycleScanDuration = Duration(seconds: 2);

/// BLE pause duration per duty cycle period.
const Duration dutyCyclePauseDuration = Duration(seconds: 8);
