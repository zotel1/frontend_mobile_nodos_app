import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/utils/app_theme_mode.dart';
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

    // ─── Tema (AppThemeMode) ──────────────────────────────────

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
          AppThemeMode.system,
        ),
      ],
    );

    blocTest<UserBloc, UserState>(
      // PR4: En inicio fresco sin SharedPreferences configurado,
      // PR5a: el default es AppThemeMode.system.
      'LoadProfile usa AppThemeMode.system cuando no hay estado previo ni SharedPreferences',
      setUp: () async {
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', AppThemeMode.system)
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
      seed: () => UserLoaded(testUser, themeMode: AppThemeMode.dark),
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', AppThemeMode.dark)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to dark changes themeMode in state',
      seed: () => UserLoaded(testUser),
      build: buildBloc,
      act: (bloc) => bloc.add(const UpdateThemeMode(AppThemeMode.dark)),
      expect: () => [
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', AppThemeMode.dark)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to dark persists in SharedPreferences',
      seed: () => UserLoaded(testUser),
      build: buildBloc,
      act: (bloc) => bloc.add(const UpdateThemeMode(AppThemeMode.dark)),
      verify: (_) async {
        final p = await SharedPreferences.getInstance();
        expect(p.getString('theme_mode'), equals('dark'));
      },
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to light changes themeMode in state',
      seed: () => UserLoaded(testUser),
      build: buildBloc,
      act: (bloc) => bloc.add(const UpdateThemeMode(AppThemeMode.light)),
      expect: () => [
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', AppThemeMode.light)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<UserBloc, UserState>(
      'UpdateThemeMode to system changes themeMode in state',
      seed: () => UserLoaded(testUser, themeMode: AppThemeMode.dark),
      build: buildBloc,
      act: (bloc) => bloc.add(const UpdateThemeMode(AppThemeMode.system)),
      expect: () => [
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', AppThemeMode.system)
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

    // ─── PR4: UUID una sola vez por instalación ─────────
    //
    // QUÉ: el UUID del dispositivo debe persistir en SharedPreferences
    // bajo la clave 'device_uuid' y reusarse incluso si el perfil se
    // elimina y se recrea. Esto garantiza identidad estable del
    // dispositivo entre reinstalaciones de perfil.
    //
    // POR QUÉ: antes _onLoadProfile generaba un UUID nuevo cada vez
    // que el perfil no existía. Si un bug borraba la tabla users, el
    // dispositivo cambiaba de identidad → otros nodos lo veían como
    // un dispositivo nuevo, perdiendo todo el historial de enlaces.

    blocTest<UserBloc, UserState>(
      'PR4: UUID se reusa de SharedPreferences al recrear perfil default',
      setUp: () async {
        // Pre-poblar SharedPreferences con un UUID previo.
        SharedPreferences.setMockInitialValues({
          'device_uuid': 'persisted-uuid-999',
        });
        prefs = await SharedPreferences.getInstance();
      },
      build: () {
        var callCount = 0;
        when(mockGetUserProfile.call(any)).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return Left(CacheFailure('No user profile found'));
          }
          return Right(testUser.copyWith(
            uuid: 'persisted-uuid-999',
            name: 'Mi dispositivo',
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
          (s) => s.user.uuid,
          'uuid',
          'persisted-uuid-999',
        ),
      ],
      verify: (_) {
        // Verifica que el User creado usa el UUID persistido, no uno nuevo.
        verify(mockUserRepository.createUser(argThat(
          predicate((u) =>
              u is User &&
              u.uuid == 'persisted-uuid-999'),
        ))).called(1);
      },
    );

    blocTest<UserBloc, UserState>(
      'PR4: genera UUID nuevo y lo guarda en SharedPreferences si no existe',
      setUp: () async {
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
      },
      build: () {
        var callCount = 0;
        when(mockGetUserProfile.call(any)).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return Left(CacheFailure('No user profile found'));
          }
          return Right(testUser.copyWith(name: 'Mi dispositivo'));
        });
        when(mockUserRepository.createUser(any))
            .thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>(),
      ],
      verify: (_) async {
        // Verifica que el UUID se guardó en SharedPreferences.
        final p = await SharedPreferences.getInstance();
        final savedUuid = p.getString('device_uuid');
        expect(savedUuid, isNotNull);
        expect(savedUuid, isNotEmpty);
        // Debe ser un UUID v4 válido (formato xxxxxxxx-xxxx-4xxx-...).
        expect(savedUuid, matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        )));
      },
    );

    // ─── PR4: Diferenciación de Failure en _onLoadProfile ──
    //
    // QUÉ: _onLoadProfile solo debe crear el perfil default cuando
    // el fallo es CacheFailure('No user profile found'). Otros fallos
    // (DatabaseFailure, UnexpectedFailure) deben emitir UserError.
    //
    // POR QUÉ: antes cualquier Left(Failure) disparaba la creación
    // de un perfil default. Si la DB estaba corrupta (DatabaseFailure),
    // el BLoC silenciosamente creaba un perfil fantasma que no se
    // persistía → estado inconsistente.

    blocTest<UserBloc, UserState>(
      'PR4: NO crea perfil default cuando LoadProfile falla con DatabaseFailure',
      build: () {
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Left(DatabaseFailure('DB corrupta')));
        return buildBloc();
      },
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserError>().having(
          (s) => s.message,
          'message',
          contains('DB corrupta'),
        ),
      ],
      verify: (_) {
        // Verifica que NUNCA se llamó a createUser.
        verifyNever(mockUserRepository.createUser(any));
      },
    );

    blocTest<UserBloc, UserState>(
      'PR4: NO crea perfil default cuando LoadProfile falla con UnexpectedFailure',
      build: () {
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Left(UnexpectedFailure('Error inesperado')));
        return buildBloc();
      },
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserError>().having(
          (s) => s.message,
          'message',
          contains('Error inesperado'),
        ),
      ],
      verify: (_) {
        verifyNever(mockUserRepository.createUser(any));
      },
    );

    // ─── PR6b: myDeviceUuid getter ─────────────────────────────
    // QUÉ: verifica que UserBloc expone el UUID del dispositivo
    // del usuario a través de un getter público myDeviceUuid.
    // POR QUÉ: otros componentes (visualization, nodes) necesitan
    // el UUID para marcar el self-node en el grafo. Sin este getter,
    // el UUID queda encapsulado en SharedPreferences y es inaccesible.
    //
    // SC-PR6b-005: UserBloc expone myDeviceUuid desde SharedPreferences.

    test('SC-PR6b-005: myDeviceUuid retorna el UUID de SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({
        'device_uuid': 'my-persisted-uuid-123',
      });
      final p = await SharedPreferences.getInstance();

      when(mockGetUserProfile.call(any))
          .thenAnswer((_) async => Right(testUser));

      final bloc = UserBloc(
        getProfile: mockGetUserProfile,
        updateName: mockUpdateUserName,
        updateColor: mockUpdateUserColor,
        userRepository: mockUserRepository,
        prefs: p,
      );

      expect(bloc.myDeviceUuid, equals('my-persisted-uuid-123'));
      bloc.close();
    });

    test('SC-PR6b-005: myDeviceUuid retorna null sin UUID en SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();

      when(mockGetUserProfile.call(any))
          .thenAnswer((_) async => Right(testUser));

      final bloc = UserBloc(
        getProfile: mockGetUserProfile,
        updateName: mockUpdateUserName,
        updateColor: mockUpdateUserColor,
        userRepository: mockUserRepository,
        prefs: p,
      );

      expect(bloc.myDeviceUuid, isNull);
      bloc.close();
    });

    // ─── PR4: Tema persistido desde SharedPreferences en inicio ──
    //
    // QUÉ: al iniciar la app (UserInitial), _onLoadProfile debe leer
    // el tema guardado en SharedPreferences bajo 'theme_mode', no
    // usar AppThemeMode.system por defecto.
    //
    // POR QUÉ: el usuario configura su tema en Settings y espera que
    // persista entre reinicios. Antes, _onLoadProfile siempre usaba
    // AppThemeMode.system en primera carga (UserInitial), ignorando la
    // preferencia guardada. El tema solo se preservaba en memoria
    // durante la sesión actual.

    blocTest<UserBloc, UserState>(
      'PR4: lee themeMode de SharedPreferences en inicio fresco (dark)',
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
            .having((s) => s.themeMode, 'themeMode', AppThemeMode.dark)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<UserBloc, UserState>(
      'PR4: lee themeMode de SharedPreferences en inicio fresco (light)',
      setUp: () async {
        SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
        prefs = await SharedPreferences.getInstance();
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', AppThemeMode.light)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<UserBloc, UserState>(
      'PR4: usa AppThemeMode.system cuando no hay tema guardado en SharedPreferences',
      setUp: () async {
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', AppThemeMode.system)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    // PR4: Tema desde SP respeta estado previo si ya está cargado.
    // Si el estado anterior es UserLoaded con dark, se preserva dark
    // incluso si SP dice light (el estado en memoria tiene prioridad).
    blocTest<UserBloc, UserState>(
      'PR4: preserva themeMode del estado sobre SharedPreferences',
      setUp: () async {
        SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
        prefs = await SharedPreferences.getInstance();
        when(mockGetUserProfile.call(any))
            .thenAnswer((_) async => Right(testUser));
      },
      build: buildBloc,
      seed: () => UserLoaded(testUser, themeMode: AppThemeMode.dark),
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        isA<UserLoading>(),
        isA<UserLoaded>()
            .having((s) => s.themeMode, 'themeMode', AppThemeMode.dark)
            .having((s) => s.user, 'user', testUser),
      ],
    );
  });
}
