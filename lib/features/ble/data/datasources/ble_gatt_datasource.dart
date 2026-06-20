/// Información de un servicio GATT descubierto en un dispositivo remoto.
///
/// Modelo de datos que abstrae la representación de flutter_blue_plus
/// para no acoplar la capa de dominio a la biblioteca BLE.
class BleServiceInfo {
  /// UUID del servicio GATT (ej. "4fafc201-1fb5-459e-8fcc-c5c9c331914b").
  final String uuid;

  /// UUIDs de las características dentro de este servicio.
  final List<String> characteristicUuids;

  const BleServiceInfo({
    required this.uuid,
    required this.characteristicUuids,
  });
}

/// Interfaz de abstracción para operaciones GATT (conexión punto a punto).
///
/// QUÉ hace: define el contrato para conectar, desconectar, monitorear
/// el estado de conexión, descubrir servicios y leer características
/// de un dispositivo BLE individual.
///
/// POR QUÉ: separa la capa de datos de la implementación concreta de
/// flutter_blue_plus, permitiendo testear el BLoC con mocks y cambiar
/// la implementación sin afectar al resto de la app.
abstract class BleGattDataSource {
  /// Conecta al dispositivo identificado por [remoteId].
  ///
  /// Timeout: 10 segundos. Usa [License.nonprofit].
  Future<void> connect(String remoteId);

  /// Desconecta del dispositivo identificado por [remoteId].
  Future<void> disconnect(String remoteId);

  /// Verifica si el dispositivo identificado por [remoteId] está conectado.
  Future<bool> isConnected(String remoteId);

  /// Stream del estado de conexión del dispositivo identificado por [remoteId].
  ///
  /// Emite `true` cuando está conectado, `false` cuando se desconecta.
  Stream<bool> connectionState(String remoteId);

  /// Descubre los servicios GATT del dispositivo identificado por [remoteId].
  ///
  /// Retorna una lista de [BleServiceInfo] con los UUIDs de servicios
  /// y sus características. Requiere que el dispositivo esté conectado.
  /// Usado para leer la característica de identidad remota (AD12).
  Future<List<BleServiceInfo>> discoverServices(String remoteId);

  /// Lee el valor de la característica [characteristicUuid] del dispositivo
  /// identificado por [remoteId].
  ///
  /// Retorna los bytes crudos de la característica, o null si la
  /// característica no existe en los servicios descubiertos.
  /// Requiere que [discoverServices] se haya llamado primero.
  Future<List<int>?> readCharacteristic(
      String remoteId, String characteristicUuid);
}
