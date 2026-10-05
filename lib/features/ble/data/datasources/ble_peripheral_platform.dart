import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';

/// Platform families supported by the peripheral adapter.
///
/// Keeping this descriptor injectable lets the advertising contract be tested
/// for Android and Darwin on any host.
enum BlePeripheralPlatform { android, darwin }

extension BlePeripheralPlatformDetection on BlePeripheralPlatform {
  static BlePeripheralPlatform get current {
    return defaultTargetPlatform == TargetPlatform.android
        ? BlePeripheralPlatform.android
        : BlePeripheralPlatform.darwin;
  }
}

/// Complete start configuration for the plugin, with portable data separated
/// from platform-specific settings.
class BlePeripheralPlatformConfig {
  const BlePeripheralPlatformConfig({
    required this.advertiseData,
    this.androidSettings,
    this.darwinSettings,
  });

  final AdvertiseDataCore advertiseData;
  final AndroidAdvertiseSettings? androidSettings;
  final DarwinAdvertiseSettings? darwinSettings;
}

class BlePeripheralPlatformConfigBuilder {
  const BlePeripheralPlatformConfigBuilder();

  BlePeripheralPlatformConfig build({
    required BlePeripheralPlatform platform,
    required String localName,
  }) {
    final normalizedName = platform == BlePeripheralPlatform.darwin
        ? _darwinLocalName(localName)
        : null;

    return BlePeripheralPlatformConfig(
      advertiseData: AdvertiseDataCore(
        serviceUuid: serviceUuid,
        serviceUuids: const [serviceUuid],
        localName: normalizedName,
      ),
      // The current Android behavior does not require platform-only fields.
      // In particular, includeDeviceName remains false because Nodos exposes
      // its identity through GATT rather than the system device name.
      androidSettings: platform == BlePeripheralPlatform.android
          ? const AndroidAdvertiseSettings()
          : null,
      // Darwin supports only overflow/solicited UUID settings. The Nodos
      // service is already part of the portable advertisement data, so no
      // additional Darwin-only setting is required for foreground use.
      darwinSettings: platform == BlePeripheralPlatform.darwin
          ? const DarwinAdvertiseSettings()
          : null,
    );
  }

  String? _darwinLocalName(String name) {
    if (name.isEmpty) return null;
    final bytes = utf8.encode(name);
    if (bytes.length <= 10) return name;

    final result = StringBuffer();
    var length = 0;
    for (final rune in name.runes) {
      final character = String.fromCharCode(rune);
      final characterLength = utf8.encode(character).length;
      if (length + characterLength > 10) break;
      result.write(character);
      length += characterLength;
    }
    return result.toString();
  }
}
