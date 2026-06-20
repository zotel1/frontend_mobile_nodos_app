/// Interfaz de abstracción para operaciones GATT (conexión punto a punto).
///
/// QUÉ hace: define el contrato para conectar, desconectar y monitorear
/// el estado de conexión de un dispositivo BLE individual.
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
}
