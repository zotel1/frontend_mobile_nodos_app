import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_identity.dart';

/// Implementación del periférico BLE de Nodos.
///
/// El advertising permite descubrir que el dispositivo ejecuta Nodos.
///
/// El servicio GATT expone las características del protocolo:
///
/// serviceUuid
///   ├── identityCharacteristicUUID
///   │     └── identidad Nodos local
///   │
///   ├── graphCharacteristicUUID
///   │     └── snapshot del grafo activo local
///   │
///   ├── linkCharacteristicUUID
///   │     ├── WRITE  → solicitud de enlace recibida
///   │     └── NOTIFY → respuesta al enlace
///   │
///   └── peerGraphCharacteristicUUID
///         └── WRITE → snapshot del grafo del peer
///
/// Esta capa solamente transporta bytes.
///
/// No interpreta LinkRequest, LinkResponse ni NodosGraphPayload y tampoco
/// decide si una solicitud debe aceptarse o rechazarse.
class FlutterBlePeripheralDataSource implements BleAdvertiserDataSource {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  final StreamController<BleGattWrite> _incomingLinkRequestsController =
      StreamController<BleGattWrite>.broadcast();

  final StreamController<BleGattWrite> _incomingPeerGraphPayloadsController =
      StreamController<BleGattWrite>.broadcast();

  StreamSubscription<GattSubscription>? _subscription;
  StreamSubscription<GattWrite>? _writeSubscription;

  Uint8List? _identityPayload;
  Uint8List? _graphPayload;

  /// Serializa la identidad Nodos utilizando la entidad oficial
  /// del protocolo.
  @visibleForTesting
  static Uint8List buildIdentityPayload(
    String deviceUuid,
    String name,
    String color,
  ) {
    final identity = NodosIdentity(uuid: deviceUuid, name: name, color: color);

    return Uint8List.fromList(identity.toBytes());
  }

  @override
  Stream<BleGattWrite> get incomingLinkRequests =>
      _incomingLinkRequestsController.stream;

  @override
  Stream<BleGattWrite> get incomingPeerGraphPayloads =>
      _incomingPeerGraphPayloadsController.stream;

  @override
  Future<void> startAdvertise(
    String deviceUuid,
    String name,
    String color,
  ) async {
    _identityPayload = buildIdentityPayload(deviceUuid, name, color);

    await _subscription?.cancel();
    await _writeSubscription?.cancel();

    _subscription = _peripheral.onCharacteristicSubscriptionChanged.listen((
      subscription,
    ) async {
      if (!subscription.subscribed) {
        return;
      }

      final characteristicUuid = subscription.characteristicUuid.toLowerCase();

      if (characteristicUuid == identityCharacteristicUUID.toLowerCase()) {
        final payload = _identityPayload;

        if (payload == null || payload.isEmpty) {
          return;
        }

        try {
          await _peripheral.sendData(
            payload,
            characteristicUuid: identityCharacteristicUUID,
          );
        } catch (error) {
          debugPrint('Nodos GATT: no se pudo enviar la identidad: $error');
        }

        return;
      }

      if (characteristicUuid == graphCharacteristicUUID.toLowerCase()) {
        final payload = _graphPayload;

        if (payload == null || payload.isEmpty) {
          return;
        }

        try {
          await _peripheral.sendData(
            payload,
            characteristicUuid: graphCharacteristicUUID,
          );
        } catch (error) {
          debugPrint('Nodos GATT: no se pudo enviar el grafo: $error');
        }
      }
    });

    // Recibimos escrituras realizadas por centrales conectados al servidor
    // GATT y las clasificamos según la característica destino.
    //
    // Esta capa no interpreta el contenido.
    _writeSubscription = _peripheral.onGattWrite.listen(
      (write) {
        final characteristicUuid = write.characteristicUuid.toLowerCase();

        if (write.data.isEmpty) {
          return;
        }

        if (characteristicUuid == linkCharacteristicUUID.toLowerCase()) {
          _incomingLinkRequestsController.add(
            BleGattWrite(payload: Uint8List.fromList(write.data)),
          );

          return;
        }

        if (characteristicUuid == peerGraphCharacteristicUUID.toLowerCase()) {
          _incomingPeerGraphPayloadsController.add(
            BleGattWrite(payload: Uint8List.fromList(write.data)),
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Nodos GATT: error recibiendo escritura: $error');
      },
    );

    // El advertisement solamente permite descubrir que este dispositivo
    // ofrece el servicio Nodos.
    //
    // La identidad, handshake y grafos se intercambian posteriormente
    // mediante las características GATT.
    const advertiseData = AndroidAdvertiseData(
      serviceUuid: serviceUuid,
      serviceUuids: [serviceUuid],
      includeDeviceName: false,
    );

    // Característica de control del handshake.
    //
    // Debe aceptar escrituras del central y permitir al periférico responder
    // mediante NOTIFY sobre la misma característica.
    const linkCharacteristic = GattCharacteristic(
      uuid: linkCharacteristicUUID,
      properties: {
        GattCharacteristicProperty.read,
        GattCharacteristicProperty.write,
        GattCharacteristicProperty.writeWithoutResponse,
        GattCharacteristicProperty.notify,
        GattCharacteristicProperty.indicate,
      },
    );

    const gattServer = GattServerSettings(
      serviceUuid: serviceUuid,
      characteristics: [
        GattCharacteristic.notify(identityCharacteristicUUID),
        GattCharacteristic.notify(graphCharacteristicUUID),
        linkCharacteristic,
        GattCharacteristic.write(peerGraphCharacteristicUUID),
      ],
    );

    await _peripheral.start(
      advertiseData: advertiseData,
      gattServer: gattServer,
    );
  }

  @override
  Future<void> updateGraphPayload(Uint8List payload) async {
    // Guardamos una copia defensiva para que las capas superiores puedan
    // reutilizar su buffer sin alterar el snapshot publicado.
    _graphPayload = Uint8List.fromList(payload);
  }

  @override
  Future<void> sendLinkResponse(Uint8List payload) async {
    if (payload.isEmpty) {
      return;
    }

    try {
      await _peripheral.sendData(
        Uint8List.fromList(payload),
        characteristicUuid: linkCharacteristicUUID,
      );
    } catch (error) {
      debugPrint(
        'Nodos GATT: no se pudo enviar la respuesta de enlace: $error',
      );
      rethrow;
    }
  }

  @override
  Future<void> stopAdvertise() async {
    await _subscription?.cancel();
    _subscription = null;

    await _writeSubscription?.cancel();
    _writeSubscription = null;

    _identityPayload = null;
    _graphPayload = null;

    await _peripheral.stop();
  }
}
