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

      expect(device.props, containsAll([
        'AA:BB:CC:DD:EE:FF',
        null, // deviceUuid
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

    // ─── T1.3: Nuevos campos de enriquecimiento ─────────────────
    // QUÉ: BleDevice ahora almacena advName, platformName, txPowerLevel,
    // connectable, serviceUuids y deviceType desde advertisementData.
    // POR QUÉ: enriquece el pipeline de datos para identidad visual
    // y clasificación de dispositivos (Phase 4).

    test('advName almacena el nombre anunciado BLE', () {
      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
        advName: 'AirPods Pro',
      );
      expect(device.advName, 'AirPods Pro');
    });

    test('advName es null por defecto (backward-compatible)', () {
      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
      );
      expect(device.advName, isNull);
    });

    test('platformName almacena el nombre del SO', () {
      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
        platformName: 'iPhone de Juan',
      );
      expect(device.platformName, 'iPhone de Juan');
    });

    test('txPowerLevel almacena la potencia de transmisión', () {
      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
        txPowerLevel: -40,
      );
      expect(device.txPowerLevel, -40);
    });

    test('connectable indica si el dispositivo acepta conexión', () {
      final connectable = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:01',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
        connectable: true,
      );
      final notConnectable = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:02',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
        connectable: false,
      );
      expect(connectable.connectable, isTrue);
      expect(notConnectable.connectable, isFalse);
    });

    test('connectable es false por defecto', () {
      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
      );
      expect(device.connectable, isFalse);
    });

    test('serviceUuids almacena los UUIDs de servicio anunciados', () {
      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
        serviceUuids: const ['0x180D', '0x180F'],
      );
      expect(device.serviceUuids, ['0x180D', '0x180F']);
    });

    test('deviceType almacena el tipo clasificado', () {
      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
        deviceType: 'Reloj/Fitness',
      );
      expect(device.deviceType, 'Reloj/Fitness');
    });

    test('dos BleDevice con mismos nuevos campos son iguales', () {
      final device1 = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
        advName: 'AirPods',
        platformName: 'iPhone',
        txPowerLevel: -40,
        connectable: true,
        serviceUuids: const ['0x180A'],
        deviceType: 'Auriculares',
      );
      final device2 = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
        advName: 'AirPods',
        platformName: 'iPhone',
        txPowerLevel: -40,
        connectable: true,
        serviceUuids: const ['0x180A'],
        deviceType: 'Auriculares',
      );
      expect(device1, equals(device2));
    });

    test('props incluye todos los campos nuevos', () {
      final device = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -55,
        distance: 1.8,
        proximity: ProximityLevel.close,
        timestamp: now,
        advName: 'Watch',
        platformName: 'Pixel',
        txPowerLevel: -30,
        connectable: false,
        serviceUuids: const ['0x180D'],
        deviceType: 'Reloj',
      );

      expect(device.props, containsAll([
        'AA:BB:CC:DD:EE:FF',
        null, // deviceUuid
        -55,
        1.8,
        ProximityLevel.close,
        now,
        'Watch',     // advName
        'Pixel',     // platformName
        -30,         // txPowerLevel
        false,       // connectable
        ['0x180D'],  // serviceUuids
        'Reloj',     // deviceType
      ]));
    });
  });
}
