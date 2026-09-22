/// Contrato del repositorio de conexiones GATT punto a punto.
///
/// QUÉ: define las operaciones de infraestructura necesarias para el
/// ciclo de vida de una conexión BLE: conectar, desconectar, suscribirse
/// al estado, descubrir servicios, leer y escribir características y
/// persistir conexiones locales en la base de datos.
///
/// POR QUÉ: separa la lógica de presentación ([BleConnectionBloc]) de
/// los detalles de infraestructura (FlutterBluePlus GATT, Drift).
///
/// El BLoC depende de esta abstracción en lugar de depender directamente
/// de [BleGattDataSource] y [AppDatabase].
///
/// Esta capa transporta bytes GATT. No interpreta LinkRequest,
/// LinkResponse ni NodosGraphPayload.
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
  ///
  /// Retorna los bytes leídos o null si la característica no está
  /// disponible o no fue posible obtener un valor.
  Future<List<int>?> readCharacteristic(
    String remoteId,
    String characteristicUuid,
  );

  /// Escribe [payload] en una característica GATT del dispositivo conectado.
  ///
  /// Retorna `true` cuando la característica existe y la escritura pudo
  /// realizarse.
  ///
  /// Retorna `false` cuando la característica no existe en el dispositivo
  /// remoto. Esto permite detectar instalaciones Nodos anteriores que todavía
  /// no implementan una característica incorporada en una versión posterior.
  ///
  /// Los errores reales de transporte se propagan al llamador.
  Future<bool> writeCharacteristic(
    String remoteId,
    String characteristicUuid,
    List<int> payload,
  );

  /// Inserta una fila en la tabla connections (R5.2).
  ///
  /// Usa insertOrIgnore para evitar duplicados.
  ///
  /// IMPORTANTE:
  /// Este método representa una relación local persistente. Las relaciones
  /// reportadas dentro de un NodosGraphPayload remoto no deben guardarse aquí.
  Future<void> saveConnection(int fromNodeId, int toNodeId);
}
