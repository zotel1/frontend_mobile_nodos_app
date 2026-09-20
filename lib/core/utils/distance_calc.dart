import 'dart:math';

import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';

/// Niveles de proximidad derivados de la intensidad de señal BLE.
///
/// IMPORTANTE:
/// RSSI permite estimar proximidad de forma razonable, pero no representa
/// una medición física precisa de distancia.
enum ProximityLevel { close, medium, far }

/// Convierte un RSSI BLE en una distancia aproximada expresada en metros.
///
/// Utiliza el modelo log-distance:
///
///   distance = 10 ^ ((measuredPower - rssi) / (10 * n))
///
/// donde:
///
/// - [rssi] es la intensidad de señal recibida;
/// - [txPower] representa el RSSI de referencia asumido a 1 metro;
/// - [pathLossExponent] representa la pérdida de señal del entorno.
///
/// IMPORTANTE:
///
/// El Tx Power anunciado por un dispositivo BLE NO se utiliza directamente
/// como RSSI calibrado a 1 metro.
///
/// Algunos dispositivos anuncian Tx Power y otros no, y ese valor describe
/// la potencia de transmisión del dispositivo. No necesariamente equivale
/// al RSSI que nuestro teléfono debería recibir a exactamente 1 metro.
///
/// Utilizarlo directamente como measuredPower puede producir estimaciones
/// extremadamente incorrectas entre dispositivos diferentes.
///
/// Por esa razón Nodos App utiliza una referencia común configurada en
/// [app_config.dart].
///
/// La distancia obtenida debe interpretarse exclusivamente como una
/// estimación orientativa.
///
/// Para RSSI inválido (>= 0) devuelve [double.infinity].
double rssiToDistance(int rssi, {int? txPowerLevel}) {
  if (rssi >= 0) {
    return double.infinity;
  }

  // No utilizamos txPowerLevel como measuredPower@1m.
  //
  // Se conserva el parámetro temporalmente para mantener compatibilidad
  // con los callers existentes mientras estabilizamos el pipeline BLE.
  final effectiveTxPower = txPower;

  final exponent = (effectiveTxPower - rssi) / (10.0 * pathLossExponent);

  final distance = pow(10.0, exponent).toDouble();

  // Protección ante cualquier resultado matemáticamente inválido.
  if (!distance.isFinite || distance.isNaN || distance < 0) {
    return double.infinity;
  }

  return distance;
}

/// Clasifica un RSSI BLE en un nivel de proximidad.
///
/// La clasificación depende directamente de RSSI y no de la distancia
/// estimada, porque RSSI → metros tiene un margen de error considerable.
///
/// Rangos actuales:
///
/// - RSSI > -70 dBm          → cerca
/// - RSSI entre -70 y -85    → media
/// - RSSI < -85 dBm          → lejos
/// - RSSI >= 0               → lejos / lectura inválida
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
