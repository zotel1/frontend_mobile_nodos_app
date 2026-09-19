import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_identity.dart';

void main() {
  group('NodosIdentity', () {
    const identity = NodosIdentity(
      uuid: '550e8400-e29b-41d4-a716-446655440000',
      name: 'Cristian',
      color: '#2196F3',
    );

    test('usa protocol version 1 por defecto', () {
      expect(identity.version, equals(1));
      expect(
        identity.version,
        equals(NodosIdentity.currentVersion),
      );
    });

    test('toJson conserva todos los campos del protocolo', () {
      expect(
        identity.toJson(),
        equals({
          'version': 1,
          'uuid': '550e8400-e29b-41d4-a716-446655440000',
          'name': 'Cristian',
          'color': '#2196F3',
        }),
      );
    });

    test('toJsonString genera JSON válido', () {
      final decoded = jsonDecode(identity.toJsonString());

      expect(decoded['version'], equals(1));
      expect(
        decoded['uuid'],
        equals('550e8400-e29b-41d4-a716-446655440000'),
      );
      expect(decoded['name'], equals('Cristian'));
      expect(decoded['color'], equals('#2196F3'));
    });

    test('toBytes y fromBytes realizan roundtrip completo', () {
      final bytes = identity.toBytes();

      final decoded = NodosIdentity.fromBytes(bytes);

      expect(decoded, equals(identity));
    });

    test('fromJsonString realiza roundtrip completo', () {
      final decoded = NodosIdentity.fromJsonString(
        identity.toJsonString(),
      );

      expect(decoded, equals(identity));
    });

    test('fromBytes falla cuando el payload está vacío', () {
      expect(
        () => NodosIdentity.fromBytes(const []),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson falla cuando falta uuid', () {
      expect(
        () => NodosIdentity.fromJson({
          'version': 1,
          'name': 'Cristian',
          'color': '#2196F3',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson falla cuando falta name', () {
      expect(
        () => NodosIdentity.fromJson({
          'version': 1,
          'uuid': '550e8400-e29b-41d4-a716-446655440000',
          'color': '#2196F3',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson falla cuando falta color', () {
      expect(
        () => NodosIdentity.fromJson({
          'version': 1,
          'uuid': '550e8400-e29b-41d4-a716-446655440000',
          'name': 'Cristian',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rechaza una versión futura del protocolo', () {
      expect(
        () => NodosIdentity.fromJson({
          'version': 2,
          'uuid': '550e8400-e29b-41d4-a716-446655440000',
          'name': 'Cristian',
          'color': '#2196F3',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Versión de protocolo Nodos no soportada'),
          ),
        ),
      );
    });

    test('rechaza JSON que no sea un objeto', () {
      expect(
        () => NodosIdentity.fromJsonString(
          '["uuid", "name", "color"]',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('dos identidades iguales son Equatable', () {
      const other = NodosIdentity(
        uuid: '550e8400-e29b-41d4-a716-446655440000',
        name: 'Cristian',
        color: '#2196F3',
      );

      expect(identity, equals(other));
    });

    test('dos UUID distintos producen identidades distintas', () {
      const other = NodosIdentity(
        uuid: 'otro-uuid',
        name: 'Cristian',
        color: '#2196F3',
      );

      expect(identity, isNot(equals(other)));
    });
  });
}