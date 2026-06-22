/// Contrato del repositorio de conexiones GATT punto a punto.
///
/// QUÉ: define las operaciones de infraestructura necesarias para el
/// ciclo de vida de una conexión BLE: conectar, desconectar, suscribirse
/// al estado, descubrir servicios, leer características y persistir
/// la conexión en la base de datos.
///
/// POR QUÉ: separa la lógica de presentación ([BleConnectionBloc]) de
/// los detalles de infraestructura (FlutterBluePlus GATT, Drift).
/// El BLoC depende de esta abstracción en lugar de depender directamente
/// de [BleGattDataSource] y [AppDatabase].
abstract class BleConnectionRepository {
  /// Inicia la conexión GATT al dispositivo identificado por [remoteId].
  Future<void> connect(String remoteId);

  /// Cierra la conexión GATT al dispositivo identificado por [remoteId].
  Future<void> disconnect(String remoteId);

  /// Stream que emite `true` cuando la conexión está establecida
  /// y `false` cuando se pierde.
  Stream<bool> connectionState(String remoteId);

  /// Descubre los servicios GATT del dispositivo conectado.
  Future<void> discoverServices(String remoteId);

  /// Lee una característica GATT del dispositivo conectado.
  /// Retorna los bytes leídos o null si no está disponible.
  Future<List<int>?> readCharacteristic(
      String remoteId, String characteristicUuid);

  /// Inserta una fila en la tabla connections (R5.2).
  /// Usa insertOrIgnore para evitar duplicados.
  Future<void> saveConnection(int fromNodeId, int toNodeId);
}
