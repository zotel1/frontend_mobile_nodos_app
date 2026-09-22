/// Contrato del repositorio de conexiones GATT punto a punto.
///
/// QUÉ: define las operaciones de infraestructura necesarias para el
/// ciclo de vida de una conexión BLE: conectar, desconectar, suscribirse
/// al estado, descubrir servicios, leer y escribir características,
/// realizar intercambios request/response y persistir conexiones locales
/// en la base de datos.
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

  /// Escribe una solicitud y espera una respuesta sobre la misma
  /// característica GATT.
  ///
  /// La implementación debe preparar primero la escucha de
  /// NOTIFY/INDICATE y recién después escribir [requestPayload].
  ///
  /// Esto evita perder una respuesta que llegue inmediatamente después
  /// de la escritura.
  ///
  /// Retorna los bytes crudos de la respuesta.
  ///
  /// Retorna `null` cuando [characteristicUuid] no existe en el dispositivo
  /// remoto.
  ///
  /// Si la característica existe pero no soporta las operaciones necesarias,
  /// o si ocurre un fallo real de transporte, el error se propaga al llamador.
  ///
  /// [timeout] representa el tiempo máximo que se esperará la respuesta.
  ///
  /// El repositorio no interpreta el contenido de la solicitud ni de la
  /// respuesta.
  Future<List<int>?> writeAndWaitForResponse(
    String remoteId,
    String characteristicUuid,
    List<int> requestPayload, {
    Duration timeout = const Duration(seconds: 30),
  });

  /// Inserta una fila en la tabla connections (R5.2).
  ///
  /// Usa insertOrIgnore para evitar duplicados.
  ///
  /// IMPORTANTE:
  /// Este método representa una relación local persistente. Las relaciones
  /// reportadas dentro de un NodosGraphPayload remoto no deben guardarse aquí.
  Future<void> saveConnection(int fromNodeId, int toNodeId);
}
