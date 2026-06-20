import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';

void main() {
  final now = DateTime(2026, 6, 18, 12, 0, 0);

  group('User', () {
    test('supports equality by all props', () {
      final user1 = User(
        uuid: '550e8400-e29b-41d4-a716-446655440000',
        name: 'Usuario',
        color: '#2196F3',
        deviceType: 'Android',
        createdAt: now,
      );

      final user2 = User(
        uuid: '550e8400-e29b-41d4-a716-446655440000',
        name: 'Usuario',
        color: '#2196F3',
        deviceType: 'Android',
        createdAt: now,
      );

      expect(user1, equals(user2));
    });

    test('supports inequality when any prop differs', () {
      final user1 = User(
        uuid: '550e8400-e29b-41d4-a716-446655440000',
        name: 'Usuario',
        color: '#2196F3',
        deviceType: 'Android',
        createdAt: now,
      );

      final user2 = User(
        uuid: '550e8400-e29b-41d4-a716-446655440000',
        name: 'Other', // different
        color: '#2196F3',
        deviceType: 'Android',
        createdAt: now,
      );

      expect(user1, isNot(equals(user2)));
    });

    test('is immutable — const constructable', () {
      final user = User(
        uuid: '550e8400-e29b-41d4-a716-446655440000',
        name: 'Usuario',
        color: '#2196F3',
        deviceType: 'Android',
        createdAt: now,
      );

      expect(user.uuid, '550e8400-e29b-41d4-a716-446655440000');
      expect(user.name, 'Usuario');
      expect(user.color, '#2196F3');
      expect(user.deviceType, 'Android');
    });

    test('props list contains all fields', () {
      final user = User(
        uuid: '550e8400-e29b-41d4-a716-446655440000',
        name: 'Usuario',
        color: '#2196F3',
        deviceType: 'Android',
        createdAt: now,
      );

      expect(user.props.length, 6);
      expect(user.props, containsAll([
        '550e8400-e29b-41d4-a716-446655440000',
        'Usuario',
        '#2196F3',
        'Android',
        now,
      ]));
    });
  });
}
