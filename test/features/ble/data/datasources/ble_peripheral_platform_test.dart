import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_peripheral_adapter.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_peripheral_platform.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_ble_peripheral_datasource.dart';

void main() {
  group('BlePeripheralPlatformConfigBuilder', () {
    const builder = BlePeripheralPlatformConfigBuilder();

    test('uses the same Nodos service UUID on Android and Darwin', () {
      final android = builder.build(
        platform: BlePeripheralPlatform.android,
        localName: 'Android node',
      );
      final darwin = builder.build(
        platform: BlePeripheralPlatform.darwin,
        localName: 'iPhone node',
      );

      expect(android.advertiseData.serviceUuid, serviceUuid);
      expect(android.advertiseData.serviceUuids, [serviceUuid]);
      expect(darwin.advertiseData.serviceUuid, serviceUuid);
      expect(darwin.advertiseData.serviceUuids, [serviceUuid]);
    });

    test('keeps the same GATT UUIDs and properties for both platforms', () {
      final gatt = FlutterBlePeripheralDataSource.buildGattServer();
      final characteristics = gatt.effectiveCharacteristics;

      expect(gatt.serviceUuid, serviceUuid);
      expect(characteristics, hasLength(4));
      expect(characteristics[0].uuid, identityCharacteristicUUID);
      expect(characteristics[0].canNotify, isTrue);
      expect(characteristics[1].uuid, graphCharacteristicUUID);
      expect(characteristics[1].canNotify, isTrue);
      expect(characteristics[2].uuid, linkCharacteristicUUID);
      expect(characteristics[2].canWrite, isTrue);
      expect(characteristics[2].canNotify, isTrue);
      expect(characteristics[3].uuid, peerGraphCharacteristicUUID);
      expect(characteristics[3].canWrite, isTrue);
    });

    test(
      'selects platform settings without leaking Android fields to Darwin',
      () {
        final android = builder.build(
          platform: BlePeripheralPlatform.android,
          localName: 'Android node',
        );
        final darwin = builder.build(
          platform: BlePeripheralPlatform.darwin,
          localName: 'iPhone node',
        );

        expect(android.androidSettings, isNotNull);
        expect(android.darwinSettings, isNull);
        expect(darwin.androidSettings, isNull);
        expect(darwin.darwinSettings, isNotNull);
        expect(darwin.advertiseData.manufacturerId, isNull);
        expect(darwin.advertiseData.manufacturerData, isNull);
      },
    );

    test('preserves a Darwin local name within the documented limit', () {
      final config = builder.build(
        platform: BlePeripheralPlatform.darwin,
        localName: 'Nodos device longer than ten bytes',
      );

      expect(config.advertiseData.localName, 'Nodos devi');
    });
  });

  group('FlutterBlePeripheralDataSource platform adapter', () {
    late FakeBlePeripheralAdapter adapter;

    setUp(() {
      adapter = FakeBlePeripheralAdapter();
    });

    tearDown(() async {
      await adapter.dispose();
    });

    test(
      'starts with the Darwin configuration and portable GATT layout',
      () async {
        final dataSource = FlutterBlePeripheralDataSource(
          peripheral: adapter,
          platform: BlePeripheralPlatform.darwin,
        );

        await dataSource.startAdvertise('uuid', 'Nodos', '#123456');

        expect(adapter.startCall, isNotNull);
        expect(adapter.startCall!.darwinSettings, isNotNull);
        expect(adapter.startCall!.androidSettings, isNull);
        expect(adapter.startCall!.advertiseData.serviceUuid, serviceUuid);
        expect(
          adapter.startCall!.gattServer.effectiveCharacteristics.map(
            (characteristic) => characteristic.uuid,
          ),
          containsAll(<String>[
            identityCharacteristicUUID,
            graphCharacteristicUUID,
            linkCharacteristicUUID,
            peerGraphCharacteristicUUID,
          ]),
        );
      },
    );

    test(
      'routes incoming writes by characteristic without a MAC assumption',
      () async {
        final dataSource = FlutterBlePeripheralDataSource(
          peripheral: adapter,
          platform: BlePeripheralPlatform.darwin,
        );
        final writes = <BleGattWrite>[];
        final subscription = dataSource.incomingLinkRequests.listen(writes.add);

        await dataSource.startAdvertise('uuid', 'Nodos', '#123456');
        adapter.writes.add(
          GattWrite(
            characteristicUuid: linkCharacteristicUUID,
            data: Uint8List.fromList([1, 2, 3]),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(writes.single.payload, [1, 2, 3]);
        await subscription.cancel();
      },
    );

    test('sends notifications through the portable adapter', () async {
      final dataSource = FlutterBlePeripheralDataSource(
        peripheral: adapter,
        platform: BlePeripheralPlatform.android,
      );

      await dataSource.sendLinkResponse(Uint8List.fromList([7, 8]));

      expect(adapter.sentData.single.data, [7, 8]);
      expect(
        adapter.sentData.single.characteristicUuid,
        linkCharacteristicUUID,
      );
    });

    test('stops advertising through the same portable adapter', () async {
      final dataSource = FlutterBlePeripheralDataSource(
        peripheral: adapter,
        platform: BlePeripheralPlatform.darwin,
      );

      await dataSource.stopAdvertise();

      expect(adapter.stopCalls, 1);
    });

    test('routes subscriptions independently by characteristic', () async {
      final dataSource = FlutterBlePeripheralDataSource(
        peripheral: adapter,
        platform: BlePeripheralPlatform.darwin,
      );

      await dataSource.startAdvertise('uuid', 'Nodos', '#123456');
      await dataSource.updateGraphPayload(Uint8List.fromList([9, 10]));
      adapter.subscriptions.add(
        const GattSubscription(
          characteristicUuid: identityCharacteristicUUID,
          subscribed: true,
        ),
      );
      adapter.subscriptions.add(
        const GattSubscription(
          characteristicUuid: graphCharacteristicUUID,
          subscribed: true,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(
        adapter.sentData.map((sent) => sent.characteristicUuid),
        containsAll(<String>[
          identityCharacteristicUUID,
          graphCharacteristicUUID,
        ]),
      );
    });
  });
}

class FakeBlePeripheralAdapter implements BlePeripheralAdapter {
  final StreamController<GattSubscription> subscriptions =
      StreamController<GattSubscription>.broadcast();
  final StreamController<GattWrite> writes =
      StreamController<GattWrite>.broadcast();
  final List<SentData> sentData = [];
  StartCall? startCall;
  int stopCalls = 0;

  @override
  Stream<GattSubscription> get onCharacteristicSubscriptionChanged =>
      subscriptions.stream;

  @override
  Stream<GattWrite> get onGattWrite => writes.stream;

  @override
  Future<void> start({
    required AdvertiseDataCore advertiseData,
    required GattServerSettings gattServer,
    AndroidAdvertiseSettings? androidSettings,
    DarwinAdvertiseSettings? darwinSettings,
  }) async {
    startCall = StartCall(
      advertiseData: advertiseData,
      gattServer: gattServer,
      androidSettings: androidSettings,
      darwinSettings: darwinSettings,
    );
  }

  @override
  Future<void> sendData(
    Uint8List data, {
    required String characteristicUuid,
  }) async {
    sentData.add(
      SentData(
        data: Uint8List.fromList(data),
        characteristicUuid: characteristicUuid,
      ),
    );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  Future<void> dispose() async {
    await subscriptions.close();
    await writes.close();
  }
}

class StartCall {
  const StartCall({
    required this.advertiseData,
    required this.gattServer,
    required this.androidSettings,
    required this.darwinSettings,
  });

  final AdvertiseDataCore advertiseData;
  final GattServerSettings gattServer;
  final AndroidAdvertiseSettings? androidSettings;
  final DarwinAdvertiseSettings? darwinSettings;
}

class SentData {
  const SentData({required this.data, required this.characteristicUuid});

  final Uint8List data;
  final String characteristicUuid;
}
