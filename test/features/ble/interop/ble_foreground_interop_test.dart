import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_peripheral_platform.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_ble_peripheral_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_identity.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_link_request.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_link_response.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/graph_exchange_session_manager.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/transport/ble_frame_codec.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/transport/ble_message_reassembler.dart';

void main() {
  for (final scenario
      in <
        ({
          String name,
          BlePeripheralPlatform central,
          BlePeripheralPlatform peripheral,
          String centralTransportId,
        })
      >[
        (
          name: 'Android central discovers Darwin peripheral',
          central: BlePeripheralPlatform.android,
          peripheral: BlePeripheralPlatform.darwin,
          centralTransportId: 'android-opaque-transport-id',
        ),
        (
          name: 'Darwin central discovers Android peripheral',
          central: BlePeripheralPlatform.darwin,
          peripheral: BlePeripheralPlatform.android,
          centralTransportId: '6A7B0E4D-1234-4EAB-9ABC-1234567890AB',
        ),
      ]) {
    test('$scenario.name: foreground BLE contract', () async {
      final peripheralIdentity = const NodosIdentity(
        uuid: 'peripheral-device-uuid',
        name: 'Nodo Ñandú 東京',
        color: '#123456',
      );
      final peripheral = _InteropPeripheral(
        platform: scenario.peripheral,
        identity: peripheralIdentity,
      );
      final central = _InteropCentral(
        platform: scenario.central,
        transportId: scenario.centralTransportId,
        peripheral: peripheral,
      );

      peripheral.startAdvertising();
      expect(central.discover(serviceUuid), isTrue);
      expect(central.readIdentity(), peripheralIdentity);

      final linkResponse = await central.link(
        const NodosLinkRequest(
          deviceUuid: 'central-device-uuid',
          name: 'Central Á',
          color: '#abcdef',
        ),
      );
      expect(linkResponse.accepted, isTrue);
      expect(peripheral.events.sublist(peripheral.events.length - 3), [
        'subscribe:$linkCharacteristicUUID',
        'write:$linkCharacteristicUUID',
        'response:$linkCharacteristicUUID',
      ]);

      final manager = GraphExchangeSessionManager();
      manager.activate(peripheralIdentity.uuid, remoteId: central.transportId);
      expect(manager.isAuthorized(peripheralIdentity.uuid), isTrue);

      final centralGraph = _graphPayload('central-device-uuid');
      final centralFrames = BleMessageFramer().frame(
        centralGraph.toBytes(),
        mtu: 23,
      );
      for (final frame in centralFrames) {
        await central.writePeerGraph(frame);
      }
      expect(peripheral.receivedPeerGraph, centralGraph.toBytes());

      final peripheralGraph = _graphPayload(peripheralIdentity.uuid);
      final centralReassembler = BleMessageReassembler(scheduleCleanup: false);
      Uint8List? reassembled;
      central.subscribeGraph(
        (bytes) => reassembled = centralReassembler.add(bytes),
      );
      for (final frame in BleMessageFramer().frame(
        peripheralGraph.toBytes(),
        mtu: 23,
      )) {
        peripheral.notifyGraph(frame);
      }
      expect(reassembled, peripheralGraph.toBytes());

      final previousNodeKey = peripheralIdentity.uuid;
      final newTransportId = '${scenario.centralTransportId}-reconnected';
      manager.activate(previousNodeKey, remoteId: newTransportId);
      expect(manager.byPeerUuid(previousNodeKey)!.remoteId, newTransportId);
      expect(<String>{previousNodeKey}, hasLength(1));

      manager.invalidateByRemoteId(newTransportId);
      expect(manager.isAuthorized(previousNodeKey), isFalse);
      expect(peripheral.persistentLinked, isTrue);
    });
  }

  test(
    'foreground harness exposes the same UUID and characteristic contract',
    () {
      final builder = const BlePeripheralPlatformConfigBuilder();
      final android = builder.build(
        platform: BlePeripheralPlatform.android,
        localName: 'Android',
      );
      final darwin = builder.build(
        platform: BlePeripheralPlatform.darwin,
        localName: 'iPhone',
      );
      final gatt = FlutterBlePeripheralDataSource.buildGattServer();

      expect(android.advertiseData.serviceUuid, serviceUuid);
      expect(darwin.advertiseData.serviceUuid, serviceUuid);
      expect(gatt.serviceUuid, serviceUuid);
      expect(
        gatt.effectiveCharacteristics.map(
          (characteristic) => characteristic.uuid,
        ),
        [
          identityCharacteristicUUID,
          graphCharacteristicUUID,
          linkCharacteristicUUID,
          peerGraphCharacteristicUUID,
        ],
      );
    },
  );
}

