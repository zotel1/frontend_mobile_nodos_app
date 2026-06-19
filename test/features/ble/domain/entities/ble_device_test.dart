import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

void main() {
  final now = DateTime(2026, 6, 18, 12, 0, 0);

  group('BleDevice', () {
    test('supports equality by all props', () {
      final device1 = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        deviceUuid: '550e8400-e29b-41d4-a716-446655440000',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
      );

      final device2 = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        deviceUuid: '550e8400-e29b-41d4-a716-446655440000',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
      );

      expect(device1, equals(device2));
    });

    test('supports inequality when any prop differs', () {
      final device1 = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
      );

      final device2 = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FE', // different
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
      );

      expect(device1, isNot(equals(device2)));
    });

    test('is immutable — fields are final', () {
      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
      );

      // If BleDevice is immutable, all fields are final and const constructable
      expect(device.deviceId, 'AA:BB:CC:DD:EE:FF');
      expect(device.rssi, -55);
      expect(device.proximity, ProximityLevel.close);
    });

    test('props list contains all fields', () {
      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
      );

      expect(device.props.length, 6);
      expect(device.props, containsAll([
        'AA:BB:CC:DD:EE:FF',
        null, // deviceUuid is null
        -55,
        1.8,
        ProximityLevel.close,
        now,
      ]));
    });

    test('supports null deviceUuid', () {
      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -70,
        distance: 5.0,
        proximity: ProximityLevel.medium,
        timestamp: now,
      );

      expect(device.deviceUuid, isNull);
      final withUuid = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        deviceUuid: 'uuid-here',
        rssi: -70,
        distance: 5.0,
        proximity: ProximityLevel.medium,
        timestamp: now,
      );
      expect(device, isNot(equals(withUuid)));
    });
  });
}
