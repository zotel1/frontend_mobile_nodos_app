import 'dart:typed_data';

/// Contrato para publicar la instalación local como periférico Nodos.
///
/// La identidad y el grafo tienen ciclos de vida independientes:
///
/// - [startAdvertise] inicia el advertising y publica la identidad.
/// - [updateGraphPayload] actualiza el snapshot del grafo activo sin
///   reiniciar el advertising.
/// - [stopAdvertise] detiene completamente el periférico.
///
/// El datasource solamente transporta bytes.
/// No conoce Nodes, Connections, SQLite ni NodosGraphPayload.
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

  /// Detiene el advertising y el servidor GATT.
  Future<void> stopAdvertise();
}
