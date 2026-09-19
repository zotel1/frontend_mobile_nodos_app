import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';

/// Implementación del periférico BLE de Nodos.
///
/// El advertising permite descubrir que el dispositivo ejecuta Nodos.
/// La identidad estable se publica mediante una característica GATT.
///
/// serviceUuid
///   └── identityCharacteristicUUID
///         └── { uuid, name, color }
class FlutterBlePeripheralDataSource implements BleAdvertiserDataSource {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  StreamSubscription<GattSubscription>? _identitySubscription;

  Uint8List? _identityPayload;

  /// Serializa la identidad Nodos como JSON UTF-8.
  @visibleForTesting
  static Uint8List buildIdentityPayload(
    String deviceUuid,
    String name,
    String color,
  ) {
    final identityJson = jsonEncode({
      'uuid': deviceUuid,
      'name': name,
      'color': color,
    });

    return Uint8List.fromList(utf8.encode(identityJson));
  }

  @override
  Future<void> startAdvertise(
    String deviceUuid,
    String name,
    String color,
  ) async {
    _identityPayload = buildIdentityPayload(deviceUuid, name, color);

    await _identitySubscription?.cancel();

    // Escuchamos específicamente las suscripciones a la característica
    // de identidad. Cuando otro dispositivo Nodos se suscribe, publicamos
    // inmediatamente la identidad local.
    _identitySubscription = _peripheral.onCharacteristicSubscriptionChanged
        .listen((subscription) async {
          if (!subscription.subscribed ||
              subscription.characteristicUuid.toLowerCase() !=
                  identityCharacteristicUUID.toLowerCase()) {
            return;
          }

          final payload = _identityPayload;
          if (payload == null) return;

          try {
            await _peripheral.sendData(
              payload,
              characteristicUuid: identityCharacteristicUUID,
            );
          } catch (error) {
            debugPrint('Nodos GATT: no se pudo enviar la identidad: $error');
          }
        });

    // El advertisement solamente identifica al dispositivo como Nodos.
    // La identidad completa se obtiene posteriormente mediante GATT.
    const advertiseData = AndroidAdvertiseData(
      serviceUuid: serviceUuid,
      serviceUuids: [serviceUuid],
      includeDeviceName: false,
    );

    // Una única característica de identidad.
    //
    // GattCharacteristic.notify habilita READ + NOTIFY + INDICATE.
    const gattServer = GattServerSettings(
      serviceUuid: serviceUuid,
      characteristics: [GattCharacteristic.notify(identityCharacteristicUUID)],
    );

    await _peripheral.start(
      advertiseData: advertiseData,
      gattServer: gattServer,
    );
  }

  @override
  Future<void> stopAdvertise() async {
    await _identitySubscription?.cancel();
    _identitySubscription = null;
    _identityPayload = null;

    await _peripheral.stop();
  }
}
