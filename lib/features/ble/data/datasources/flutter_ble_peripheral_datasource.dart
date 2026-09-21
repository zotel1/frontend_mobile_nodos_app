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
/// El servicio GATT expone dos características:
///
/// serviceUuid
///   ├── identityCharacteristicUUID
///   │     └── NodosIdentity
///   │
///   └── graphCharacteristicUUID
///         └── último snapshot del grafo activo
///
/// La identidad permanece prácticamente estable durante la sesión.
///
/// El grafo, en cambio, puede actualizarse mientras el advertising continúa
/// activo mediante [updateGraphPayload].
class FlutterBlePeripheralDataSource implements BleAdvertiserDataSource {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  StreamSubscription<GattSubscription>? _subscription;

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
  Future<void> startAdvertise(
    String deviceUuid,
    String name,
    String color,
  ) async {
    _identityPayload = buildIdentityPayload(deviceUuid, name, color);

    await _subscription?.cancel();

    // Escuchamos las suscripciones a las características del servicio Nodos.
    //
    // Cuando un cliente se suscribe:
    //
    // - identityCharacteristicUUID:
    //     enviamos la identidad local.
    //
    // - graphCharacteristicUUID:
    //     enviamos el snapshot de grafo más reciente disponible.
    //
    // El snapshot no se calcula aquí. Esta capa solamente transporta
    // los bytes preparados por las capas superiores.
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

    // El advertisement solamente permite descubrir que este dispositivo
    // ofrece el servicio Nodos.
    //
    // La identidad y el grafo completo se obtienen posteriormente mediante
    // las características GATT.
    const advertiseData = AndroidAdvertiseData(
      serviceUuid: serviceUuid,
      serviceUuids: [serviceUuid],
      includeDeviceName: false,
    );

    // Servicio GATT Nodos.
    //
    // Ambas características utilizan NOTIFY porque el cliente actual se
    // suscribe y espera que el periférico envíe inmediatamente el valor.
    const gattServer = GattServerSettings(
      serviceUuid: serviceUuid,
      characteristics: [
        GattCharacteristic.notify(identityCharacteristicUUID),
        GattCharacteristic.notify(graphCharacteristicUUID),
      ],
    );

    await _peripheral.start(
      advertiseData: advertiseData,
      gattServer: gattServer,
    );
  }

  @override
  Future<void> updateGraphPayload(Uint8List payload) async {
    // Guardamos una copia defensiva.
    //
    // De esta forma las capas superiores pueden reutilizar o modificar
    // su propio buffer sin alterar accidentalmente el snapshot que
    // publicará el servidor GATT.
    _graphPayload = Uint8List.fromList(payload);

    // No enviamos automáticamente el payload en este punto.
    //
    // El contrato actual es request/snapshot:
    //
    // cliente se suscribe
    //        ↓
    // servidor recibe subscription
    //        ↓
    // servidor envía el snapshot vigente
    //
    // Más adelante podemos evolucionar esto a actualizaciones push mientras
    // el cliente permanezca suscrito, pero no es necesario para establecer
    // el primer intercambio funcional de FEAT-002.
  }

  @override
  Future<void> stopAdvertise() async {
    await _subscription?.cancel();
    _subscription = null;

    _identityPayload = null;
    _graphPayload = null;

    await _peripheral.stop();
  }
}
