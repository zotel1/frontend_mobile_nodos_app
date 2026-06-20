import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';

/// Implementación real de advertising BLE usando [FlutterBlePeripheral].
///
/// QUÉ hace: inicia/detiene el advertising periférico con los metadatos
/// de identidad del dispositivo (UUID, nombre, color) para que otros
/// dispositivos Nodos puedan detectarlo vía escaneo BLE.
///
/// POR QUÉ: reemplaza el stub anterior con llamadas reales al hardware
/// BLE vía flutter_ble_peripheral. El advertising anuncia el service UUID
/// Nodos y el manufacturer data con la identidad serializada como JSON.
class FlutterBlePeripheralDataSource implements BleAdvertiserDataSource {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  @override
  Future<void> startAdvertise(
      String deviceUuid, String name, String color) async {
    /// JSON con metadatos de identidad: uuid, name, color.
    final identityJson = jsonEncode({
      'uuid': deviceUuid,
      'name': name,
      'color': color,
    });

    final advertiseData = AdvertiseData(
      serviceUuids: [serviceUuid],
      manufacturerId: 0x004C, // Apple como placeholder para manufacturer
      manufacturerData: Uint8List.fromList(utf8.encode(identityJson)),
      includeDeviceName: false,
      localName: name,
    );

    await _peripheral.start(advertiseData: advertiseData);
  }

  @override
  Future<void> stopAdvertise() async {
    await _peripheral.stop();
  }
}
