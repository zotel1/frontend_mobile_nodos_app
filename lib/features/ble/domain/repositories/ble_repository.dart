import 'dart:typed_data';

import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

/// Escritura GATT recibida por el peripheral Nodos.
///
/// La capa de dominio recibe únicamente el payload crudo.
/// La interpretación del protocolo corresponde a capas superiores.
class BleIncomingGattWrite {
  const BleIncomingGattWrite({required this.payload});

  final Uint8List payload;
}

abstract class BleRepository {
  Stream<List<BleDevice>> get scanResults;

  Future<void> startScan();

  Future<void> stopScan();

  /// Inicia el advertising y el servidor GATT de Nodos.
  ///
  /// [deviceUuid] identifica de forma estable esta instalación.
  /// [name] y [color] forman parte de la identidad pública de Nodos.
  Future<void> startAdvertise(String deviceUuid, String name, String color);

  /// Actualiza el snapshot del grafo activo publicado mediante GATT.
  ///
  /// El payload debe contener un NodosGraphPayload ya serializado.
  ///
  /// Este método solamente transporta los bytes hacia la capa de datos.
  /// No determina qué conexiones están activas ni consulta SQLite.
  ///
  /// Actualizar el grafo no debe reiniciar el advertising.
  Future<void> updateGraphPayload(Uint8List payload);

  /// Solicitudes de enlace recibidas mediante la característica GATT
  /// linkCharacteristicUUID.
  ///
  /// El payload todavía no fue interpretado como NodosLinkRequest.
  Stream<BleIncomingGattWrite> get incomingLinkRequests;

  /// Envía una respuesta al central actualmente suscripto a la
  /// característica de control de enlace.
  ///
  /// El payload debe contener un NodosLinkResponse ya serializado.
  Future<void> sendLinkResponse(Uint8List payload);

  /// Snapshots de grafo enviados hacia esta instalación por un peer Nodos.
  ///
  /// Estos mensajes llegan mediante peerGraphCharacteristicUUID.
  ///
  /// El payload todavía no fue interpretado como NodosGraphPayload.
  Stream<BleIncomingGattWrite> get incomingPeerGraphPayloads;

  /// Detiene el advertising y el servidor GATT.
  Future<void> stopAdvertise();

  Stream<bool> get bluetoothState;

  /// Cierra la sesión de escaneo activa estableciendo [endedAt].
  ///
  /// QUÉ hace: finaliza el ciclo de vida de la sesión de escaneo
  /// cuando el usuario detiene el scan o BT se apaga.
  ///
  /// POR QUÉ: sin este método las sesiones quedan con endedAt=null
  /// permanentemente, distorsionando estadísticas de historial.
  Future<void> endScanSession();
}
