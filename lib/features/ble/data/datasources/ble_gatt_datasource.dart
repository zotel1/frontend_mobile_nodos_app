/// Información de un servicio GATT descubierto en un dispositivo remoto.
///
/// Modelo de datos que abstrae la representación de flutter_blue_plus
/// para no acoplar la capa de dominio a la biblioteca BLE.
class BleServiceInfo {
  /// UUID del servicio GATT
  /// (ej. "4fafc201-1fb5-459e-8fcc-c5c9c331914b").
  final String uuid;

  /// UUIDs de las características dentro de este servicio.
  final List<String> characteristicUuids;

  const BleServiceInfo({required this.uuid, required this.characteristicUuids});
}

/// Interfaz de abstracción para operaciones GATT (conexión punto a punto).
///
/// QUÉ hace: define el contrato para conectar, desconectar, monitorear
/// el estado de conexión, descubrir servicios, leer características,
/// escribir características y realizar intercambios request/response
/// sobre GATT.
///
/// POR QUÉ: separa la capa de datos de la implementación concreta de
/// flutter_blue_plus, permitiendo testear el BLoC con mocks y cambiar
/// la implementación sin afectar al resto de la app.
///
/// Esta capa solamente transporta bytes. No interpreta mensajes del
/// protocolo Nodos.
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
  /// y sus características.
  ///
  /// Requiere que el dispositivo esté conectado.
  Future<List<BleServiceInfo>> discoverServices(String remoteId);

  /// Lee el valor de la característica [characteristicUuid] del dispositivo
  /// identificado por [remoteId].
  ///
  /// Retorna los bytes crudos de la característica, o null si la
  /// característica no existe en los servicios descubiertos.
  ///
  /// Requiere que [discoverServices] se haya llamado primero.
  Future<List<int>?> readCharacteristic(
    String remoteId,
    String characteristicUuid,
  );

  /// Escribe [payload] en la característica [characteristicUuid] del
  /// dispositivo identificado por [remoteId].
  ///
  /// Retorna `true` cuando la característica existe y la escritura pudo
  /// realizarse.
  ///
  /// Retorna `false` cuando la característica solicitada no existe entre
  /// los servicios GATT descubiertos.
  ///
  /// Los errores reales de transporte BLE se propagan al llamador.
  ///
  /// Requiere que [discoverServices] se haya llamado primero.
  Future<bool> writeCharacteristic(
    String remoteId,
    String characteristicUuid,
    List<int> payload,
  );

  /// Escribe una solicitud y espera una respuesta mediante la misma
  /// característica GATT.
  ///
  /// El orden de la operación es importante:
  ///
  /// 1. localiza [characteristicUuid];
  /// 2. habilita NOTIFY/INDICATE;
  /// 3. deja preparada la escucha de la respuesta;
  /// 4. escribe [requestPayload];
  /// 5. espera el primer payload de respuesta no vacío;
  /// 6. deshabilita NOTIFY/INDICATE antes de finalizar.
  ///
  /// De esta forma se evita la carrera que ocurriría si primero se
  /// escribiera la solicitud y recién después se comenzara a escuchar
  /// la respuesta.
  ///
  /// Retorna los bytes crudos de la respuesta.
  ///
  /// Retorna `null` si [characteristicUuid] no existe.
  ///
  /// Si la característica existe pero no soporta escritura o
  /// notificaciones/indicaciones, la implementación debe lanzar un error.
  ///
  /// Si no se recibe una respuesta dentro de [timeout], la operación
  /// debe lanzar [TimeoutException].
  ///
  /// Esta capa no interpreta el contenido de la solicitud ni de la
  /// respuesta. El protocolo Nodos pertenece a capas superiores.
  Future<List<int>?> writeAndWaitForResponse(
    String remoteId,
    String characteristicUuid,
    List<int> requestPayload, {
    Duration timeout = const Duration(seconds: 30),
  });
}
