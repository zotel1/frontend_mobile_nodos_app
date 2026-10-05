import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

abstract class BlePeripheralAdapter {
  Stream<GattSubscription> get onCharacteristicSubscriptionChanged;
  Stream<GattWrite> get onGattWrite;

  Future<void> start({
    required AdvertiseDataCore advertiseData,
    required GattServerSettings gattServer,
    AndroidAdvertiseSettings? androidSettings,
    DarwinAdvertiseSettings? darwinSettings,
  });

  Future<void> sendData(Uint8List data, {required String characteristicUuid});

  Future<void> stop();
}

class FlutterBlePeripheralAdapter implements BlePeripheralAdapter {
  FlutterBlePeripheralAdapter([FlutterBlePeripheral? peripheral])
    : _peripheral = peripheral ?? FlutterBlePeripheral();

  final FlutterBlePeripheral _peripheral;

  @override
  Stream<GattSubscription> get onCharacteristicSubscriptionChanged =>
      _peripheral.onCharacteristicSubscriptionChanged;

  @override
  Stream<GattWrite> get onGattWrite => _peripheral.onGattWrite;

  @override
  Future<void> start({
    required AdvertiseDataCore advertiseData,
    required GattServerSettings gattServer,
    AndroidAdvertiseSettings? androidSettings,
    DarwinAdvertiseSettings? darwinSettings,
  }) async {
    await _peripheral.start(
      advertiseData: advertiseData,
      gattServer: gattServer,
      androidSettings: androidSettings,
      darwinSettings: darwinSettings,
    );
  }

  @override
  Future<void> sendData(Uint8List data, {required String characteristicUuid}) {
    return _peripheral.sendData(data, characteristicUuid: characteristicUuid);
  }

  @override
  Future<void> stop() => _peripheral.stop();
}
