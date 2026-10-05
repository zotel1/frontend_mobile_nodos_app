import 'package:flutter/foundation.dart';

class BlePlatformCapabilities {
  const BlePlatformCapabilities({
    required this.supportsDirectBluetoothSettingsNavigation,
    required this.usesAndroidRuntimeBlePermissions,
  });

  factory BlePlatformCapabilities.platform() {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    return BlePlatformCapabilities(
      supportsDirectBluetoothSettingsNavigation: isAndroid,
      usesAndroidRuntimeBlePermissions: isAndroid,
    );
  }

  final bool supportsDirectBluetoothSettingsNavigation;
  final bool usesAndroidRuntimeBlePermissions;
}
