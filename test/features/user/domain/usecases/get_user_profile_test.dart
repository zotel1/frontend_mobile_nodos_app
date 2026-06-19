import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/usecases/usecase.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/get_user_profile.dart';

@GenerateNiceMocks([MockSpec<UserRepository>()])
import 'get_user_profile_test.mocks.dart';

void main() {
  late MockUserRepository mockRepository;
  late GetUserProfile useCase;

  final testUser = User(
    uuid: '550e8400-e29b-41d4-a716-446655440000',
    name: 'Usuario',
    color: '#2196F3',
    deviceType: 'Android',
    createdAt: DateTime(2026, 6, 18),
  );

  setUp(() {
    mockRepository = MockUserRepository();
    useCase = GetUserProfile(mockRepository);
  });

  group('GetUserProfile', () {
    test('calls repository.getUserProfile() and returns Right(User)', () async {
      // arrange
      when(mockRepository.getUserProfile()).thenAnswer((_) async => testUser);

      // act
      final result = await useCase(const NoParams());

      // assert
      verify(mockRepository.getUserProfile()).called(1);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (user) => expect(user, equals(testUser)),
      );
    });

    test('returns Left(Failure) when no profile exists', () async {
      // arrange
      when(mockRepository.getUserProfile()).thenAnswer((_) async => null);

      // act
      final result = await useCase(const NoParams());

      // assert
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('Expected Left, got Right'),
      );
    });

    test('returns Left(Failure) when repository throws', () async {
      // arrange
      when(mockRepository.getUserProfile())
          .thenThrow(Exception('DB error'));

      // act
      final result = await useCase(const NoParams());

      // assert
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure.message, contains('DB error')),
        (_) => fail('Expected Left, got Right'),
      );
    });
  });
}
