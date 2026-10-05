import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  Node knownNode(String address, {int id = 1}) {
    return Node(
      id: id,
      bleAddress: address,
      name: 'Known $address',
      firstSeen: now,
      lastSeen: now,
    );
  }

  BleDevice visibleDevice(String address) {
    return BleDevice(
      deviceId: address,
      rssi: -60,
      distance: 2,
      proximity: ProximityLevel.close,
      timestamp: now,
    );
  }

  group('KNOWN versus VISIBLE projection', () {
    test('historical nodes are not visible without a current BLE result', () {
      final historical = [knownNode('AA:AA')];

      final visible = NodeListBloc.visibleNodesForDeviceIds(
        historical,
        const <String>[],
      );

      expect(visible, isEmpty);
    });

    test('a current BLE result projects the persisted node as visible', () {
      final node = knownNode('AA:AA');

      final visible = NodeListBloc.visibleNodesForDeviceIds(
        [node],
        [visibleDevice('AA:AA').deviceId],
      );

      expect(visible, [node]);
    });

    test('a device outside the current presence window is no longer visible', () {
      final node = knownNode('AA:AA');

      final visible = NodeListBloc.visibleNodesForDeviceIds(
        [node],
        [visibleDevice('BB:BB').deviceId],
      );

      expect(visible, isEmpty);
    });

    test('stopping the scan does not repopulate visibility from the catalog', () {
      final catalog = [knownNode('AA:AA'), knownNode('BB:BB', id: 2)];

      final visible = NodeListBloc.visibleNodesForDeviceIds(
        catalog,
        const <String>[],
      );

      expect(visible, isEmpty);
      expect(catalog, hasLength(2));
    });
  });
}
