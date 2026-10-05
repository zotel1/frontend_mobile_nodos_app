import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum BlePermissionScope { scan, connection, advertising }

typedef BlePermissionRequest =
    Future<PermissionStatus> Function(Permission permission);

typedef BlePermissionStatus =
    Future<PermissionStatus> Function(Permission permission);

abstract class BlePermissionPolicy {
  const BlePermissionPolicy();

  factory BlePermissionPolicy.platform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidBlePermissionPolicy();
      case TargetPlatform.iOS:
        return IosBlePermissionPolicy();
      default:
        return const UnsupportedBlePermissionPolicy();
    }
  }

  Future<bool> requestScanPermissions();

  Future<bool> requestConnectionPermissions();

  Future<bool> requestAdvertisingPermissions();

  Future<bool> hasRequiredPermissions(BlePermissionScope scope);
}

class AndroidBlePermissionPolicy extends BlePermissionPolicy {
  AndroidBlePermissionPolicy({
    BlePermissionRequest? request,
    BlePermissionStatus? status,
  }) : _request = request ?? ((permission) => permission.request()),
       _status = status ?? ((permission) => permission.status);

  final BlePermissionRequest _request;
  final BlePermissionStatus _status;

  @override
  Future<bool> requestScanPermissions() async =>
      (await _request(Permission.bluetoothScan)).isGranted;

  @override
  Future<bool> requestConnectionPermissions() async =>
      (await _request(Permission.bluetoothConnect)).isGranted;

  @override
  Future<bool> requestAdvertisingPermissions() async =>
      (await _request(Permission.bluetoothAdvertise)).isGranted;

  @override
  Future<bool> hasRequiredPermissions(BlePermissionScope scope) async {
    final permission = switch (scope) {
      BlePermissionScope.scan => Permission.bluetoothScan,
      BlePermissionScope.connection => Permission.bluetoothConnect,
      BlePermissionScope.advertising => Permission.bluetoothAdvertise,
    };
    return (await _status(permission)).isGranted;
  }
}

class IosBlePermissionPolicy extends BlePermissionPolicy {
  IosBlePermissionPolicy({
    BlePermissionRequest? request,
    BlePermissionStatus? status,
  }) : _request = request ?? ((permission) => permission.request()),
       _status = status ?? ((permission) => permission.status);

  final BlePermissionRequest _request;
  final BlePermissionStatus _status;

  @override
  Future<bool> requestScanPermissions() async =>
      (await _request(Permission.bluetooth)).isGranted;

  @override
  Future<bool> requestConnectionPermissions() async =>
      (await _request(Permission.bluetooth)).isGranted;

  @override
  Future<bool> requestAdvertisingPermissions() async =>
      (await _request(Permission.bluetooth)).isGranted;

  @override
  Future<bool> hasRequiredPermissions(BlePermissionScope scope) async =>
      (await _status(Permission.bluetooth)).isGranted;
}

class UnsupportedBlePermissionPolicy extends BlePermissionPolicy {
  const UnsupportedBlePermissionPolicy();

  @override
  Future<bool> requestScanPermissions() async => false;

  @override
  Future<bool> requestConnectionPermissions() async => false;

  @override
  Future<bool> requestAdvertisingPermissions() async => false;

  @override
  Future<bool> hasRequiredPermissions(BlePermissionScope scope) async => false;
}

/// Default used by unit tests that provide a fake BLE repository.
class AllowAllBlePermissionPolicy extends BlePermissionPolicy {
  const AllowAllBlePermissionPolicy();

  @override
  Future<bool> requestScanPermissions() async => true;

  @override
  Future<bool> requestConnectionPermissions() async => true;

  @override
  Future<bool> requestAdvertisingPermissions() async => true;

  @override
  Future<bool> hasRequiredPermissions(BlePermissionScope scope) async => true;
}
