/// Shared Service UUID for BLE discovery.
///
/// All Nodos devices advertise on this UUID — it is a protocol identifier,
/// analogous to a port number. Not a secret.
const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

/// UUID de la característica de identidad Nodos.
///
/// Bajo el Service UUID compartido, esta característica expone
/// un JSON `{uuid, name, color}` con los metadatos de identidad
/// del dispositivo remoto. Si el dispositivo no corre Nodos App,
/// la característica no existe → fallback a bottom sheet manual.
///
/// AD12: UUID propio bajo el mismo service, no UUIDs estándar (0x2A00).
const String identityCharacteristicUUID = '4fafc202-1fb5-459e-8fcc-c5c9c331914b';

/// Assumed RSSI at 1 meter (dBm). Will be calibrated in Phase 1.
const int txPower = -50;

/// RSSI threshold for "close" proximity (dBm).
const int proximityThresholdClose = -70;

/// RSSI threshold for "medium" proximity (dBm).
const int proximityThresholdMedium = -85;

/// RSSI threshold for "far" proximity — maximum range.
///
/// Devices below this RSSI are filtered out from scan results.
/// Relaxed from -85 (medium) to -95 to detect devices at greater
/// distance (~10-15m in open space). The datasource uses this
/// threshold in [_bindToPlatform] to decide which raw BLE scan
/// results are forwarded to the BleBloc.
///
/// Valores típicos: -45 (a 1m), -70 (a 3-5m), -85 (a 5-8m), -95 (a 10-15m).
/// Si en pruebas reales el ruido (falsos positivos) es excesivo, ajustar a -90.
const int proximityThresholdFar = -95;

/// Exponente de pérdida de trayectoria (n) para el modelo Friis.
///
/// Usado en distance_calc.dart para la fórmula:
///   distancia = 10 ^ ((txPower - rssi) / (10 * pathLossExponent))
///
/// n = 2.0 asume espacio libre (free-space). En interiores, valores
/// típicos van de 2.0 a 4.0. Este valor puede calibrarse en Phase 3.
const double pathLossExponent = 2.0;

/// BLE scan active duration per duty cycle period.
const Duration dutyCycleScanDuration = Duration(seconds: 2);

/// BLE pause duration per duty cycle period.
const Duration dutyCyclePauseDuration = Duration(seconds: 8);
