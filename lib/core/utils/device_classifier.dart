import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';

/// Clasificador estático de dispositivos BLE por service UUIDs y manufacturer ID.
///
/// QUÉ hace: analiza los UUIDs de servicio y el manufacturer ID anunciados
/// por un dispositivo BLE y devuelve una categoría legible (ej: "Reloj/Fitness",
/// "Nodo", "Apple (Desconocido)").
///
/// POR QUÉ es estático: 0 estado, 0 dependencias externas, puramente funcional.
/// Esto permite testearlo sin mocks y usarlo en cualquier capa sin DI.
///
/// Lógica de prioridad:
/// 1. Si contiene el Nodos service UUID → "Nodo" (máxima prioridad, R3.3)
/// 2. Si contiene un service UUID conocido → categoría del primer match
///    (orden: Heart Rate > Battery > Keyboard > Device Info > Generic)
/// 3. Si solo tiene manufacturer ID → "{marca} (Desconocido)"
/// 4. Si no hay nada reconocible → null
class DeviceClassifier {
  DeviceClassifier._(); // Clase estática, no instanciable

  /// Mapa de prefijos de UUID de servicio → categoría.
  ///
  /// Los UUIDs BLE de 16 bits se representan como GUID completo:
  /// 0000XXXX-0000-1000-8000-00805F9B34FB donde XXXX es el código de 16 bits.
  /// Este mapa usa solo el código de 16 bits en minúscula como clave.
  ///
  /// PR9: Expandido con Cycling Speed and Cadence (1816), Health Thermometer (1809),
  /// Blood Pressure (1810). Fuente: Bluetooth SIG Assigned Numbers.
  static const Map<String, String> _serviceUuidMap = {
    '180d': 'Reloj/Fitness', // Heart Rate
    '180f': 'Batería', // Battery Service
    '1812': 'Teclado', // Human Interface Device (Keyboard)
    '180a': 'Dispositivo', // Device Information
    '1800': 'Genérico', // Generic Access
    '1816': 'Ciclismo', // Cycling Speed and Cadence
    '1809': 'Termómetro', // Health Thermometer
    '1810': 'Presión Arterial', // Blood Pressure
  };

  /// Mapa de manufacturer company ID → marca.
  ///
  /// Fuente: Bluetooth SIG Company Identifiers.
  ///
  /// PR9: Expandido con Fitbit (0x026A), Microsoft (0x0006),
  /// Huawei (0x012D).
  static const Map<int, String> _manufacturerMap = {
    0x004C: 'Apple',
    0x0075: 'Samsung',
    0x00E0: 'Google',
    0x026A: 'Fitbit',
    0x0006: 'Microsoft',
    0x012D: 'Huawei',
  };

  /// Clasifica un dispositivo BLE a partir de sus service UUIDs y manufacturer ID.
  ///
  /// [serviceUuids] — lista de UUIDs de servicio en formato GUID string
  ///   (ej: "0000180d-0000-1000-8000-00805f9b34fb").
  /// [manufacturerId] — company ID del fabricante (ej: 0x004C para Apple).
  ///
  /// Retorna la categoría como String, o null si no se puede clasificar.
  static String? classify(List<String> serviceUuids, int? manufacturerId) {
    // 1. Prioridad máxima: Nodos UUID (R3.3)
    for (final uuid in serviceUuids) {
      if (uuid == serviceUuid) return 'Nodo';
    }

    // 2. Buscar service UUID conocido (primer match gana)
    for (final uuid in serviceUuids) {
      final category = _matchServiceUuid(uuid);
      if (category != null) return category;
    }

    // 3. Fallback: manufacturer ID → marca
    if (manufacturerId != null) {
      final brand = _manufacturerMap[manufacturerId];
      if (brand != null) return '$brand (Desconocido)';
    }

    // 4. Nada reconocible
    return null;
  }

  /// Intenta hacer match de un service UUID contra el mapa conocido.
  ///
  /// Soporta dos formatos:
  /// 1. GUID completo: "0000180d-0000-1000-8000-00805F9B34FB"
  ///    Extrae posiciones 4-7 (código de 16 bits).
  /// 2. Código corto: "180d" (como lo retorna flutter_blue_plus).
  ///    Usa directamente el string.
  static String? _matchServiceUuid(String uuid) {
    // Formato GUID completo: 0000XXXX-0000-1000-8000-00805F9B34FB
    if (uuid.length >= 8 && uuid[4] != '-') {
      final shortCode = uuid.substring(4, 8).toLowerCase();
      return _serviceUuidMap[shortCode];
    }
    // Formato corto: directamente el código de 16 bits (ej: "180d")
    return _serviceUuidMap[uuid.toLowerCase()];
  }
}
