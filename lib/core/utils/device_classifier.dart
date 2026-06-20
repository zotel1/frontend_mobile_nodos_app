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
  static const Map<String, String> _serviceUuidMap = {
    '180d': 'Reloj/Fitness', // Heart Rate
    '180f': 'Batería', // Battery Service
    '1812': 'Teclado', // Human Interface Device (Keyboard)
    '180a': 'Dispositivo', // Device Information
    '1800': 'Genérico', // Generic Access
  };

  /// Mapa de manufacturer company ID → marca.
  ///
  /// Fuente: Bluetooth SIG Company Identifiers.
  static const Map<int, String> _manufacturerMap = {
    0x004C: 'Apple',
    0x0075: 'Samsung',
    0x00E0: 'Google',
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

  /// Intenta hacer match de un GUID de servicio BLE contra el mapa conocido.
  ///
  /// Extrae los 4 caracteres del código de 16 bits desde el GUID completo
  /// (posiciones 4-7 del string "0000XXXX-...") y los compara contra
  /// [_serviceUuidMap].
  static String? _matchServiceUuid(String uuid) {
    // El GUID de 16 bits tiene formato: 0000XXXX-0000-1000-8000-00805F9B34FB
    // donde XXXX es el código de 16 bits en hexadecimal.
    if (uuid.length >= 8) {
      final shortCode = uuid.substring(4, 8).toLowerCase();
      return _serviceUuidMap[shortCode];
    }
    return null;
  }
}