NodosGraphPayload _graphPayload(String ownerUuid) {
  return NodosGraphPayload(
    ownerUuid: ownerUuid,
    connections: [
      NodosGraphConnection.nodos(
        deviceUuid: 'peer-uuid',
        name: 'Peer Ñ',
        color: '#abcdef',
      ),
    ],
  );
}

class _InteropPeripheral {
  _InteropPeripheral({required this.platform, required this.identity});

  final BlePeripheralPlatform platform;
  final NodosIdentity identity;
  final events = <String>[];
  final _subscriptions = <String, void Function(Uint8List)>{};
  final _reassembler = BleMessageReassembler(scheduleCleanup: false);
  Uint8List? receivedPeerGraph;
  bool persistentLinked = false;

  void startAdvertising() {
    final config = const BlePeripheralPlatformConfigBuilder().build(
      platform: platform,
      localName: identity.name,
    );
    if (config.advertiseData.serviceUuid != serviceUuid) {
      throw StateError('Unexpected service UUID');
    }
  }

  bool discover(String requestedServiceUuid) =>
      requestedServiceUuid == serviceUuid;

  void subscribe(String characteristicUuid, void Function(Uint8List) onValue) {
    events.add('subscribe:$characteristicUuid');
    _subscriptions[characteristicUuid] = onValue;
    if (characteristicUuid == identityCharacteristicUUID) {
      onValue(Uint8List.fromList(identity.toBytes()));
    }
  }

  List<int> readIdentity() => identity.toBytes();

  Future<NodosLinkResponse> writeLink(List<int> bytes) async {
    events.add('write:$linkCharacteristicUUID');
    if (!_subscriptions.containsKey(linkCharacteristicUUID)) {
      throw StateError('Link response was requested before subscription');
    }

    final request = NodosLinkRequest.fromBytes(bytes);
    final response = NodosLinkResponse(
      requesterUuid: request.deviceUuid,
      responderUuid: identity.uuid,
      accepted: true,
    );
    persistentLinked = true;
    events.add('response:$linkCharacteristicUUID');
    _subscriptions[linkCharacteristicUUID]!(
      Uint8List.fromList(response.toBytes()),
    );
    return response;
  }

  Future<void> writePeerGraph(List<int> bytes) async {
    final complete = _reassembler.add(bytes);
    if (complete != null) receivedPeerGraph = complete;
  }

  void notifyGraph(Uint8List bytes) {
    _subscriptions[graphCharacteristicUUID]?.call(bytes);
  }
}

class _InteropCentral {
  _InteropCentral({
    required this.platform,
    required this.transportId,
    required this.peripheral,
  });

  final BlePeripheralPlatform platform;
  final String transportId;
  final _InteropPeripheral peripheral;
  final _graphValues = <Uint8List>[];

  bool discover(String requestedServiceUuid) =>
      peripheral.discover(requestedServiceUuid);

  NodosIdentity readIdentity() {
    final values = <Uint8List>[];
    peripheral.subscribe(identityCharacteristicUUID, values.add);
    return NodosIdentity.fromBytes(values.single);
  }

  Future<NodosLinkResponse> link(NodosLinkRequest request) {
    peripheral.subscribe(linkCharacteristicUUID, _graphValues.add);
    return peripheral.writeLink(request.toBytes());
  }

  void subscribeGraph(void Function(Uint8List) onValue) {
    peripheral.subscribe(graphCharacteristicUUID, onValue);
  }

  Future<void> writePeerGraph(Uint8List frame) =>
      peripheral.writePeerGraph(frame);
}
