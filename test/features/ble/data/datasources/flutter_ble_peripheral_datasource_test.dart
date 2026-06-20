import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_ble_peripheral_datasource.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterBlePeripheralDataSource', () {
    test('implements BleAdvertiserDataSource', () {
      final dataSource = FlutterBlePeripheralDataSource();
      expect(dataSource, isA<BleAdvertiserDataSource>());
    });

    /// PR2: Verifica que startAdvertise acepta los parámetros de identidad
    /// (uuid, name, color). En un test unitario sin hardware, la llamada
    /// al MethodChannel lanzará MissingPluginException, lo cual es esperado.
    /// Verificamos que la firma del método es correcta.
    test('startAdvertise acepta deviceUuid, name y color (params)', () async {
      final dataSource = FlutterBlePeripheralDataSource();
      // En entorno de test sin plataforma real, esperamos MissingPluginException.
      // Esto confirma que el método intenta comunicarse con el platform channel.
      await expectLater(
        dataSource.startAdvertise('test-uuid', 'Mi dispositivo', '#2196F3'),
        throwsA(isA<MissingPluginException>()),
      );
    });

    /// PR2: stopAdvertise no requiere parámetros.
    test('stopAdvertise existe y no requiere parámetros', () async {
      final dataSource = FlutterBlePeripheralDataSource();
      await expectLater(
        dataSource.stopAdvertise(),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });
}
