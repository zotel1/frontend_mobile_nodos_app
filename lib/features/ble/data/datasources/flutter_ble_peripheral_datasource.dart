import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_peripheral_adapter.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_peripheral_platform.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_identity.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/transport/ble_frame_codec.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/transport/ble_mtu_policy.dart';

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
  FlutterBlePeripheralDataSource({
    BlePeripheralAdapter? peripheral,
    BlePeripheralPlatform? platform,
    BlePeripheralPlatformConfigBuilder? configBuilder,
  }) : _peripheral = peripheral ?? FlutterBlePeripheralAdapter(),
       _platform = platform ?? BlePeripheralPlatformDetection.current,
       _configBuilder =
           configBuilder ?? const BlePeripheralPlatformConfigBuilder();

  final BlePeripheralAdapter _peripheral;
  final BlePeripheralPlatform _platform;
  final BlePeripheralPlatformConfigBuilder _configBuilder;

  final StreamController<BleGattWrite> _incomingLinkRequestsController =
      StreamController<BleGattWrite>.broadcast();

  final StreamController<BleGattWrite> _incomingPeerGraphPayloadsController =
      StreamController<BleGattWrite>.broadcast();

  StreamSubscription<GattSubscription>? _subscription;
  StreamSubscription<GattWrite>? _writeSubscription;

  Uint8List? _identityPayload;
  Uint8List? _graphPayload;
  final BleMessageFramer _graphFramer = BleMessageFramer();
  Future<void> _graphSendQueue = Future<void>.value();

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

  /// Builds the platform-neutral Nodos GATT layout.
  @visibleForTesting
  static GattServerSettings buildGattServer() {
    return const GattServerSettings(
      serviceUuid: serviceUuid,
      characteristics: [
        GattCharacteristic.notify(identityCharacteristicUUID),
        GattCharacteristic.notify(graphCharacteristicUUID),
        GattCharacteristic(
          uuid: linkCharacteristicUUID,
          properties: {
            GattCharacteristicProperty.read,
            GattCharacteristicProperty.write,
            GattCharacteristicProperty.writeWithoutResponse,
            GattCharacteristicProperty.notify,
            GattCharacteristicProperty.indicate,
          },
        ),
        GattCharacteristic.write(peerGraphCharacteristicUUID),
      ],
    );
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

        _enqueueGraphSend(payload);
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
    final platformConfig = _configBuilder.build(
      platform: _platform,
      localName: name,
    );

    await _peripheral.start(
      advertiseData: platformConfig.advertiseData,
      gattServer: buildGattServer(),
      androidSettings: platformConfig.androidSettings,
      darwinSettings: platformConfig.darwinSettings,
    );
  }

  @override
  Future<void> updateGraphPayload(Uint8List payload) async {
    // Guardamos una copia defensiva para que las capas superiores puedan
    // reutilizar su buffer sin alterar el snapshot publicado.
    _graphPayload = Uint8List.fromList(payload);
  }

  void _enqueueGraphSend(Uint8List payload) {
    final next = _graphSendQueue.then<void>(
      (_) => _sendGraphFrames(payload),
      onError: (Object error, StackTrace stackTrace) =>
          _sendGraphFrames(payload),
    );
    _graphSendQueue = next.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Nodos GATT: no se pudo enviar el grafo: $error');
    });
  }

  Future<void> _sendGraphFrames(Uint8List payload) async {
    try {
      final frames = _graphFramer.frame(
        payload,
        chunkPayloadSize: BleMtuPolicy.peripheralNotificationCapacity(),
      );
      for (final frame in frames) {
        await _peripheral.sendData(
          frame,
          characteristicUuid: graphCharacteristicUUID,
        );
      }
    } catch (error) {
      debugPrint('Nodos GATT: no se pudo enviar el grafo: $error');
    }
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
    _graphSendQueue = Future<void>.value();

    await _peripheral.stop();
  }
}
