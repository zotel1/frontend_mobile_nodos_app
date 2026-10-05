import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_mobile_nodos_app/features/ble/platform/ble_settings_navigator.dart';

void main() {
  test('Android navigator delegates to its platform launcher', () async {
    var launched = false;
    final navigator = AndroidBleSettingsNavigator(
      launch: () async => launched = true,
    );

    expect(
      await navigator.openBluetoothSettings(),
      BleSettingsNavigationResult.opened,
    );
    expect(launched, isTrue);
  });

  test('iOS navigator opens app settings without an Android intent', () async {
    var opened = false;
    final navigator = IosBleSettingsNavigator(
      openSettings: () async {
        opened = true;
        return true;
      },
    );

    expect(
      await navigator.openBluetoothSettings(),
      BleSettingsNavigationResult.opened,
    );
    expect(opened, isTrue);
  });

  test('unsupported settings navigation is explicit', () async {
    const navigator = UnsupportedBleSettingsNavigator();

    expect(
      await navigator.openBluetoothSettings(),
      BleSettingsNavigationResult.unsupported,
    );
  });

  test('failed settings navigation does not throw', () async {
    final navigator = IosBleSettingsNavigator(openSettings: () async => false);

    expect(
      await navigator.openBluetoothSettings(),
      BleSettingsNavigationResult.failed,
    );
  });
}
