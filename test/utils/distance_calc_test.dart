import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/utils/distance_calc.dart';

void main() {
  group('rssiToDistance', () {
    test('rssi = -65 returns distance ~5.6m', () {
      final distance = rssiToDistance(-65);
      expect(distance, closeTo(5.6, 0.2));
    });

    test('rssi = -78 returns distance ~25.1m', () {
      final distance = rssiToDistance(-78);
      expect(distance, closeTo(25.1, 0.5));
    });

    test('rssi = -100 returns distance ~316m', () {
      final distance = rssiToDistance(-100);
      expect(distance, closeTo(316.0, 2.0));
    });

    test('rssi = 0 returns clamped distance (far / max value)', () {
      final distance = rssiToDistance(0);
      expect(distance, greaterThan(1000));
    });

    test('rssi = -50 returns distance ~1.0m (txPower reference)', () {
      final distance = rssiToDistance(-50);
      expect(distance, closeTo(1.0, 0.1));
    });
  });

  group('rssiToProximity', () {
    test('rssi = -65 returns ProximityLevel.close', () {
      expect(rssiToProximity(-65), ProximityLevel.close);
    });

    test('rssi = -78 returns ProximityLevel.medium', () {
      expect(rssiToProximity(-78), ProximityLevel.medium);
    });

    test('rssi = -85 returns ProximityLevel.medium (boundary)', () {
      expect(rssiToProximity(-85), ProximityLevel.medium);
    });

    test('rssi = -100 returns ProximityLevel.far', () {
      expect(rssiToProximity(-100), ProximityLevel.far);
    });

    test('rssi = 0 returns ProximityLevel.far', () {
      expect(rssiToProximity(0), ProximityLevel.far);
    });

    test('rssi = -70 returns ProximityLevel.medium (boundary)', () {
      expect(rssiToProximity(-70), ProximityLevel.medium);
    });

    test('rssi = -69 returns ProximityLevel.close (just above boundary)', () {
      expect(rssiToProximity(-69), ProximityLevel.close);
    });

    test('rssi = -86 returns ProximityLevel.far (just below boundary)', () {
      expect(rssiToProximity(-86), ProximityLevel.far);
    });
  });
}
