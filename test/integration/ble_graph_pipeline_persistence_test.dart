import 'ble_graph_pipeline_test_support.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test(
    'BUG-003 integration: ClearNodes preserva historial y asociaciones de sesión',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      // ─────────────────────────────────────────────────────
      // 1. Infraestructura real
      // ─────────────────────────────────────────────────────

      final nodeDs = NodeDriftDataSource(db);
      final nodeRepo = NodeRepositoryImpl(nodeDs);

      final nodeBloc = NodeListBloc(
        observeNodes: ObserveNodes(nodeRepo),
        updateNodeMetadata: UpdateNodeMetadata(nodeRepo),
        nodeRepository: nodeRepo,
      );

      final scanRepo = ScanSessionRepositoryImpl(db);

      final historyDataSource = HistoryDriftDataSource(db);
      final historyRepo = HistoryRepositoryImpl(historyDataSource);

      // ─────────────────────────────────────────────────────
      // 2. Crear nodos persistentes
      // ─────────────────────────────────────────────────────

      final now = DateTime(2026, 9, 11, 20, 0);

      await nodeRepo.upsertNode(
        Node(
          bleAddress: 'BUG003-NODE-A',
          name: 'Nodo histórico A',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [-45],
          connectable: true,
        ),
      );

      await nodeRepo.upsertNode(
        Node(
          bleAddress: 'BUG003-NODE-B',
          name: 'Nodo histórico B',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [-70],
          connectable: true,
        ),
      );

      final persistedNodes = await nodeRepo.observeNodes().first;

      expect(persistedNodes, hasLength(2));

      final nodeA = persistedNodes.firstWhere(
        (node) => node.bleAddress == 'BUG003-NODE-A',
      );

      final nodeB = persistedNodes.firstWhere(
        (node) => node.bleAddress == 'BUG003-NODE-B',
      );

      expect(nodeA.id, isNotNull);
      expect(nodeB.id, isNotNull);

      // ─────────────────────────────────────────────────────
      // 3. Crear una sesión histórica real
      // ─────────────────────────────────────────────────────

      final sessionId = await scanRepo.startSession();

      await scanRepo.addNodesToSession(sessionId, [nodeA.id!, nodeB.id!]);

      await scanRepo.endSession(sessionId);

      // Reemplazar RSSI placeholder -100 por valores históricos
      // representativos para validar también getSessionDetail().
      await (db.update(db.scanSessionNodes)..where(
            (row) =>
                row.sessionId.equals(sessionId) & row.nodeId.equals(nodeA.id!),
          ))
          .write(const ScanSessionNodesCompanion(rssi: Value(-45)));

      await (db.update(db.scanSessionNodes)..where(
            (row) =>
                row.sessionId.equals(sessionId) & row.nodeId.equals(nodeB.id!),
          ))
          .write(const ScanSessionNodesCompanion(rssi: Value(-70)));

      // ─────────────────────────────────────────────────────
      // 4. Verificar historial ANTES de ClearNodes
      // ─────────────────────────────────────────────────────

      final sessionsBeforeResult = await historyRepo.getSessions();

      final sessionsBefore = sessionsBeforeResult.fold(
        (failure) => fail(
          'No se pudo consultar historial antes de ClearNodes: '
          '${failure.message}',
        ),
        (sessions) => sessions,
      );

      expect(sessionsBefore.any((session) => session.id == sessionId), isTrue);

      final sessionBefore = sessionsBefore.firstWhere(
        (session) => session.id == sessionId,
      );

      expect(sessionBefore.nodeCount, 2);

      final detailBeforeResult = await historyRepo.getSessionDetail(sessionId);

      final detailBefore = detailBeforeResult.fold(
        (failure) => fail(
          'No se pudo consultar detalle antes de ClearNodes: '
          '${failure.message}',
        ),
        (nodes) => nodes,
      );

      expect(detailBefore, hasLength(2));

      expect(
        detailBefore.map((node) => node.nodeId),
        containsAll([nodeA.id, nodeB.id]),
      );

      final statsBeforeResult = await historyRepo.getStats();

      final statsBefore = statsBeforeResult.fold(
        (failure) => fail(
          'No se pudieron consultar estadísticas antes de ClearNodes: '
          '${failure.message}',
        ),
        (stats) => stats,
      );

      expect(statsBefore.totalSessions, 1);
      expect(statsBefore.uniqueNodes, 2);

      // ─────────────────────────────────────────────────────
      // 5. Cargar nodos en UI
      // ─────────────────────────────────────────────────────

      nodeBloc.add(const LoadNodes());

      await nodeBloc.stream.firstWhere(
        (state) => state is NodeListLoaded && state.nodes.length == 2,
      );

      expect(nodeBloc.state, isA<NodeListLoaded>());

      // ─────────────────────────────────────────────────────
      // 6. Simular apagado de Bluetooth
      //
      // HomePage despacha ClearNodes cuando BluetoothOff.
      // BUG-003 exige que esto afecte solo la presentación,
      // nunca el historial persistente.
      // ─────────────────────────────────────────────────────

      nodeBloc.add(const ClearNodes());

      await nodeBloc.stream.firstWhere((state) => state is NodeListEmpty);

      expect(
        nodeBloc.state,
        isA<NodeListEmpty>(),
        reason: 'La UI debe ocultar nodos stale cuando Bluetooth se apaga',
      );

      // ─────────────────────────────────────────────────────
      // 7. Verificar scan_session_nodes directamente
      // ─────────────────────────────────────────────────────

      final sessionNodeRows = await (db.select(
        db.scanSessionNodes,
      )..where((row) => row.sessionId.equals(sessionId))).get();

      expect(
        sessionNodeRows,
        hasLength(2),
        reason:
            'BUG-003: ClearNodes no debe borrar asociaciones históricas '
            'de scan_session_nodes',
      );

      expect(
        sessionNodeRows.map((row) => row.nodeId),
        containsAll([nodeA.id, nodeB.id]),
      );

      // ─────────────────────────────────────────────────────
      // 8. Verificar historial DESPUÉS de ClearNodes
      // ─────────────────────────────────────────────────────

      final sessionsAfterResult = await historyRepo.getSessions();

      final sessionsAfter = sessionsAfterResult.fold(
        (failure) => fail(
          'No se pudo consultar historial después de ClearNodes: '
          '${failure.message}',
        ),
        (sessions) => sessions,
      );

      final sessionAfter = sessionsAfter.firstWhere(
        (session) => session.id == sessionId,
      );

      expect(
        sessionAfter.nodeCount,
        2,
        reason:
            'El historial debe conservar el conteo de nodos '
            'después de apagar Bluetooth',
      );

      final detailAfterResult = await historyRepo.getSessionDetail(sessionId);

      final detailAfter = detailAfterResult.fold(
        (failure) => fail(
          'No se pudo consultar detalle después de ClearNodes: '
          '${failure.message}',
        ),
        (nodes) => nodes,
      );

      expect(
        detailAfter,
        hasLength(2),
        reason: 'El detalle de la sesión debe sobrevivir a ClearNodes',
      );

      final historicalNodeA = detailAfter.firstWhere(
        (node) => node.nodeId == nodeA.id,
      );

      final historicalNodeB = detailAfter.firstWhere(
        (node) => node.nodeId == nodeB.id,
      );

      expect(historicalNodeA.nodeName, 'Nodo histórico A');
      expect(historicalNodeA.rssi, -45);

      expect(historicalNodeB.nodeName, 'Nodo histórico B');
      expect(historicalNodeB.rssi, -70);

      // ─────────────────────────────────────────────────────
      // 9. Verificar estadísticas históricas
      // ─────────────────────────────────────────────────────

      final statsAfterResult = await historyRepo.getStats();

      final statsAfter = statsAfterResult.fold(
        (failure) => fail(
          'No se pudieron consultar estadísticas después de ClearNodes: '
          '${failure.message}',
        ),
        (stats) => stats,
      );

      expect(statsAfter.totalSessions, statsBefore.totalSessions);

      expect(statsAfter.uniqueNodes, statsBefore.uniqueNodes);

      expect(statsAfter.totalSessions, 1);
      expect(statsAfter.uniqueNodes, 2);

      // ─────────────────────────────────────────────────────
      // Cleanup
      // ─────────────────────────────────────────────────────

      await nodeBloc.close();
      await db.close();
    },
  );

  test(
    'BUG-002 integration: ClearNodes vacía la UI sin borrar nodes ni connections',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      // ─────────────────────────────────────────────────────
      // 1. Repositorio real de nodos
      // ─────────────────────────────────────────────────────

      final nodeDs = NodeDriftDataSource(db);
      final nodeRepo = NodeRepositoryImpl(nodeDs);

      final observeNodes = ObserveNodes(nodeRepo);
      final updateNodeMetadata = UpdateNodeMetadata(nodeRepo);

      final nodeBloc = NodeListBloc(
        observeNodes: observeNodes,
        updateNodeMetadata: updateNodeMetadata,
        nodeRepository: nodeRepo,
      );

      // ─────────────────────────────────────────────────────
      // 2. Persistir dos nodos reales
      // ─────────────────────────────────────────────────────

      final now = DateTime.now();

      await nodeRepo.upsertNode(
        Node(
          bleAddress: 'LOCAL-NODE-BUG002',
          name: 'Mi dispositivo',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [],
          isSelf: true,
          connectable: false,
        ),
      );

      await nodeRepo.upsertNode(
        Node(
          bleAddress: 'REMOTE-NODE-BUG002',
          name: 'Reloj',
          firstSeen: now,
          lastSeen: now,
          rssiHistory: const [-45],
          isSelf: false,
          connectable: true,
        ),
      );

      final persistedNodesBefore = await nodeRepo.observeNodes().first;

      expect(persistedNodesBefore, hasLength(2));

      final selfNode = persistedNodesBefore.firstWhere((node) => node.isSelf);

      final remoteNode = persistedNodesBefore.firstWhere(
        (node) => !node.isSelf,
      );

      expect(selfNode.id, isNotNull);
      expect(remoteNode.id, isNotNull);

      // ─────────────────────────────────────────────────────
      // 3. Crear conexión persistente
      // ─────────────────────────────────────────────────────

      await db
          .into(db.connections)
          .insert(
            ConnectionsCompanion.insert(
              fromNodeId: selfNode.id!,
              toNodeId: remoteNode.id!,
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );

      final connectionsBefore = await db.select(db.connections).get();

      expect(connectionsBefore, hasLength(1));

      expect(connectionsBefore.single.fromNodeId, selfNode.id);

      expect(connectionsBefore.single.toNodeId, remoteNode.id);

      // ─────────────────────────────────────────────────────
      // 4. Cargar nodos en el BLoC
      // ─────────────────────────────────────────────────────

      nodeBloc.add(const LoadNodes());

      await nodeBloc.stream.firstWhere(
        (state) => state is NodeListLoaded && state.nodes.length == 2,
      );

      expect(nodeBloc.state, isA<NodeListLoaded>());

      // ─────────────────────────────────────────────────────
      // 5. Ejecutar ClearNodes
      //
      // Esto representa la limpieza de presentación utilizada
      // cuando Bluetooth se apaga.
      // ─────────────────────────────────────────────────────

      nodeBloc.add(const ClearNodes());

      await nodeBloc.stream.firstWhere((state) => state is NodeListEmpty);

      expect(
        nodeBloc.state,
        isA<NodeListEmpty>(),
        reason: 'ClearNodes debe vaciar la representación visible',
      );

      // ─────────────────────────────────────────────────────
      // 6. Verificar que nodes NO fueron borrados
      // ─────────────────────────────────────────────────────

      final persistedNodesAfter = await nodeRepo.observeNodes().first;

      expect(
        persistedNodesAfter,
        hasLength(2),
        reason: 'BUG-002: ClearNodes no debe ejecutar DELETE FROM nodes',
      );

      expect(
        persistedNodesAfter.map((node) => node.id),
        containsAll([selfNode.id, remoteNode.id]),
      );

      // ─────────────────────────────────────────────────────
      // 7. Verificar que connections NO fue borrada
      // ─────────────────────────────────────────────────────

      final connectionsAfter = await db.select(db.connections).get();

      expect(
        connectionsAfter,
        hasLength(1),
        reason: 'La relación persistente debe sobrevivir a ClearNodes',
      );

      expect(connectionsAfter.single.fromNodeId, selfNode.id);

      expect(connectionsAfter.single.toNodeId, remoteNode.id);

      // ─────────────────────────────────────────────────────
      // 8. Protección explícita contra la regresión original
      // ─────────────────────────────────────────────────────

      expect(connectionsAfter.single.fromNodeId, isNot(-1));

      expect(connectionsAfter.single.toNodeId, isNot(-1));

      // ─────────────────────────────────────────────────────
      // Cleanup
      // ─────────────────────────────────────────────────────

      await nodeBloc.close();
      await db.close();
    },
  );

  test(
    'IT5: persistent self-node exists and keeps real SQLite id',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      final userBloc = await makeUserBloc(db);

      userBloc.add(const LoadProfile());

      await userBloc.stream.firstWhere((state) => state is UserLoaded);

      final user = (userBloc.state as UserLoaded).user;

      final nodeRepo = NodeRepositoryImpl(NodeDriftDataSource(db));

      final self = await nodeRepo.getSelfNode();

      expect(self, isNotNull);
      expect(self!.id, isNotNull);
      expect(self.id, isNot(-1));
      expect(self.isSelf, isTrue);
      expect(self.deviceUuid, user.uuid);
      expect(user.localNodeId, self.id);

      await userBloc.close();
      await db.close();
    },
  );

  test(
    'IT15: Transaction rollback — no partial data persisted on failure',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      try {
        await db.transaction(() async {
          await db
              .into(db.scanSessions)
              .insert(
                ScanSessionsCompanion.insert(
                  startedAt: DateTime.now(),
                  nodesDetected: 0,
                ),
              );

          await db
              .into(db.nodes)
              .insert(
                NodesCompanion.insert(
                  bleAddress: const Value('rollback-test-01'),
                  firstSeen: DateTime.now(),
                  lastSeen: DateTime.now(),
                ),
              );

          throw Exception('Simulated mid-transaction failure');
        });
      } catch (_) {
        // Expected rollback.
      }

      final sessions = await db.select(db.scanSessions).get();

      final nodes = await db.select(db.nodes).get();

      expect(sessions, isEmpty);
      expect(nodes, isEmpty);

      await db.close();
    },
  );

  test(
    'IT16: Session lifecycle: create → add nodes → endSession → verify history',
    tags: ['integration'],
    () async {
      final db = AppDatabase.inMemory();

      final nodeDs = NodeDriftDataSource(db);

      final nodeRepo = NodeRepositoryImpl(nodeDs);

      final scanRepo = ScanSessionRepositoryImpl(db);

      final now = DateTime.now();

      for (var i = 0; i < 5; i++) {
        await nodeRepo.upsertNode(
          Node(
            bleAddress: 'hist-dev-$i',
            firstSeen: now,
            lastSeen: now,
            rssiHistory: [-50 - i * 10],
          ),
        );
      }

      final nodes = await nodeRepo.observeNodes().first;

      expect(nodes, hasLength(5));

      final sessionId = await scanRepo.startSession();

      expect(sessionId, greaterThan(0));

      await scanRepo.addNodesToSession(
        sessionId,
        nodes.map((node) => node.id!).toList(),
      );

      await scanRepo.endSession(sessionId);

      final sessions = await db.select(db.scanSessions).get();

      final session = sessions.firstWhere(
        (value) => value.id == sessionId,
        orElse: () => fail('Session not found'),
      );

      expect(session.endedAt, isNotNull, reason: 'endSession must set endedAt');

      expect(
        session.nodesDetected,
        5,
        reason: 'nodesDetected must match added nodes',
      );

      await db.close();
    },
  );

  test(
    'DB inMemory: each instance is isolated from others',
    tags: ['integration'],
    () async {
      final db1 = AppDatabase.inMemory();

      final db2 = AppDatabase.inMemory();

      await db1
          .into(db1.users)
          .insert(
            UsersCompanion.insert(
              uuid: 'separation-test',
              name: 'T',
              color: '#000',
              deviceType: 'test',
              createdAt: DateTime.now(),
            ),
          );

      final user2 =
          await (db2.select(db2.users)
                ..where((user) => user.uuid.equals('separation-test')))
              .getSingleOrNull();

      expect(user2, isNull, reason: 'Each inMemory DB must be isolated');

      await db1.close();
      await db2.close();
    },
  );
}
