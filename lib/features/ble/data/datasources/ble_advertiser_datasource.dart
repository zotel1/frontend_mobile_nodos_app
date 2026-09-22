import 'dart:typed_data';

/// Escritura recibida por el servidor GATT Nodos.
///
/// El datasource mantiene este objeto deliberadamente agnóstico respecto
/// del protocolo de dominio.
///
/// Las capas superiores son responsables de interpretar [payload] como un
/// LinkRequest, NodosGraphPayload u otro mensaje versionado.
class BleGattWrite {
  const BleGattWrite({required this.payload});

  /// Bytes recibidos mediante la característica GATT correspondiente.
  final Uint8List payload;
}

/// Contrato para publicar la instalación local como periférico Nodos.
///
/// La identidad, el grafo y el handshake tienen ciclos de vida independientes:
///
/// - [startAdvertise] inicia el advertising y publica la identidad.
/// - [updateGraphPayload] actualiza el snapshot del grafo activo sin
///   reiniciar el advertising.
/// - [incomingLinkRequests] expone escrituras recibidas en la característica
///   de control de enlace.
/// - [sendLinkResponse] envía al central la respuesta al handshake.
/// - [incomingPeerGraphPayloads] expone snapshots enviados por el central.
/// - [stopAdvertise] detiene completamente el periférico.
///
/// El datasource solamente transporta bytes.
/// No conoce Nodes, Connections, SQLite, NodosGraphPayload ni las decisiones
/// de aceptar o rechazar una solicitud.
abstract class BleAdvertiserDataSource {
  /// Inicia el advertising BLE con los metadatos de identidad del dispositivo.
  ///
  /// [deviceUuid] — UUID estable de la instalación local.
  /// [name] — nombre configurado por el usuario.
  /// [color] — color del usuario en hexadecimal.
  Future<void> startAdvertise(String deviceUuid, String name, String color);

  /// Reemplaza el snapshot de grafo que se publicará mediante GATT.
  ///
  /// [payload] debe contener un NodosGraphPayload serializado.
  ///
  /// El payload representa únicamente las relaciones que la instalación
  /// considera activas en ese momento.
  ///
  /// Este método NO reinicia el advertising ni modifica la identidad.
  Future<void> updateGraphPayload(Uint8List payload);

  /// Solicitudes de enlace recibidas desde un central Nodos.
  ///
  /// Cada evento corresponde a una escritura realizada sobre
  /// linkCharacteristicUUID.
  ///
  /// El datasource no interpreta el contenido del mensaje.
  Stream<BleGattWrite> get incomingLinkRequests;

  /// Envía al central la respuesta correspondiente al handshake de enlace.
  ///
  /// [payload] será construido por las capas superiores y contendrá el
  /// LinkResponse versionado.
  Future<void> sendLinkResponse(Uint8List payload);

  /// Snapshots de grafo enviados por el central conectado.
  ///
  /// Cada evento corresponde a una escritura realizada sobre
  /// peerGraphCharacteristicUUID.
  ///
  /// El datasource no interpreta ni persiste el snapshot.
  Stream<BleGattWrite> get incomingPeerGraphPayloads;

  /// Detiene el advertising y el servidor GATT.
  Future<void> stopAdvertise();
}
