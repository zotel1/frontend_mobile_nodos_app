import 'ble_graph_pipeline_test_support.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test(
    'BUG-001 integration: conexión self → remoto persiste edge con Node.id reales',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      // ─────────────────────────────────────────────────────
      // 1. Crear repositorios reales
      // ─────────────────────────────────────────────────────

      final nodeDs = NodeDriftDataSource(db);
      final nodeRepo = NodeRepositoryImpl(nodeDs);

      final userDs = UserDriftDataSource(db);
      final userRepo = UserRepositoryImpl(userDs);

      final ensureLocalNode = EnsureLocalNode(
        nodeRepository: nodeRepo,
        userRepository: userRepo,
      );

      SharedPreferences.setMockInitialValues({});

      final prefs = await SharedPreferences.getInstance();

      final userBloc = UserBloc(
        getProfile: GetUserProfile(userRepo),
        updateName: UpdateUserName(userRepo),
        updateColor: UpdateUserColor(userRepo),
        ensureLocalNode: ensureLocalNode,
        userRepository: userRepo,
        prefs: prefs,
      );

      // ─────────────────────────────────────────────────────
      // 2. Crear perfil + self-node persistente
      // ─────────────────────────────────────────────────────

      userBloc.add(const LoadProfile());

      await userBloc.stream.firstWhere((state) => state is UserLoaded);

      final loadedUser = (userBloc.state as UserLoaded).user;

      expect(
        loadedUser.localNodeId,
        isNotNull,
        reason: 'El usuario debe apuntar al self-node persistente',
      );

      final selfId = loadedUser.localNodeId!;

      final selfNode = await nodeRepo.getSelfNode();

      expect(selfNode, isNotNull);
      expect(selfNode!.id, selfId);
      expect(selfNode.isSelf, isTrue);
      expect(selfNode.id, isNot(-1));

      // ─────────────────────────────────────────────────────
      // 3. Crear nodo remoto real en SQLite
      // ─────────────────────────────────────────────────────

      const remoteBleAddress = 'AA:BB:CC:DD:EE:99';

      final now = DateTime.now();

      await nodeRepo.upsertNode(
        Node(
          bleAddress: remoteBleAddress,
          name: 'Reloj',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [-45],
          connectable: true,
          isSelf: false,
        ),
      );

      final remoteNode = await nodeRepo.getNodeByBleAddress(remoteBleAddress);

      expect(remoteNode, isNotNull);
      expect(remoteNode!.id, isNotNull);
      expect(remoteNode.isSelf, isFalse);

      final remoteId = remoteNode.id!;

      // Garantía explícita:
      // self y remoto deben tener IDs SQLite diferentes.
      expect(selfId, isNot(remoteId));

      // ─────────────────────────────────────────────────────
      // 4. Usar BleConnectionRepositoryImpl REAL
      // ─────────────────────────────────────────────────────

      final gatt = TestBleGattDataSource();

      final connectionRepo = BleConnectionRepositoryImpl(gatt: gatt, db: db);

      final connectionBloc = BleConnectionBloc(
        connectionRepository: connectionRepo,
        nodeRepository: nodeRepo,
        userRepository: TestUserRepository(),
        activeGraphExchange: ActiveGraphExchangeService(
          nodeRepository: nodeRepo,
          userRepository: TestUserRepository(),
          bleRepository: TestBleRepository(),
        ),
        remoteRelationRepository: TestRemoteRelationRepository(),
      );

      // ─────────────────────────────────────────────────────
      // 5. Conectar usando el Node.id local real
      // ─────────────────────────────────────────────────────

      connectionBloc.add(ConnectToDevice(remoteBleAddress, myNodeId: selfId));

      await connectionBloc.stream.firstWhere(
        (state) => state is ConnectionInserted,
      );

      // ─────────────────────────────────────────────────────
      // 6. Verificar persistencia en tabla connections
      // ─────────────────────────────────────────────────────

      final connections = await db.select(db.connections).get();

      expect(
        connections,
        hasLength(1),
        reason: 'La conexión exitosa debe persistirse una sola vez',
      );

      final persistedConnection = connections.single;

      expect(
        persistedConnection.fromNodeId,
        selfId,
        reason:
            'fromNodeId debe ser el Node.id persistente del dispositivo local',
      );

      expect(
        persistedConnection.toNodeId,
        remoteId,
        reason:
            'toNodeId debe ser el Node.id persistente del dispositivo remoto',
      );

      // Protección contra la regresión original.
      expect(persistedConnection.fromNodeId, isNot(-1));

      // ─────────────────────────────────────────────────────
      // 7. Crear sesión con el nodo remoto
      // ─────────────────────────────────────────────────────

      final scanRepo = ScanSessionRepositoryImpl(db);

      final sessionId = await scanRepo.startSession();

      await scanRepo.addNodesToSession(sessionId, [remoteId]);

      // El self-node no tiene por qué aparecer en scan_session_nodes.
      //
      // GraphRepositoryImpl debe agregarlo mediante getSelfNode().
      final sessionRows = await (db.select(
        db.scanSessionNodes,
      )..where((row) => row.sessionId.equals(sessionId))).get();

      expect(sessionRows.map((row) => row.nodeId), contains(remoteId));

      expect(
        sessionRows.map((row) => row.nodeId),
        isNot(contains(selfId)),
        reason:
            'El self-node no debe depender de haber sido detectado por el scanner',
      );

      // ─────────────────────────────────────────────────────
      // 8. Construir grafo
      // ─────────────────────────────────────────────────────

      final graphRepo = GraphRepositoryImpl(
        nodeRepo,
        db,
        TestRemoteRelationRepository(),
      );

      final layout = await graphRepo.buildGraph(
        sessionId,
        myDeviceUuid: loadedUser.uuid,
        userName: loadedUser.name,
        userColor: loadedUser.color,
      );

      // ─────────────────────────────────────────────────────
      // 9. Verificar nodos visibles
      // ─────────────────────────────────────────────────────

      final graphSelf = layout.nodes.firstWhere((node) => node.id == selfId);

      final graphRemote = layout.nodes.firstWhere(
        (node) => node.id == remoteId,
      );

      expect(graphSelf.isSelf, isTrue);
      expect(graphRemote.isSelf, isFalse);

      // ─────────────────────────────────────────────────────
      // 10. Verificar edge self → remoto
      // ─────────────────────────────────────────────────────

      final directEdge = layout.edges.firstWhere(
        (edge) =>
            edge.edgeType == EdgeType.direct &&
            edge.fromId == selfId &&
            edge.toId == remoteId,
      );

      expect(directEdge.fromId, selfId);
      expect(directEdge.toId, remoteId);

      // Protección adicional:
      // no debe existir ninguna arista contra id=-1.
      expect(
        layout.edges.any((edge) => edge.fromId == -1 || edge.toId == -1),
        isFalse,
      );

      // ─────────────────────────────────────────────────────
      // Cleanup
      // ─────────────────────────────────────────────────────

      await connectionBloc.close();
      await userBloc.close();
      await db.close();
    },
  );

  // ━━━━━━━━━━━━━━━━━ User / Onboarding ━━━━━━━━━━━━━━━━━━━━━━━

  test(
    'IT3: Connect → GATT connected → disconnect → verify state transitions',
    tags: ['integration'],
    () {
      fakeAsync((async) async {
        final db = AppDatabase.inMemory();

        final nodeDs = NodeDriftDataSource(db);
        final nodeRepo = NodeRepositoryImpl(nodeDs);

        final connRepo = TestBleConnectionRepository();

        final bloc = BleConnectionBloc(
          connectionRepository: connRepo,
          nodeRepository: nodeRepo,
          userRepository: TestUserRepository(),
          activeGraphExchange: ActiveGraphExchangeService(
            nodeRepository: nodeRepo,
            userRepository: TestUserRepository(),
            bleRepository: TestBleRepository(),
          ),
          remoteRelationRepository: TestRemoteRelationRepository(),
        );

        const remoteId = 'AA:BB:CC:DD:EE:FF';

        expect(bloc.state, isA<BleConnectionInitial>());

        bloc.add(const ConnectToDevice(remoteId, myNodeId: 1));

        async.flushMicrotasks();

        expect(bloc.state, isA<BleConnected>());

        bloc.add(const DisconnectDevice(remoteId));

        async.flushMicrotasks();

        expect(
          bloc.state,
          isA<BleConnectionInitial>(),
          reason: 'After disconnect, must be Initial',
        );

        await bloc.close();
        connRepo.dispose();
        await db.close();
      });
    },
  );

  test(
    'IT11: BleConnectionBloc full lifecycle: connecting → connected → disconnected',
    tags: ['integration'],
    () {
      fakeAsync((async) async {
        final db = AppDatabase.inMemory();

        final nodeDs = NodeDriftDataSource(db);

        final nodeRepo = NodeRepositoryImpl(nodeDs);

        final connRepo = TestBleConnectionRepository();

        final bloc = BleConnectionBloc(
          connectionRepository: connRepo,
          nodeRepository: nodeRepo,
          userRepository: TestUserRepository(),
          activeGraphExchange: ActiveGraphExchangeService(
            nodeRepository: nodeRepo,
            userRepository: TestUserRepository(),
            bleRepository: TestBleRepository(),
          ),
          remoteRelationRepository: TestRemoteRelationRepository(),
        );

        const remoteId = '11:22:33:44:55:66';

        expect(bloc.state, isA<BleConnectionInitial>());

        bloc.add(const ConnectToDevice(remoteId, myNodeId: 1));

        async.flushMicrotasks();

        expect(bloc.state, isA<BleConnected>());

        connRepo.emitConnected(remoteId);

        async.flushMicrotasks();

        bloc.add(const DisconnectDevice(remoteId));

        async.flushMicrotasks();

        expect(bloc.state, isA<BleConnectionInitial>());

        await bloc.close();
        connRepo.dispose();
        await db.close();
      });
    },
  );
}
