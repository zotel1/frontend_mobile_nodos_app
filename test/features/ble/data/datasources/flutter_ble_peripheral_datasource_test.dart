import 'dart:convert';

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

  // ─── PR6a: Tests de construcción del payload de identidad ──────
  // QUÉ: Verifica que buildIdentityPayload codifica correctamente
  // los metadatos del dispositivo como JSON dentro de un Uint8List.
  // POR QUÉ: el advertising BLE envía estos metadatos como
  // ManufacturerData para que otros dispositivos Nodos los lean.

  group('PR6a — buildIdentityPayload (función pura)', () {
    /// SC-PR6a-001: El payload contiene uuid, name y color.
    test('construye payload JSON con uuid, name y color', () {
      final payload = FlutterBlePeripheralDataSource.buildIdentityPayload(
        'abc-123',
        'Mi Nodo',
        '#FF5722',
      );

      final decoded = utf8.decode(payload);
      final json = jsonDecode(decoded) as Map<String, dynamic>;

      expect(json['uuid'], 'abc-123');
      expect(json['name'], 'Mi Nodo');
      expect(json['color'], '#FF5722');
      expect(json.length, 3);
    });

    /// Triangulación: diferentes valores producen JSON distinto.
    test('payload varía según los parámetros (triangulación)', () {
      final payload1 = FlutterBlePeripheralDataSource.buildIdentityPayload(
        'uuid-a', 'Dispositivo A', '#000000',
      );
      final payload2 = FlutterBlePeripheralDataSource.buildIdentityPayload(
        'uuid-b', 'Dispositivo B', '#FFFFFF',
      );

      final json1 = jsonDecode(utf8.decode(payload1));
      final json2 = jsonDecode(utf8.decode(payload2));

      expect(json1['uuid'], 'uuid-a');
      expect(json2['uuid'], 'uuid-b');
      expect(json1['name'], 'Dispositivo A');
      expect(json2['name'], 'Dispositivo B');
      expect(json1, isNot(equals(json2)));
    });

    /// Edge case: nombre vacío
    test('soporta nombre vacío sin crash', () {
      final payload = FlutterBlePeripheralDataSource.buildIdentityPayload(
        'uuid-1', '', '#000000',
      );

      final json = jsonDecode(utf8.decode(payload));
      expect(json['name'], '');
    });

    /// El payload es Uint8List (no null, no vacío).
    test('payload no es vacío', () {
      final payload = FlutterBlePeripheralDataSource.buildIdentityPayload(
        'test', 'test', '#000',
      );
      expect(payload, isA<Uint8List>());
      expect(payload, isNotEmpty);
    });
  });
}
