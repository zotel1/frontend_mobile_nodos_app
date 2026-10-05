import 'ble_graph_pipeline_test_support.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test(
    'IT2: Onboarding → createProfile → persist → reload verify identity',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      final bloc = await makeUserBloc(db);

      bloc.add(const LoadProfile());

      await bloc.stream.firstWhere((state) => state is UserLoaded);

      final user = (bloc.state as UserLoaded).user;

      expect(user.name, 'Mi dispositivo');
      expect(user.color, '#2196F3');
      expect(user.localNodeId, isNotNull);

      final uuid1 = user.uuid;

      expect(uuid1, isNotEmpty);

      bloc.add(const LoadProfile());

      await bloc.stream.firstWhere(
        (state) => state is UserLoaded && state.user.uuid == uuid1,
      );

      final reloaded = (bloc.state as UserLoaded).user;

      expect(reloaded.uuid, uuid1);
      expect(reloaded.name, 'Mi dispositivo');
      expect(reloaded.localNodeId, user.localNodeId);

      await bloc.close();
      await db.close();
    },
  );

  test(
    'IT4: Set dark mode → restart UserBloc → verify ThemeMode persists',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      SharedPreferences.setMockInitialValues({});

      var prefs = await SharedPreferences.getInstance();

      final ds = UserDriftDataSource(db);
      final repo = UserRepositoryImpl(ds);

      final nodeRepo = NodeRepositoryImpl(NodeDriftDataSource(db));

      final ensureLocalNode = EnsureLocalNode(
        nodeRepository: nodeRepo,
        userRepository: repo,
      );

      var bloc = UserBloc(
        getProfile: GetUserProfile(repo),
        updateName: UpdateUserName(repo),
        updateColor: UpdateUserColor(repo),
        ensureLocalNode: ensureLocalNode,
        userRepository: repo,
        prefs: prefs,
      );

      bloc.add(const LoadProfile());

      await bloc.stream.firstWhere((state) => state is UserLoaded);

      bloc.add(const UpdateThemeMode(AppThemeMode.dark));

      await Future.microtask(() {});

      expect((bloc.state as UserLoaded).themeMode, AppThemeMode.dark);

      expect(prefs.getString('theme_mode'), 'dark');

      await bloc.close();

      prefs = await SharedPreferences.getInstance();

      bloc = UserBloc(
        getProfile: GetUserProfile(repo),
        updateName: UpdateUserName(repo),
        updateColor: UpdateUserColor(repo),
        ensureLocalNode: ensureLocalNode,
        userRepository: repo,
        prefs: prefs,
      );

      bloc.add(const LoadProfile());

      await bloc.stream.firstWhere((state) => state is UserLoaded);

      expect(
        (bloc.state as UserLoaded).themeMode,
        AppThemeMode.dark,
        reason: 'Theme must survive BLoC restart',
      );

      await bloc.close();
      await db.close();
    },
  );

  // ━━━━━━━━━━━━━━━━━ Self-node & Dedup ━━━━━━━━━━━━━━━━━━━━━━━

  test(
    'IT8: Empty DB → UserBloc creates default user and persistent self-node',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      SharedPreferences.setMockInitialValues({});

      final prefs = await SharedPreferences.getInstance();

      final ds = UserDriftDataSource(db);

      final user = await ds.getUser();

      expect(user, isNull);

      final repo = UserRepositoryImpl(ds);

      final nodeRepo = NodeRepositoryImpl(NodeDriftDataSource(db));

      final ensureLocalNode = EnsureLocalNode(
        nodeRepository: nodeRepo,
        userRepository: repo,
      );

      final bloc = UserBloc(
        getProfile: GetUserProfile(repo),
        updateName: UpdateUserName(repo),
        updateColor: UpdateUserColor(repo),
        ensureLocalNode: ensureLocalNode,
        userRepository: repo,
        prefs: prefs,
      );

      bloc.add(const LoadProfile());

      await bloc.stream.firstWhere((state) => state is UserLoaded);

      final loaded = (bloc.state as UserLoaded).user;

      expect(loaded.name, 'Mi dispositivo');

      expect(loaded.uuid, isNotEmpty);

      expect(loaded.color, '#2196F3');

      expect(
        loaded.localNodeId,
        isNotNull,
        reason: 'UserLoaded debe tener asociado un self-node persistente',
      );

      final selfNode = await nodeRepo.getSelfNode();

      expect(selfNode, isNotNull);
      expect(selfNode!.id, loaded.localNodeId);
      expect(selfNode.isSelf, isTrue);
      expect(selfNode.id, isNot(-1));

      await bloc.close();
      await db.close();
    },
  );

  // ━━━━━━━━━━━━━━━━━ Session + Edges ━━━━━━━━━━━━━━━━━━━━━━━━━

  test(
    'IT12: Onboarding + Settings roundtrip: set name/color → reload → verify',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      final bloc = await makeUserBloc(db);

      bloc.add(const LoadProfile());

      await bloc.stream.firstWhere((state) => state is UserLoaded);

      bloc.add(const UpdateUserNameEvent('Zotel'));

      await bloc.stream.firstWhere(
        (state) => state is UserLoaded && state.user.name == 'Zotel',
      );

      bloc.add(const UpdateUserColorEvent('#FF0000'));

      await bloc.stream.firstWhere(
        (state) => state is UserLoaded && state.user.color == '#FF0000',
      );

      bloc.add(const LoadProfile());

      await bloc.stream.firstWhere((state) => state is UserLoaded);

      final user = (bloc.state as UserLoaded).user;

      expect(user.name, 'Zotel', reason: 'Name must survive reload');

      expect(user.color, '#FF0000', reason: 'Color must survive reload');

      expect(user.localNodeId, isNotNull);

      await bloc.close();
      await db.close();
    },
  );

  test(
    'IT13: Theme survives name update (dark → updateName → theme stays dark)',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      final bloc = await makeUserBloc(db);

      bloc.add(const LoadProfile());

      await bloc.stream.firstWhere((state) => state is UserLoaded);

      bloc.add(const UpdateThemeMode(AppThemeMode.dark));

      await Future.microtask(() {});

      expect((bloc.state as UserLoaded).themeMode, AppThemeMode.dark);

      bloc.add(const UpdateUserNameEvent('Nuevo'));

      await bloc.stream.firstWhere(
        (state) => state is UserLoaded && state.user.name == 'Nuevo',
      );

      expect(
        (bloc.state as UserLoaded).themeMode,
        AppThemeMode.dark,
        reason: 'ThemeMode must NOT reset on name update',
      );

      await bloc.close();
      await db.close();
    },
  );

  test(
    'IT19: DeviceClassifier integration — classify returns correct deviceType',
    tags: ['integration'],
    () {
      const hrUuid = '0000180d-0000-1000-8000-00805f9b34fb';

      const batUuid = '0000180f-0000-1000-8000-00805f9b34fb';

      const nodosUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

      expect(DeviceClassifier.classify([hrUuid], null), 'Reloj/Fitness');

      expect(
        DeviceClassifier.classify([nodosUuid, hrUuid], null),
        'Nodo',
        reason: 'Nodos service UUID must take priority',
      );

      expect(DeviceClassifier.classify([batUuid], null), 'Batería');

      expect(
        DeviceClassifier.classify(['unknown-uuid'], 0x004C),
        'Apple (Desconocido)',
      );

      expect(DeviceClassifier.classify(['unknown'], null), isNull);
    },
  );
}
