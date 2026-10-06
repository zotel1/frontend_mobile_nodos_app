import 'package:flutter/foundation.dart';

/// The background transport capabilities available to the current platform.
///
/// These values describe platform/plugin support, not a promise that Dart will
/// keep executing while the process is suspended.
class BleBackgroundCapabilities {
  final bool supportsCentralBackground;
  final bool supportsPeripheralBackground;
  final bool supportsNativeStateRestoration;
  final bool appReceivesRestorationCallbacks;

  const BleBackgroundCapabilities({
    required this.supportsCentralBackground,
    required this.supportsPeripheralBackground,
    required this.supportsNativeStateRestoration,
    required this.appReceivesRestorationCallbacks,
  });

  static const foregroundOnly = BleBackgroundCapabilities(
    supportsCentralBackground: false,
    supportsPeripheralBackground: false,
    supportsNativeStateRestoration: false,
    appReceivesRestorationCallbacks: false,
  );

  /// CoreBluetooth support exposed by the plugins used by Nodos on iOS.
  ///
  /// `flutter_blue_plus` exposes central restoration through `setOptions` and
  /// `flutter_ble_peripheral` manages peripheral restoration internally when
  /// the peripheral background mode is declared. Neither plugin exposes a
  /// domain-level restoration callback to this application.
  static const iosCoreBluetooth = BleBackgroundCapabilities(
    supportsCentralBackground: true,
    supportsPeripheralBackground: true,
    supportsNativeStateRestoration: true,
    appReceivesRestorationCallbacks: false,
  );
}

/// Explicit application policy for BLE while the app is not foregrounded.
class BleBackgroundPolicy {
  final BleBackgroundCapabilities capabilities;
  final bool keepRuntimeOnBackground;

  const BleBackgroundPolicy({
    required this.capabilities,
    required this.keepRuntimeOnBackground,
  });

  const BleBackgroundPolicy.foregroundOnly()
    : capabilities = BleBackgroundCapabilities.foregroundOnly,
      keepRuntimeOnBackground = false;

  const BleBackgroundPolicy.iosBackgroundCapable()
    : capabilities = BleBackgroundCapabilities.iosCoreBluetooth,
      keepRuntimeOnBackground = true;

  static BleBackgroundPolicy get platform {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const BleBackgroundPolicy.iosBackgroundCapable();
    }
    return const BleBackgroundPolicy.foregroundOnly();
  }

  bool get supportsCentralBackground => capabilities.supportsCentralBackground;

  bool get supportsPeripheralBackground =>
      capabilities.supportsPeripheralBackground;

  bool get supportsNativeStateRestoration =>
      capabilities.supportsNativeStateRestoration;

  bool get appReceivesRestorationCallbacks =>
      capabilities.appReceivesRestorationCallbacks;
}
