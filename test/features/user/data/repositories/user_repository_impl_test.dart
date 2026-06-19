import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/repositories/user_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart'
    as domain;
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

@GenerateNiceMocks([MockSpec<UserLocalDataSource>()])
import 'user_repository_impl_test.mocks.dart';

void main() {
  late MockUserLocalDataSource mockDataSource;
  late UserRepository repository;

  final now = DateTime(2026, 6, 18, 12, 0, 0);

  setUp(() {
    mockDataSource = MockUserLocalDataSource();
    repository = UserRepositoryImpl(mockDataSource);
  });

  group('UserRepositoryImpl', () {
    test('implements UserRepository', () {
      expect(repository, isA<UserRepository>());
    });

    test('getUserProfile returns user from data source', () async {
      final user = domain.User(
        uuid: 'test-uuid',
        name: 'Usuario',
        color: '#2196F3',
        deviceType: 'mobile',
        createdAt: now,
      );
      when(mockDataSource.getUser()).thenAnswer((_) async => user);

      final result = await repository.getUserProfile();

      expect(result, isNotNull);
      expect(result!.uuid, 'test-uuid');
      expect(result.name, 'Usuario');
      verify(mockDataSource.getUser()).called(1);
    });

    test('getUserProfile returns null when no user exists', () async {
      when(mockDataSource.getUser()).thenAnswer((_) async => null);

      final result = await repository.getUserProfile();

      expect(result, isNull);
    });

    test('updateName delegates to data source', () async {
      when(mockDataSource.updateName(any)).thenAnswer((_) async {});

      await repository.updateName('Carlos');

      verify(mockDataSource.updateName('Carlos')).called(1);
    });

    test('updateColor delegates to data source', () async {
      when(mockDataSource.updateColor(any)).thenAnswer((_) async {});

      await repository.updateColor('#FF5722');

      verify(mockDataSource.updateColor('#FF5722')).called(1);
    });

    test('createUser delegates to data source', () async {
      when(mockDataSource.upsertUser(any)).thenAnswer((_) async {});

      final user = domain.User(
        uuid: 'new-uuid',
        name: 'New User',
        color: '#000000',
        deviceType: 'mobile',
        createdAt: now,
      );
      await repository.createUser(user);

      verify(mockDataSource.upsertUser(user)).called(1);
    });
  });
}
