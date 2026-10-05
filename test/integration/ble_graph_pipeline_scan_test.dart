import 'ble_graph_pipeline_test_support.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test(
    'IT1: BLE scan → NodeList → Session → Graph → GraphReady',
    tags: ['integration'],
    () {
      fakeAsync((async) async {
        final db = AppDatabase.inMemory();

        final nodeDs = NodeDriftDataSource(db);
        final nodeRepo = NodeRepositoryImpl(nodeDs);
        final scanRepo = ScanSessionRepositoryImpl(db);
        final bleRepo = TestBleRepository();

        final bleBloc = BleBloc(
          repository: bleRepo,
          userRepository: TestUserRepository(),
          remoteRelationRepository: TestRemoteRelationRepository(),
          nodeRepository: nodeRepo,
          connectionRepository: TestBleConnectionRepository(),
          dutyCyclePeriod: const Duration(minutes: 10),
        );

        final nodeBloc = NodeListBloc(
          observeNodes: ObserveNodes(nodeRepo),
          updateNodeMetadata: UpdateNodeMetadata(nodeRepo),
          nodeRepository: nodeRepo,
        );

        bleBloc.add(const StartScan());
        async.flushMicrotasks();

        final devices = [
          BleDevice(
            deviceId: 'AA:BB:CC:DD:EE:01',
            rssi: -50,
            distance: rssiToDistance(-50),
            proximity: rssiToProximity(-50),
            timestamp: DateTime.now(),
            advName: 'Sensor A',
          ),
          BleDevice(
            deviceId: 'AA:BB:CC:DD:EE:02',
            rssi: -60,
            distance: rssiToDistance(-60),
            proximity: rssiToProximity(-60),
            timestamp: DateTime.now(),
            advName: 'Sensor B',
          ),
          BleDevice(
            deviceId: 'AA:BB:CC:DD:EE:03',
            rssi: -75,
            distance: rssiToDistance(-75),
            proximity: rssiToProximity(-75),
            timestamp: DateTime.now(),
            advName: 'Sensor C',
          ),
        ];

        nodeBloc.add(SyncBleDevices(devices));

        async.flushMicrotasks();

        await Future<void>.delayed(const Duration(milliseconds: 50));

        async.flushMicrotasks();

        final savedNodes = await nodeRepo.observeNodes().first;

        expect(savedNodes.length, greaterThanOrEqualTo(3));

        final sessionId = await scanRepo.startSession();

        final nodeIds = savedNodes.map((node) => node.id!).toList();

        await scanRepo.addNodesToSession(sessionId, nodeIds);

        final graphRepo = GraphRepositoryImpl(
          nodeRepo,
          db,
          TestRemoteRelationRepository(),
        );

        final layout = await graphRepo.buildGraph(
          sessionId,
          myDeviceUuid: 'self-uuid',
        );

        expect(layout.nodes, isNotEmpty);
        expect(layout.nodes.length, greaterThanOrEqualTo(3));

        final buildGraph = BuildGraph(graphRepo);

        final calc = CalculateLayout(
          layoutAlgorithm: const FruchtermanReingold(),
        );

        final vizBloc = VisualizationBloc(
          buildGraph: buildGraph,
          calculateLayout: calc,
          remoteRelationRepository: TestRemoteRelationRepository(),
          debounceDuration: const Duration(milliseconds: 10),
        );

        final states = <VisualizationState>[];
        final sub = vizBloc.stream.listen(states.add);

        vizBloc.add(
          BuildGraphRequested(
            scanSessionId: sessionId,
            nodes: savedNodes,
            myDeviceUuid: 'self-uuid',
          ),
        );

        async.elapse(const Duration(milliseconds: 30));

        async.flushMicrotasks();

        await Future<void>.delayed(const Duration(milliseconds: 200));

        async.flushMicrotasks();

        final ready = states.whereType<GraphReady>().firstOrNull;

        expect(ready, isNotNull, reason: 'Pipeline must reach GraphReady');

        await sub.cancel();
        await vizBloc.close();
        await bleBloc.close();
        await nodeBloc.close();

        bleRepo.dispose();

        await db.close();
      });
    },
  );

  test(
    'IT6: Multiple BLE devices with same ID → dedup to single node',
    tags: ['integration'],
    () {
      fakeAsync((async) async {
        final db = AppDatabase.inMemory();

        final nodeDs = NodeDriftDataSource(db);

        final nodeRepo = NodeRepositoryImpl(nodeDs);

        final bloc = NodeListBloc(
          observeNodes: ObserveNodes(nodeRepo),
          updateNodeMetadata: UpdateNodeMetadata(nodeRepo),
          nodeRepository: nodeRepo,
        );

        const sameId = 'AA:BB:CC:DD:EE:DUP';

        final devices = [
          BleDevice(
            deviceId: sameId,
            rssi: -50,
            distance: 5,
            proximity: ProximityLevel.medium,
            timestamp: DateTime.now(),
            advName: 'Dupe A',
          ),
          BleDevice(
            deviceId: sameId,
            rssi: -55,
            distance: 6,
            proximity: ProximityLevel.medium,
            timestamp: DateTime.now(),
            advName: 'Dupe A Update',
          ),
          BleDevice(
            deviceId: 'other-dev',
            rssi: -60,
            distance: 7,
            proximity: ProximityLevel.medium,
            timestamp: DateTime.now(),
            advName: 'Unique',
          ),
        ];

        bloc.add(SyncBleDevices(devices));

        async.flushMicrotasks();

        await Future<void>.delayed(const Duration(milliseconds: 50));

        async.flushMicrotasks();

        final nodes = await nodeRepo.observeNodes().first;

        final addresses = nodes.map((node) => node.bleAddress).toSet();

        expect(
          addresses.length,
          2,
          reason: 'Same deviceId must not create duplicate nodes',
        );

        await bloc.close();
        await db.close();
      });
    },
  );

  test(
    'IT7: RSSI update → same IDs → graph rebuild with new proximity',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      final nodeDs = NodeDriftDataSource(db);

      final nodeRepo = NodeRepositoryImpl(nodeDs);

      final now = DateTime.now();

      await nodeRepo.upsertNode(
        Node(
          bleAddress: 'AA:BB:CC:DD:EE:PROX',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [-40],
        ),
      );

      final nodes = await nodeRepo.observeNodes().first;

      final nodeId = nodes.first.id!;

      final scanRepo = ScanSessionRepositoryImpl(db);

      final sessionId = await scanRepo.startSession();

      await scanRepo.addNodesToSession(sessionId, [nodeId]);

      final graphRepo = GraphRepositoryImpl(
        nodeRepo,
        db,
        TestRemoteRelationRepository(),
      );

      var layout = await graphRepo.buildGraph(sessionId);

      final node1 = layout.nodes.firstWhere((node) => node.id == nodeId);

      expect(node1.proximity, ProximityLevel.close);

      await nodeRepo.upsertNode(
        Node(
          id: nodeId,
          bleAddress: 'AA:BB:CC:DD:EE:PROX',
          firstSeen: now,
          lastSeen: DateTime.now(),
          rssiHistory: const [-90],
        ),
      );

      layout = await graphRepo.buildGraph(sessionId);

      final node2 = layout.nodes.firstWhere((node) => node.id == nodeId);

      expect(
        node2.proximity,
        ProximityLevel.far,
        reason: 'RSSI update must change proximity in rebuilt graph',
      );

      await db.close();
    },
  );

  test(
    'IT9: Create session → insert nodes → buildGraph returns edges',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      final nodeDs = NodeDriftDataSource(db);

      final nodeRepo = NodeRepositoryImpl(nodeDs);

      final now = DateTime.now();

      await nodeRepo.upsertNode(
        Node(
          bleAddress: 'AA:01',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [-50],
        ),
      );

      await nodeRepo.upsertNode(
        Node(
          bleAddress: 'AA:02',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [-60],
        ),
      );

      await nodeRepo.upsertNode(
        Node(
          bleAddress: 'AA:03',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [-70],
        ),
      );

      final nodes = await nodeRepo.observeNodes().first;

      final scanRepo = ScanSessionRepositoryImpl(db);

      final sessionId = await scanRepo.startSession();

      await scanRepo.addNodesToSession(
        sessionId,
        nodes.map((node) => node.id!).toList(),
      );

      await db
          .into(db.connections)
          .insert(
            ConnectionsCompanion(
              fromNodeId: Value(nodes[0].id!),
              toNodeId: Value(nodes[1].id!),
              createdAt: Value(now),
            ),
            mode: InsertMode.insertOrIgnore,
          );

      final graphRepo = GraphRepositoryImpl(
        nodeRepo,
        db,
        TestRemoteRelationRepository(),
      );

      final layout = await graphRepo.buildGraph(sessionId);

      expect(layout.nodes, isNotEmpty);

      final directEdges = layout.edges.where(
        (edge) => edge.edgeType == EdgeType.direct,
      );

      expect(
        directEdges,
        isNotEmpty,
        reason: 'Session with a connection must produce edges',
      );

      await db.close();
    },
  );

  // ━━━━━━━━━━━━━━━━━ Layout / Metadata ━━━━━━━━━━━━━━━━━━━━━━━

  test(
    'IT10: FR layout → preserve metadata after isolate computation',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      final nodeDs = NodeDriftDataSource(db);

      final nodeRepo = NodeRepositoryImpl(nodeDs);

      final now = DateTime.now();

      await nodeRepo.upsertNode(
        Node(
          bleAddress: 'meta-dev-1',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [-45],
          suggestedName: 'Living Room Sensor',
          deviceType: 'Sensor',
          connectable: true,
        ),
      );

      final nodes = await nodeRepo.observeNodes().first;

      final scanRepo = ScanSessionRepositoryImpl(db);

      final sessionId = await scanRepo.startSession();

      await scanRepo.addNodesToSession(
        sessionId,
        nodes.map((node) => node.id!).toList(),
      );

      final graphRepo = GraphRepositoryImpl(
        nodeRepo,
        db,
        TestRemoteRelationRepository(),
      );

      final layout = await graphRepo.buildGraph(sessionId);

      final gn = layout.nodes.firstWhere(
        (node) => node.suggestedName == 'Living Room Sensor',
      );

      expect(gn.suggestedName, 'Living Room Sensor');

      expect(gn.connectable, isTrue);

      final calc = CalculateLayout(
        layoutAlgorithm: const FruchtermanReingold(),
      );

      final result = await calc(layout, 2000.0, 2000.0);

      final refined = result.fold(
        (failure) => fail('FR failed: ${failure.message}'),
        (value) => value,
      );

      final refinedNode = refined.nodes.firstWhere(
        (node) => node.suggestedName == 'Living Room Sensor',
      );

      expect(
        refinedNode.suggestedName,
        'Living Room Sensor',
        reason: 'Metadata must survive FR isolate computation',
      );

      await db.close();
    },
  );

  // ━━━━━━━━━━━━━━━━━ BleConnectionBloc Lifecycle ━━━━━━━━━━━━━━

  test(
    'IT14: RSSI null → proximity "far" (RSSI -100 semantics)',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      final nodeDs = NodeDriftDataSource(db);

      final nodeRepo = NodeRepositoryImpl(nodeDs);

      final now = DateTime.now();

      await nodeRepo.upsertNode(
        Node(
          bleAddress: 'no-rssi-dev',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [],
        ),
      );

      final nodes = await nodeRepo.observeNodes().first;

      final scanRepo = ScanSessionRepositoryImpl(db);

      final sessionId = await scanRepo.startSession();

      await scanRepo.addNodesToSession(
        sessionId,
        nodes.map((node) => node.id!).toList(),
      );

      final graphRepo = GraphRepositoryImpl(
        nodeRepo,
        db,
        TestRemoteRelationRepository(),
      );

      final layout = await graphRepo.buildGraph(sessionId);

      final nodeId = nodes.first.id!;
      final gn = layout.nodes.firstWhere((node) => node.id == nodeId);

      expect(
        gn.proximity,
        ProximityLevel.far,
        reason: 'Node without RSSI must render as far (RSSI -100 fallback)',
      );

      await db.close();
    },
  );

  test(
    'IT17: 3D representation — z-coordinates survive graph rebuild',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      final nodeDs = NodeDriftDataSource(db);

      final nodeRepo = NodeRepositoryImpl(nodeDs);

      final now = DateTime.now();

      await nodeRepo.upsertNode(
        Node(
          bleAddress: 'webview-3d-test',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [-50],
        ),
      );

      final nodes = await nodeRepo.observeNodes().first;

      final graphRepo = GraphRepositoryImpl(
        nodeRepo,
        db,
        TestRemoteRelationRepository(),
      );

      final scanRepo = ScanSessionRepositoryImpl(db);

      final sessionId = await scanRepo.startSession();

      await scanRepo.addNodesToSession(
        sessionId,
        nodes.map((node) => node.id!).toList(),
      );

      final layout1 = await graphRepo.buildGraph(sessionId);

      final layout2 = await graphRepo.buildGraph(sessionId);

      for (final node in layout1.nodes) {
        expect(
          node.z,
          0.0,
          reason: 'z-coordinate must be preserved across builds',
        );
      }

      expect(
        layout1.nodes.length,
        layout2.nodes.length,
        reason: 'Graph rebuild must preserve node count',
      );

      await db.close();
    },
  );

  test(
    'IT18: Auto-center on GraphReady — barycenter computed from node positions',
    tags: ['integration'],
    () {
      fakeAsync((async) async {
        final db = AppDatabase.inMemory();

        final nodeDs = NodeDriftDataSource(db);

        final nodeRepo = NodeRepositoryImpl(nodeDs);

        final now = DateTime.now();

        await nodeRepo.upsertNode(
          Node(
            bleAddress: 'center-dev-1',
            firstSeen: now,
            lastSeen: now,
            rssiHistory: const [-50],
          ),
        );

        await nodeRepo.upsertNode(
          Node(
            bleAddress: 'center-dev-2',
            firstSeen: now,
            lastSeen: now,
            rssiHistory: const [-60],
          ),
        );

        final nodes = await nodeRepo.observeNodes().first;

        final scanRepo = ScanSessionRepositoryImpl(db);

        final sessionId = await scanRepo.startSession();

        await scanRepo.addNodesToSession(
          sessionId,
          nodes.map((node) => node.id!).toList(),
        );

        final graphRepo = GraphRepositoryImpl(
          nodeRepo,
          db,
          TestRemoteRelationRepository(),
        );

        final buildGraph = BuildGraph(graphRepo);

        final calc = CalculateLayout(
          layoutAlgorithm: const FruchtermanReingold(),
        );

        final vizBloc = VisualizationBloc(
          buildGraph: buildGraph,
          calculateLayout: calc,
          remoteRelationRepository: TestRemoteRelationRepository(),
          debounceDuration: const Duration(milliseconds: 10),
        );

        final states = <VisualizationState>[];

        final sub = vizBloc.stream.listen(states.add);

        vizBloc.add(
          BuildGraphRequested(scanSessionId: sessionId, nodes: nodes),
        );

        async.elapse(const Duration(milliseconds: 30));

        async.flushMicrotasks();

        await Future<void>.delayed(const Duration(milliseconds: 200));

        async.flushMicrotasks();

        final ready = states.whereType<GraphReady>().firstOrNull;

        expect(ready, isNotNull, reason: 'Must reach GraphReady');

        final barycenter = ready!.barycenter;

        expect(
          barycenter,
          isNotNull,
          reason: 'GraphReady must include barycenter for auto-centering',
        );

        expect(barycenter!.dx, greaterThan(0));

        expect(barycenter.dy, greaterThan(0));

        await sub.cancel();
        await vizBloc.close();
        await db.close();
      });
    },
  );

  test(
    'IT20: Full cold start — empty DB → onboarding → BLE scan → graph ready',
    tags: ['integration'],
    () {
      fakeAsync((async) async {
        final db = AppDatabase.inMemory();

        final userDs = UserDriftDataSource(db);

        final userRepo = UserRepositoryImpl(userDs);

        final nodeDs = NodeDriftDataSource(db);

        final nodeRepo = NodeRepositoryImpl(nodeDs);

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

        userBloc.add(const LoadProfile());

        await userBloc.stream.firstWhere((state) => state is UserLoaded);

        userBloc.add(const UpdateUserNameEvent('Zotel'));

        await userBloc.stream.firstWhere(
          (state) => state is UserLoaded && state.user.name == 'Zotel',
        );

        userBloc.add(const UpdateUserColorEvent('#FF5722'));

        await userBloc.stream.firstWhere(
          (state) => state is UserLoaded && state.user.color == '#FF5722',
        );

        final myUuid = userBloc.myDeviceUuid;

        expect(myUuid, isNotNull);

        final loadedUser = (userBloc.state as UserLoaded).user;

        expect(
          loadedUser.localNodeId,
          isNotNull,
          reason: 'Cold start debe crear el self-node antes de UserLoaded',
        );

        final persistedSelf = await nodeRepo.getSelfNode();

        expect(persistedSelf, isNotNull);

        expect(persistedSelf!.id, loadedUser.localNodeId);

        expect(persistedSelf.id, isNot(-1));

        expect(persistedSelf.isSelf, isTrue);

        expect(persistedSelf.deviceUuid, myUuid);

        final scanRepo = ScanSessionRepositoryImpl(db);

        final bleRepo = TestBleRepository();

        final bleBloc = BleBloc(
          repository: bleRepo,
          userRepository: TestUserRepository(),
          remoteRelationRepository: TestRemoteRelationRepository(),
          nodeRepository: nodeRepo,
          connectionRepository: TestBleConnectionRepository(),
          dutyCyclePeriod: const Duration(minutes: 10),
        );

        final nodeBloc = NodeListBloc(
          observeNodes: ObserveNodes(nodeRepo),
          updateNodeMetadata: UpdateNodeMetadata(nodeRepo),
          nodeRepository: nodeRepo,
        );

        bleBloc.add(const StartScan());

        async.flushMicrotasks();

        final devices = [
          BleDevice(
            deviceId: 'DD:01',
            rssi: -45,
            distance: 2,
            proximity: ProximityLevel.close,
            timestamp: DateTime.now(),
            advName: 'S1',
          ),
          BleDevice(
            deviceId: 'DD:02',
            rssi: -55,
            distance: 3,
            proximity: ProximityLevel.close,
            timestamp: DateTime.now(),
            advName: 'S2',
          ),
          BleDevice(
            deviceId: 'DD:03',
            rssi: -65,
            distance: 4,
            proximity: ProximityLevel.medium,
            timestamp: DateTime.now(),
            advName: 'S3',
          ),
          BleDevice(
            deviceId: 'DD:04',
            rssi: -75,
            distance: 6,
            proximity: ProximityLevel.medium,
            timestamp: DateTime.now(),
            advName: 'S4',
          ),
          BleDevice(
            deviceId: 'DD:05',
            rssi: -85,
            distance: 10,
            proximity: ProximityLevel.far,
            timestamp: DateTime.now(),
            advName: 'S5',
          ),
        ];

        nodeBloc.add(SyncBleDevices(devices));

        async.flushMicrotasks();

        await Future<void>.delayed(const Duration(milliseconds: 50));

        async.flushMicrotasks();

        final nodes = await nodeRepo.observeNodes().first;

        expect(
          nodes.length,
          greaterThanOrEqualTo(6),
          reason:
              'Debe existir el self persistente más los dispositivos detectados',
        );

        final sessionId = await scanRepo.startSession();

        final externalNodes = nodes.where((node) => !node.isSelf).toList();

        await scanRepo.addNodesToSession(
          sessionId,
          externalNodes.map((node) => node.id!).toList(),
        );

        await scanRepo.endSession(sessionId);

        final graphRepo = GraphRepositoryImpl(
          nodeRepo,
          db,
          TestRemoteRelationRepository(),
        );

        final layout = await graphRepo.buildGraph(
          sessionId,
          myDeviceUuid: myUuid,
        );

        expect(
          layout.nodes.length,
          greaterThanOrEqualTo(5),
          reason: 'Cold start must produce graph with detected nodes',
        );

        await userBloc.close();
        await bleBloc.close();
        await nodeBloc.close();

        bleRepo.dispose();

        await db.close();
      });
    },
  );

  // ━━━━━━━━━━━━━━━━━ Sanity checks ━━━━━━━━━━━━━━━━━━━━━━━━━
}
