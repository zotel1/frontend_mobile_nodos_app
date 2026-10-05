import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_mobile_nodos_app/features/ble/platform/ble_platform_capabilities.dart';

void main() {
  test('capabilities can be configured independently of host platform', () {
    const android = BlePlatformCapabilities(
      supportsDirectBluetoothSettingsNavigation: true,
      usesAndroidRuntimeBlePermissions: true,
    );
    const ios = BlePlatformCapabilities(
      supportsDirectBluetoothSettingsNavigation: false,
      usesAndroidRuntimeBlePermissions: false,
    );

    expect(android.usesAndroidRuntimeBlePermissions, isTrue);
    expect(ios.supportsDirectBluetoothSettingsNavigation, isFalse);
  });
}
