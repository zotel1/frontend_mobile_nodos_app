import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/transport/ble_mtu_policy.dart';

void main() {
  group('BleMtuPolicy', () {
    test('uses safe fallback for invalid MTU values', () {
      for (final mtu in <int?>[null, 0, -1, 2, 3, 18, 20, 22]) {
        final policy = BleMtuPolicy.fromMtu(mtu);
        expect(policy.effectiveMtu, 23);
        expect(policy.attPayloadCapacity, 20);
        expect(policy.framedPayloadCapacity, 2);
      }
    });

    test('calculates ATT and framed capacities without protocol changes', () {
      expect(BleMtuPolicy.fromMtu(23).framedPayloadCapacity, 2);
      expect(BleMtuPolicy.fromMtu(40).framedPayloadCapacity, 19);
      expect(BleMtuPolicy.fromMtu(185).framedPayloadCapacity, 164);
      expect(BleMtuPolicy.fromMtu(247).framedPayloadCapacity, 226);
      expect(BleMtuPolicy.fromMtu(512).framedPayloadCapacity, 255);
    });

    test('caps absurdly large capacities at one-byte fragment length', () {
      expect(BleMtuPolicy.centralWriteCapacity(1000000), 255);
      expect(BleMtuPolicy.peripheralNotificationCapacity(), 2);
      expect(
        BleMtuPolicy.peripheralNotificationCapacity(
          maximumUpdateValueLength: 512,
        ),
        255,
      );
    });
  });
}
