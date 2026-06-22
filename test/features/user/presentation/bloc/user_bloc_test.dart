import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/get_user_profile.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_color.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_name.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';

@GenerateNiceMocks([
  MockSpec<GetUserProfile>(),
  MockSpec<UpdateUserName>(),
  MockSpec<UpdateUserColor>(),
  MockSpec<UserRepository>(),
])
import 'user_bloc_test.mocks.dart';

void main() {
  late MockGetUserProfile mockGetUserProfile;
  late MockUpdateUserName mockUpdateUserName;
  late MockUpdateUserColor mockUpdateUserColor;
  late MockUserRepository mockUserRepository;
  late SharedPreferences prefs;

  final testUser = User(
    uuid: 'test-uuid-123',
    name: 'Test User',
    color: '#2196F3',
    deviceType: 'android',
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() async {
    mockGetUserProfile = MockGetUserProfile();
    mockUpdateUserName = MockUpdateUserName();
    mockUpdateUserColor = MockUpdateUserColor();
    mockUserRepository = MockUserRepository();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  UserBloc buildBloc() => UserBloc(
        getProfile: mockGetUserProfile,
        updateName: mockUpdateUserName,
        updateColor: mockUpdateUserColor,
        userRepository: mockUserRepository,
        prefs: prefs,
      );

  group('UserBloc', () {
    blocTest<UserBloc, UserState>(
      'emits [UserInitial] as initial state',
      build: buildBloc,
      verify: (bloc) => expect(bloc.state, isA<UserInitial>()),
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserLoaded] when LoadProfile succeeds',
      build: () {
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Right(testUser));
        return buildBloc();
      },
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>().having(
          (s) => s.user,
          'user',
          equals(testUser),
        ),
      ],
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserError] when LoadProfile fails',
      build: () {
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Left(CacheFailure('No user profile found')));
        return buildBloc();
      },
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserError>().having(
          (s) => s.message,
          'message',
          contains('No user profile found'),
        ),
      ],
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserLoaded] when UpdateName succeeds',
      seed: () => UserLoaded(testUser),
      build: () {
        when(mockUpdateUserName.call(any))
            .thenAnswer((_) async => const Right(null));
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Right(testUser.copyWith(name: 'New Name')));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const UpdateUserNameEvent('New Name')),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>().having(
          (s) => s.user.name,
          'name',
          'New Name',
        ),
      ],
      verify: (_) {
        verify(mockUpdateUserName.call(
          const UpdateUserNameParams(name: 'New Name'),
        )).called(1);
      },
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserError] when UpdateName fails',
      seed: () => UserLoaded(testUser),
      build: () {
        when(mockUpdateUserName.call(any)).thenAnswer(
            (_) async => Left(UnexpectedFailure('Save failed')));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const UpdateUserNameEvent('New Name')),
      expect: () => [
        isA<UserLoading>(),
        isA<UserError>().having(
          (s) => s.message,
          'message',
          contains('Save failed'),
        ),
      ],
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserLoaded] when UpdateColor succeeds',
      seed: () => UserLoaded(testUser),
      build: () {
        when(mockUpdateUserColor.call(any))
            .thenAnswer((_) async => const Right(null));
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Right(testUser.copyWith(color: '#FF5722')));
        return buildBloc();
      },
      act: (bloc) =>
          bloc.add(const UpdateUserColorEvent('#FF5722')),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>().having(
          (s) => s.user.color,
          'color',
          '#FF5722',
        ),
      ],
      verify: (_) {
        verify(mockUpdateUserColor.call(
          const UpdateUserColorParams(color: '#FF5722'),
        )).called(1);
      },
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserError] when UpdateColor fails',
      seed: () => UserLoaded(testUser),
      build: () {
        when(mockUpdateUserColor.call(any)).thenAnswer(
            (_) async => Left(UnexpectedFailure('Save failed')));
        return buildBloc();
      },
      act: (bloc) =>
          bloc.add(const UpdateUserColorEvent('#FF5722')),
      expect: () => [
        isA<UserLoading>(),
        isA<UserError>().having(
          (s) => s.message,
          'message',
          contains('Save failed'),
        ),
      ],
    );

    // ─── Tema (ThemeMode) ──────────────────────────────────

    blocTest<UserBloc, UserState>(
      'initial LoadProfile emits UserLoaded with themeMode=system',
      build: () {
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Right(testUser));
        return buildBloc();
      },
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>().having(
          (s) => s.themeMode,
          'themeMode',
          ThemeMode.system,
        ),
      ],
    );

    blocTest<UserBloc, UserState>(
      // T-PR1-004: themeMode ahora se preserva del estado actual, no de SharedPreferences.
      // En primera carga (UserInitial), el default es ThemeMode.system.
      'LoadProfile usa ThemeMode.system cuando no hay estado previo cargado',
      setUp: () async {
        SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
        prefs = await SharedPreferences.getInstance();
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', ThemeMode.system)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<UserBloc, UserState>(
      // T-PR1-004: Si el estado anterior es UserLoaded con dark, se preserva dark.
      'LoadProfile preserva themeMode del estado anterior',
      setUp: () {
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      seed: () => UserLoaded(testUser, themeMode: ThemeMode.dark),
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', ThemeMode.dark)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to dark changes themeMode in state',
      seed: () => UserLoaded(testUser),
      build: buildBloc,
      act: (bloc) => bloc.add(const UpdateThemeMode(ThemeMode.dark)),
      expect: () => [
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', ThemeMode.dark)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to dark persists in SharedPreferences',
      seed: () => UserLoaded(testUser),
      build: buildBloc,
      act: (bloc) => bloc.add(const UpdateThemeMode(ThemeMode.dark)),
      verify: (_) async {
        final p = await SharedPreferences.getInstance();
        expect(p.getString('theme_mode'), equals('dark'));
      },
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to light changes themeMode in state',
      seed: () => UserLoaded(testUser),
      build: buildBloc,
      act: (bloc) => bloc.add(const UpdateThemeMode(ThemeMode.light)),
      expect: () => [
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', ThemeMode.light)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to system changes themeMode in state',
      seed: () => UserLoaded(testUser, themeMode: ThemeMode.dark),
      build: buildBloc,
      act: (bloc) => bloc.add(const UpdateThemeMode(ThemeMode.system)),
      expect: () => [
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', ThemeMode.system)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    // T1.7 F7: Auto-creación de User default cuando no existe en DB.
    blocTest<UserBloc, UserState>(
      'creates default User when LoadProfile returns Left (no user in DB)',
      build: () {
        var callCount = 0;
        when(mockGetUserProfile.call(any)).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return Left(CacheFailure('No user profile found'));
          }
          return Right(testUser.copyWith(
            name: 'Mi dispositivo',
            color: '#2196F3',
            deviceType: 'android',
          ));
        });
        when(mockUserRepository.createUser(any))
            .thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>().having(
          (s) => s.user.name,
          'name',
          'Mi dispositivo',
        ),
      ],
      verify: (_) {
        verify(mockUserRepository.createUser(argThat(
          predicate((u) =>
              u is User &&
              u.name == 'Mi dispositivo' &&
              u.color == '#2196F3' &&
              u.deviceType == 'android'),
        ))).called(1);
      },
    );
  });
}
