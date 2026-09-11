import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/utils/app_theme_mode.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/ensure_local_node.dart';
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
  MockSpec<EnsureLocalNode>(),
])
import 'user_bloc_test.mocks.dart';

void main() {
  late MockGetUserProfile mockGetUserProfile;
  late MockUpdateUserName mockUpdateUserName;
  late MockUpdateUserColor mockUpdateUserColor;
  late MockUserRepository mockUserRepository;
  late MockEnsureLocalNode mockEnsureLocalNode;
  late SharedPreferences prefs;

  final testUser = User(
    uuid: 'test-uuid-123',
    name: 'Test User',
    color: '#2196F3',
    deviceType: 'android',
    createdAt: DateTime(2026, 1, 1),
  );

  User loadedUser(User user) => user.copyWith(localNodeId: 99);

  Node selfNodeFor(User user) => Node(
    id: 99,
    deviceUuid: user.uuid,
    bleAddress: null,
    isSelf: true,
    name: user.name,
    color: user.color,
    firstSeen: user.createdAt,
    lastSeen: user.createdAt,
    deviceType: user.deviceType,
    connectable: false,
    estimatedDistance: 0.0,
  );

  setUp(() async {
    mockGetUserProfile = MockGetUserProfile();
    mockUpdateUserName = MockUpdateUserName();
    mockUpdateUserColor = MockUpdateUserColor();
    mockUserRepository = MockUserRepository();
    mockEnsureLocalNode = MockEnsureLocalNode();

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    // ARCH-001:
    // Por defecto cualquier User válido obtiene un self-node persistente
    // cuyo ID es deliberadamente distinto de User.id.
    when(mockEnsureLocalNode.call(any)).thenAnswer((invocation) async {
      final user = invocation.positionalArguments.first as User;

      return Right(selfNodeFor(user));
    });
  });

  UserBloc buildBloc() => UserBloc(
    getProfile: mockGetUserProfile,
    updateName: mockUpdateUserName,
    updateColor: mockUpdateUserColor,
    ensureLocalNode: mockEnsureLocalNode,
    userRepository: mockUserRepository,
    prefs: prefs,
  );

  group('UserBloc', () {
    blocTest<UserBloc, UserState>(
      'emits [UserInitial] as initial state',
      build: buildBloc,
      verify: (bloc) {
        expect(bloc.state, isA<UserInitial>());
      },
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserLoaded] when LoadProfile succeeds',
      build: () {
        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Right(testUser));

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((state) => state.user.uuid, 'uuid', testUser.uuid)
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
      verify: (_) {
        verify(mockEnsureLocalNode.call(testUser)).called(1);
      },
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserError] when LoadProfile fails with DatabaseFailure',
      build: () {
        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Left(DatabaseFailure('DB failure')));

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserError>().having(
          (state) => state.message,
          'message',
          contains('DB failure'),
        ),
      ],
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserLoaded] when UpdateName succeeds',
      seed: () => UserLoaded(loadedUser(testUser)),
      build: () {
        final updated = testUser.copyWith(name: 'New Name', localNodeId: 99);

        when(
          mockUpdateUserName.call(any),
        ).thenAnswer((_) async => const Right(null));

        when(
          mockUserRepository.getUserProfile(),
        ).thenAnswer((_) async => updated);

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const UpdateUserNameEvent('New Name'));
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((state) => state.user.name, 'name', 'New Name')
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
      verify: (_) {
        verify(
          mockUpdateUserName.call(const UpdateUserNameParams(name: 'New Name')),
        ).called(1);
      },
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserError] when UpdateName fails',
      seed: () => UserLoaded(loadedUser(testUser)),
      build: () {
        when(
          mockUpdateUserName.call(any),
        ).thenAnswer((_) async => Left(UnexpectedFailure('Save failed')));

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const UpdateUserNameEvent('New Name'));
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserError>().having(
          (state) => state.message,
          'message',
          contains('Save failed'),
        ),
      ],
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserLoaded] when UpdateColor succeeds',
      seed: () => UserLoaded(loadedUser(testUser)),
      build: () {
        final updated = testUser.copyWith(color: '#FF5722', localNodeId: 99);

        when(
          mockUpdateUserColor.call(any),
        ).thenAnswer((_) async => const Right(null));

        when(
          mockUserRepository.getUserProfile(),
        ).thenAnswer((_) async => updated);

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const UpdateUserColorEvent('#FF5722'));
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((state) => state.user.color, 'color', '#FF5722')
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
      verify: (_) {
        verify(
          mockUpdateUserColor.call(
            const UpdateUserColorParams(color: '#FF5722'),
          ),
        ).called(1);
      },
    );

    blocTest<UserBloc, UserState>(
      'emits [UserLoading, UserError] when UpdateColor fails',
      seed: () => UserLoaded(loadedUser(testUser)),
      build: () {
        when(
          mockUpdateUserColor.call(any),
        ).thenAnswer((_) async => Left(UnexpectedFailure('Save failed')));

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const UpdateUserColorEvent('#FF5722'));
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserError>().having(
          (state) => state.message,
          'message',
          contains('Save failed'),
        ),
      ],
    );

    // ─────────────────────────────────────────────────────────
    // Tema
    // ─────────────────────────────────────────────────────────

    blocTest<UserBloc, UserState>(
      'initial LoadProfile emits UserLoaded with themeMode=system',
      build: () {
        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Right(testUser));

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having(
              (state) => state.themeMode,
              'themeMode',
              AppThemeMode.system,
            )
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
    );

    blocTest<UserBloc, UserState>(
      'LoadProfile usa AppThemeMode.system cuando no hay estado previo ni SharedPreferences',
      setUp: () async {
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();

        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having(
              (state) => state.themeMode,
              'themeMode',
              AppThemeMode.system,
            )
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
    );

    blocTest<UserBloc, UserState>(
      'LoadProfile preserva themeMode del estado anterior',
      setUp: () {
        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      seed: () =>
          UserLoaded(loadedUser(testUser), themeMode: AppThemeMode.dark),
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((state) => state.themeMode, 'themeMode', AppThemeMode.dark)
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to dark changes themeMode in state',
      seed: () => UserLoaded(loadedUser(testUser)),
      build: buildBloc,
      act: (bloc) {
        bloc.add(const UpdateThemeMode(AppThemeMode.dark));
      },
      expect: () => [
        isA<UserLoaded>()
            .having((state) => state.themeMode, 'themeMode', AppThemeMode.dark)
            .having((state) => state.user, 'user', loadedUser(testUser)),
      ],
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to dark persists in SharedPreferences',
      seed: () => UserLoaded(loadedUser(testUser)),
      build: buildBloc,
      act: (bloc) {
        bloc.add(const UpdateThemeMode(AppThemeMode.dark));
      },
      verify: (_) async {
        final preferences = await SharedPreferences.getInstance();

        expect(preferences.getString('theme_mode'), equals('dark'));
      },
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to light changes themeMode in state',
      seed: () => UserLoaded(loadedUser(testUser)),
      build: buildBloc,
      act: (bloc) {
        bloc.add(const UpdateThemeMode(AppThemeMode.light));
      },
      expect: () => [
        isA<UserLoaded>()
            .having((state) => state.themeMode, 'themeMode', AppThemeMode.light)
            .having((state) => state.user, 'user', loadedUser(testUser)),
      ],
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to system changes themeMode in state',
      seed: () =>
          UserLoaded(loadedUser(testUser), themeMode: AppThemeMode.dark),
      build: buildBloc,
      act: (bloc) {
        bloc.add(const UpdateThemeMode(AppThemeMode.system));
      },
      expect: () => [
        isA<UserLoaded>()
            .having(
              (state) => state.themeMode,
              'themeMode',
              AppThemeMode.system,
            )
            .having((state) => state.user, 'user', loadedUser(testUser)),
      ],
    );

    // ─────────────────────────────────────────────────────────
    // Auto-creación de perfil
    // ─────────────────────────────────────────────────────────

    blocTest<UserBloc, UserState>(
      'creates default User when LoadProfile returns no user',
      build: () {
        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Left(CacheFailure('No user profile found')));

        when(mockUserRepository.createUser(any)).thenAnswer((_) async {});

        final defaultPersistedUser = testUser.copyWith(
          name: 'Mi dispositivo',
          color: '#2196F3',
          deviceType: 'android',
        );

        when(
          mockUserRepository.getUserProfile(),
        ).thenAnswer((_) async => defaultPersistedUser);

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((state) => state.user.name, 'name', 'Mi dispositivo')
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
      verify: (_) {
        verify(
          mockUserRepository.createUser(
            argThat(
              predicate(
                (value) =>
                    value is User &&
                    value.name == 'Mi dispositivo' &&
                    value.color == '#2196F3' &&
                    value.deviceType == 'android',
              ),
            ),
          ),
        ).called(1);
      },
    );

    // ─────────────────────────────────────────────────────────
    // UUID estable
    // ─────────────────────────────────────────────────────────

    blocTest<UserBloc, UserState>(
      'PR4: UUID se reusa de SharedPreferences al recrear perfil default',
      setUp: () async {
        SharedPreferences.setMockInitialValues({
          'device_uuid': 'persisted-uuid-999',
        });

        prefs = await SharedPreferences.getInstance();
      },
      build: () {
        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Left(CacheFailure('No user profile found')));

        when(mockUserRepository.createUser(any)).thenAnswer((_) async {});

        final persisted = testUser.copyWith(
          uuid: 'persisted-uuid-999',
          name: 'Mi dispositivo',
        );

        when(
          mockUserRepository.getUserProfile(),
        ).thenAnswer((_) async => persisted);

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((state) => state.user.uuid, 'uuid', 'persisted-uuid-999')
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
      verify: (_) {
        verify(
          mockUserRepository.createUser(
            argThat(
              predicate(
                (value) => value is User && value.uuid == 'persisted-uuid-999',
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<UserBloc, UserState>(
      'PR4: genera UUID nuevo y lo guarda en SharedPreferences si no existe',
      setUp: () async {
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
      },
      build: () {
        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Left(CacheFailure('No user profile found')));

        when(mockUserRepository.createUser(any)).thenAnswer((_) async {});

        when(mockUserRepository.getUserProfile()).thenAnswer((
          invocation,
        ) async {
          final savedUuid = prefs.getString('device_uuid');

          return testUser.copyWith(uuid: savedUuid, name: 'Mi dispositivo');
        });

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>().having(
          (state) => state.user.localNodeId,
          'localNodeId',
          99,
        ),
      ],
      verify: (_) async {
        final preferences = await SharedPreferences.getInstance();

        final savedUuid = preferences.getString('device_uuid');

        expect(savedUuid, isNotNull);
        expect(savedUuid, isNotEmpty);

        expect(
          savedUuid,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
      },
    );

    // ─────────────────────────────────────────────────────────
    // Failure differentiation
    // ─────────────────────────────────────────────────────────

    blocTest<UserBloc, UserState>(
      'PR4: NO crea perfil default cuando LoadProfile falla con DatabaseFailure',
      build: () {
        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Left(DatabaseFailure('DB corrupta')));

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserError>().having(
          (state) => state.message,
          'message',
          contains('DB corrupta'),
        ),
      ],
      verify: (_) {
        verifyNever(mockUserRepository.createUser(any));
      },
    );

    blocTest<UserBloc, UserState>(
      'PR4: NO crea perfil default cuando LoadProfile falla con UnexpectedFailure',
      build: () {
        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Left(UnexpectedFailure('Error inesperado')));

        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserError>().having(
          (state) => state.message,
          'message',
          contains('Error inesperado'),
        ),
      ],
      verify: (_) {
        verifyNever(mockUserRepository.createUser(any));
      },
    );

    // ─────────────────────────────────────────────────────────
    // myDeviceUuid
    // ─────────────────────────────────────────────────────────

    test(
      'SC-PR6b-005: myDeviceUuid retorna el UUID de SharedPreferences',
      () async {
        SharedPreferences.setMockInitialValues({
          'device_uuid': 'my-persisted-uuid-123',
        });

        final preferences = await SharedPreferences.getInstance();

        final bloc = UserBloc(
          getProfile: mockGetUserProfile,
          updateName: mockUpdateUserName,
          updateColor: mockUpdateUserColor,
          ensureLocalNode: mockEnsureLocalNode,
          userRepository: mockUserRepository,
          prefs: preferences,
        );

        expect(bloc.myDeviceUuid, equals('my-persisted-uuid-123'));

        await bloc.close();
      },
    );

    test(
      'SC-PR6b-005: myDeviceUuid retorna null sin UUID en SharedPreferences',
      () async {
        SharedPreferences.setMockInitialValues({});

        final preferences = await SharedPreferences.getInstance();

        final bloc = UserBloc(
          getProfile: mockGetUserProfile,
          updateName: mockUpdateUserName,
          updateColor: mockUpdateUserColor,
          ensureLocalNode: mockEnsureLocalNode,
          userRepository: mockUserRepository,
          prefs: preferences,
        );

        expect(bloc.myDeviceUuid, isNull);

        await bloc.close();
      },
    );

    // ─────────────────────────────────────────────────────────
    // Tema persistido
    // ─────────────────────────────────────────────────────────

    blocTest<UserBloc, UserState>(
      'PR4: lee themeMode de SharedPreferences en inicio fresco (dark)',
      setUp: () async {
        SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});

        prefs = await SharedPreferences.getInstance();

        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((state) => state.themeMode, 'themeMode', AppThemeMode.dark)
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
    );

    blocTest<UserBloc, UserState>(
      'PR4: lee themeMode de SharedPreferences en inicio fresco (light)',
      setUp: () async {
        SharedPreferences.setMockInitialValues({'theme_mode': 'light'});

        prefs = await SharedPreferences.getInstance();

        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((state) => state.themeMode, 'themeMode', AppThemeMode.light)
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
    );

    blocTest<UserBloc, UserState>(
      'PR4: usa AppThemeMode.system cuando no hay tema guardado en SharedPreferences',
      setUp: () async {
        SharedPreferences.setMockInitialValues({});

        prefs = await SharedPreferences.getInstance();

        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having(
              (state) => state.themeMode,
              'themeMode',
              AppThemeMode.system,
            )
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
    );

    blocTest<UserBloc, UserState>(
      'PR4: preserva themeMode del estado sobre SharedPreferences',
      setUp: () async {
        SharedPreferences.setMockInitialValues({'theme_mode': 'light'});

        prefs = await SharedPreferences.getInstance();

        when(
          mockGetUserProfile.call(any),
        ).thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      seed: () =>
          UserLoaded(loadedUser(testUser), themeMode: AppThemeMode.dark),
      act: (bloc) {
        bloc.add(const LoadProfile());
      },
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((state) => state.themeMode, 'themeMode', AppThemeMode.dark)
            .having((state) => state.user.localNodeId, 'localNodeId', 99),
      ],
    );
  });
}
