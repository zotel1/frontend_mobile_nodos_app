import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum BleSettingsNavigationResult { opened, unsupported, failed }

abstract class BleSettingsNavigator {
  const BleSettingsNavigator();

  factory BleSettingsNavigator.platform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidBleSettingsNavigator();
      case TargetPlatform.iOS:
        return IosBleSettingsNavigator();
      default:
        return const UnsupportedBleSettingsNavigator();
    }
  }

  Future<BleSettingsNavigationResult> openBluetoothSettings();
}

class AndroidBleSettingsNavigator extends BleSettingsNavigator {
  AndroidBleSettingsNavigator({Future<void> Function()? launch})
    : _launch = launch ?? _launchAndroidSettings;

  final Future<void> Function() _launch;

  static Future<void> _launchAndroidSettings() => const AndroidIntent(
    action: 'android.settings.BLUETOOTH_SETTINGS',
  ).launch();

  @override
  Future<BleSettingsNavigationResult> openBluetoothSettings() async {
    try {
      await _launch();
      return BleSettingsNavigationResult.opened;
    } catch (_) {
      return BleSettingsNavigationResult.failed;
    }
  }
}

class IosBleSettingsNavigator extends BleSettingsNavigator {
  IosBleSettingsNavigator({Future<bool> Function()? openSettings})
    : _openSettings = openSettings ?? openAppSettings;

  final Future<bool> Function() _openSettings;

  @override
  Future<BleSettingsNavigationResult> openBluetoothSettings() async {
    try {
      return await _openSettings()
          ? BleSettingsNavigationResult.opened
          : BleSettingsNavigationResult.failed;
    } catch (_) {
      return BleSettingsNavigationResult.failed;
    }
  }
}

class UnsupportedBleSettingsNavigator extends BleSettingsNavigator {
  const UnsupportedBleSettingsNavigator();

  @override
  Future<BleSettingsNavigationResult> openBluetoothSettings() async =>
      BleSettingsNavigationResult.unsupported;
}
