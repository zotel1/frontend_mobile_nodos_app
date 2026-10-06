import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/ble/platform/ble_background_policy.dart';

void main() {
  test('foregroundOnly keeps the IOS-007 destructive cleanup policy', () {
    const policy = BleBackgroundPolicy.foregroundOnly();

    expect(policy.keepRuntimeOnBackground, isFalse);
    expect(policy.supportsCentralBackground, isFalse);
    expect(policy.supportsPeripheralBackground, isFalse);
    expect(policy.supportsNativeStateRestoration, isFalse);
  });

  test('iOS policy represents native central and peripheral capabilities', () {
    const policy = BleBackgroundPolicy.iosBackgroundCapable();

    expect(policy.keepRuntimeOnBackground, isTrue);
    expect(policy.supportsCentralBackground, isTrue);
    expect(policy.supportsPeripheralBackground, isTrue);
    expect(policy.supportsNativeStateRestoration, isTrue);
    // The plugins restore natively, but do not expose a domain callback.
    expect(policy.appReceivesRestorationCallbacks, isFalse);
  });

  test('Info.plist declares both CoreBluetooth background roles', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(plist, contains('<string>bluetooth-central</string>'));
    expect(plist, contains('<string>bluetooth-peripheral</string>'));
  });
}
