import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:frontend_mobile_nodos_app/features/ble/platform/ble_permission_policy.dart';

void main() {
  test(
    'Android requests scan, connection and advertising permissions',
    () async {
      final requested = <Permission>[];
      final policy = AndroidBlePermissionPolicy(
        request: (permission) async {
          requested.add(permission);
          return PermissionStatus.granted;
        },
        status: (_) async => PermissionStatus.granted,
      );

      expect(await policy.requestScanPermissions(), isTrue);
      expect(await policy.requestConnectionPermissions(), isTrue);
      expect(await policy.requestAdvertisingPermissions(), isTrue);

      expect(
        requested.map((permission) => permission.value),
        containsAll(<int>[
          Permission.bluetoothScan.value,
          Permission.bluetoothConnect.value,
          Permission.bluetoothAdvertise.value,
        ]),
      );
    },
  );

  test('iOS uses the grouped Bluetooth permission for every scope', () async {
    final requested = <Permission>[];
    final policy = IosBlePermissionPolicy(
      request: (permission) async {
        requested.add(permission);
        return PermissionStatus.granted;
      },
      status: (_) async => PermissionStatus.granted,
    );

    expect(await policy.requestScanPermissions(), isTrue);
    expect(await policy.requestConnectionPermissions(), isTrue);
    expect(await policy.requestAdvertisingPermissions(), isTrue);

    expect(
      requested.map((permission) => permission.value),
      everyElement(Permission.bluetooth.value),
    );
    expect(
      requested.map((permission) => permission.value),
      isNot(contains(Permission.bluetoothScan.value)),
    );
    expect(
      requested.map((permission) => permission.value),
      isNot(contains(Permission.bluetoothConnect.value)),
    );
  });

  test('denied permission is returned as false', () async {
    final policy = AndroidBlePermissionPolicy(
      request: (_) async => PermissionStatus.denied,
      status: (_) async => PermissionStatus.denied,
    );

    expect(await policy.requestConnectionPermissions(), isFalse);
    expect(
      await policy.hasRequiredPermissions(BlePermissionScope.connection),
      isFalse,
    );
  });
}
