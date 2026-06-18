import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/config/app_config.dart';

void main() {
  group('AppConfig constants', () {
    test('serviceUuid is a valid 128-bit hex UUID', () {
      final uuidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      );
      expect(uuidPattern.hasMatch(serviceUuid), isTrue,
          reason: '$serviceUuid is not a valid 128-bit hex UUID');
    });

    test('serviceUuid matches the expected Nodos service UUID', () {
      expect(serviceUuid, '4fafc201-1fb5-459e-8fcc-c5c9c331914b');
    });

    test('txPower is the assumed value -50 dBm', () {
      expect(txPower, -50);
    });

    test('proximityThresholdClose is -70 dBm', () {
      expect(proximityThresholdClose, -70);
    });

    test('proximityThresholdMedium is -85 dBm', () {
      expect(proximityThresholdMedium, -85);
    });

    test('dutyCycleScanDuration is 2 seconds', () {
      expect(dutyCycleScanDuration, const Duration(seconds: 2));
    });

    test('dutyCyclePauseDuration is 8 seconds', () {
      expect(dutyCyclePauseDuration, const Duration(seconds: 8));
    });
  });
}
