import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_ble_peripheral_datasource.dart';

void main() {
  group('FlutterBlePeripheralDataSource', () {
    test('implements BleAdvertiserDataSource', () {
      final dataSource = FlutterBlePeripheralDataSource();
      expect(dataSource, isA<BleAdvertiserDataSource>());
    });

    test('startAdvertise completes without error (stub)', () async {
      final dataSource = FlutterBlePeripheralDataSource();
      // Should complete — stub implementation
      await dataSource.startAdvertise(
        'device-uuid',
        '4fafc201-1fb5-459e-8fcc-c5c9c331914b',
      );
    });

    test('stopAdvertise completes without error (stub)', () async {
      final dataSource = FlutterBlePeripheralDataSource();
      await dataSource.stopAdvertise();
    });
  });
}
