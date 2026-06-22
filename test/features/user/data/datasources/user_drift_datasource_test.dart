import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart'
    as domain;

void main() {
  late AppDatabase database;
  late UserLocalDataSource dataSource;

  final now = DateTime(2026, 6, 18, 12, 0, 0);

  setUp(() async {
    database = AppDatabase.inMemory();
    dataSource = UserDriftDataSource(database);
  });

  tearDown(() async {
    await database.close();
  });

  domain.User createUser({
    String uuid = '550e8400-e29b-41d4-a716-446655440000',
    String name = 'Usuario',
    String color = '#2196F3',
    String deviceType = 'mobile',
    DateTime? createdAt,
  }) {
    return domain.User(
      uuid: uuid,
      name: name,
      color: color,
      deviceType: deviceType,
      createdAt: createdAt ?? now,
    );
  }

  group('UserDriftDataSource', () {
    test('implements UserLocalDataSource', () {
      expect(dataSource, isA<UserLocalDataSource>());
    });

    test('getUser returns null when no user exists', () async {
      final result = await dataSource.getUser();
      expect(result, isNull);
    });

    test('upsertUser creates a user and getUser retrieves it', () async {
      final user = createUser();
      await dataSource.upsertUser(user);

      final retrieved = await dataSource.getUser();
      expect(retrieved, isNotNull);
      expect(retrieved!.uuid, '550e8400-e29b-41d4-a716-446655440000');
      expect(retrieved.name, 'Usuario');
      expect(retrieved.color, '#2196F3');
      expect(retrieved.deviceType, 'mobile');
    });

    test('upsertUser updates existing user by uuid', () async {
      final user = createUser();
      await dataSource.upsertUser(user);

      // Update same uuid
      final updated = createUser(
        name: 'Nuevo Nombre',
        color: '#FF5722',
      );
      await dataSource.upsertUser(updated);

      final retrieved = await dataSource.getUser();
      expect(retrieved!.name, 'Nuevo Nombre');
      expect(retrieved.color, '#FF5722');
    });

    test('updateName changes the name of the first user', () async {
      final user = createUser();
      await dataSource.upsertUser(user);

      await dataSource.updateName('Carlos');

      final retrieved = await dataSource.getUser();
      expect(retrieved!.name, 'Carlos');
    });

    test('updateColor changes the color of the first user', () async {
      final user = createUser();
      await dataSource.upsertUser(user);

      await dataSource.updateColor('#FF0000');

      final retrieved = await dataSource.getUser();
      expect(retrieved!.color, '#FF0000');
    });

    // T-PR2-004: Ahora lanza StateError en lugar de silent no-op.
    test('updateName lanza StateError cuando no hay usuario', () async {
      expect(
        () => dataSource.updateName('ShouldNotMatter'),
        throwsA(isA<StateError>()),
      );
    });

    // T-PR2-004: Ahora lanza StateError en lugar de silent no-op.
    test('updateColor lanza StateError cuando no hay usuario', () async {
      expect(
        () => dataSource.updateColor('#000000'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
