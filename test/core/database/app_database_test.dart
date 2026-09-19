import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';

/// SQLite stores DateTime with millisecond precision.
/// Truncate Dart microseconds so assertions match.
DateTime _truncateToMs(DateTime dt) =>
    DateTime.fromMillisecondsSinceEpoch(dt.millisecondsSinceEpoch);

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase schema', () {
    test('schema version is 7', () {
      expect(db.schemaVersion, 7);
    });

    test('creates users table', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
          )
          .get();

      expect(tables, hasLength(1));
    });

    test('creates nodes table', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='nodes'",
          )
          .get();

      expect(tables, hasLength(1));
    });

    test('creates scan_sessions table', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='scan_sessions'",
          )
          .get();

      expect(tables, hasLength(1));
    });

    test('ARCH-001: nodes contains device_uuid and is_self columns', () async {
      final columns = await db.customSelect('PRAGMA table_info(nodes)').get();

      final names = columns.map((row) => row.read<String>('name')).toSet();

      expect(names, contains('device_uuid'));
      expect(names, contains('is_self'));
      expect(names, contains('ble_address'));
    });

    test('ARCH-001: users contains local_node_id column', () async {
      final columns = await db.customSelect('PRAGMA table_info(users)').get();

      final names = columns.map((row) => row.read<String>('name')).toSet();

      expect(names, contains('local_node_id'));
    });
  });

  group('Users CRUD', () {
    test('inserts and reads a user', () async {
      final now = _truncateToMs(DateTime.now());

      final id = await db
          .into(db.users)
          .insert(
            UsersCompanion(
              uuid: const Value('abc-123'),
              name: const Value('TestUser'),
              color: const Value('#2196F3'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      expect(id, greaterThan(0));

      final user = await (db.select(
        db.users,
      )..where((u) => u.id.equals(id))).getSingle();

      expect(user.uuid, 'abc-123');
      expect(user.name, 'TestUser');
      expect(user.color, '#2196F3');
      expect(user.deviceType, 'android');
      expect(user.createdAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch);

      // ARCH-001:
      // Un perfil puede existir momentáneamente antes de EnsureLocalNode.
      expect(user.localNodeId, isNull);
    });

    test('enforces uuid uniqueness', () async {
      final now = _truncateToMs(DateTime.now());

      await db
          .into(db.users)
          .insert(
            UsersCompanion(
              uuid: const Value('unique-123'),
              name: const Value('User1'),
              color: const Value('#000'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      expect(
        () => db
            .into(db.users)
            .insert(
              UsersCompanion(
                uuid: const Value('unique-123'),
                name: const Value('User2'),
                color: const Value('#fff'),
                deviceType: const Value('ios'),
                createdAt: Value(now),
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });

    test('updates a user', () async {
      final now = _truncateToMs(DateTime.now());

      final id = await db
          .into(db.users)
          .insert(
            UsersCompanion(
              uuid: const Value('upd-123'),
              name: const Value('OldName'),
              color: const Value('#111'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      await (db.update(db.users)..where((u) => u.id.equals(id))).write(
        const UsersCompanion(name: Value('NewName'), color: Value('#222')),
      );

      final user = await (db.select(
        db.users,
      )..where((u) => u.id.equals(id))).getSingle();

      expect(user.name, 'NewName');
      expect(user.color, '#222');
    });

    test('deletes a user', () async {
      final now = _truncateToMs(DateTime.now());

      final id = await db
          .into(db.users)
          .insert(
            UsersCompanion(
              uuid: const Value('del-123'),
              name: const Value('ToDelete'),
              color: const Value('#333'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      await (db.delete(db.users)..where((u) => u.id.equals(id))).go();

      final allUsers = await db.select(db.users).get();

      expect(allUsers, isEmpty);
    });

    test('reads all users (CHECK(id=1) limita a 1 fila)', () async {
      final now = _truncateToMs(DateTime.now());

      await db
          .into(db.users)
          .insert(
            UsersCompanion(
              id: const Value(1),
              uuid: const Value('a-1'),
              name: const Value('Alice'),
              color: const Value('#aaa'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      await expectLater(
        () => db
            .into(db.users)
            .insert(
              UsersCompanion(
                uuid: const Value('b-2'),
                name: const Value('Bob'),
                color: const Value('#bbb'),
                deviceType: const Value('ios'),
                createdAt: Value(now),
              ),
            ),
        throwsA(isA<Exception>()),
      );

      final users = await db.select(db.users).get();

      expect(users, hasLength(1));
    });

    test('ARCH-001: localNodeId referencia un Node real', () async {
      final now = _truncateToMs(DateTime.now());

      final nodeId = await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              deviceUuid: const Value('local-node-uuid'),
              isSelf: const Value(true),
              name: const Value('Cristian'),
              color: const Value('#2196F3'),
              firstSeen: Value(now),
              lastSeen: Value(now),
            ),
          );

      await db
          .into(db.users)
          .insert(
            UsersCompanion(
              id: const Value(1),
              uuid: const Value('local-node-uuid'),
              name: const Value('Cristian'),
              color: const Value('#2196F3'),
              deviceType: const Value('android'),
              createdAt: Value(now),
              localNodeId: Value(nodeId),
            ),
          );

      final user = await db.select(db.users).getSingle();

      expect(user.localNodeId, nodeId);

      final referencedNode = await (db.select(
        db.nodes,
      )..where((node) => node.id.equals(user.localNodeId!))).getSingle();

      expect(referencedNode.id, nodeId);
      expect(referencedNode.isSelf, isTrue);
      expect(referencedNode.deviceUuid, 'local-node-uuid');
    });

    test(
      'ARCH-001: borrar self-node deja localNodeId en null y conserva User',
      () async {
        final now = _truncateToMs(DateTime.now());

        final nodeId = await db
            .into(db.nodes)
            .insert(
              NodesCompanion(
                deviceUuid: const Value('self-set-null'),
                isSelf: const Value(true),
                firstSeen: Value(now),
                lastSeen: Value(now),
              ),
            );

        await db
            .into(db.users)
            .insert(
              UsersCompanion(
                id: const Value(1),
                uuid: const Value('self-set-null'),
                name: const Value('Cristian'),
                color: const Value('#2196F3'),
                deviceType: const Value('android'),
                createdAt: Value(now),
                localNodeId: Value(nodeId),
              ),
            );

        await (db.delete(
          db.nodes,
        )..where((node) => node.id.equals(nodeId))).go();

        final user = await db.select(db.users).getSingle();

        expect(user.localNodeId, isNull);

        final users = await db.select(db.users).get();

        expect(users, hasLength(1));
      },
    );
  });

  group('Nodes CRUD', () {
    test('inserts and reads a node', () async {
      final now = _truncateToMs(DateTime.now());

      final id = await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('AA:BB:CC:DD:EE:FF'),
              name: const Value('Node1'),
              color: const Value('#808080'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              lastRssi: const Value(-55),
              proximityZone: const Value('green'),
              rssiHistory: const Value('[-50,-55,-60]'),
            ),
          );

      expect(id, greaterThan(0));

      final node = await (db.select(
        db.nodes,
      )..where((n) => n.id.equals(id))).getSingle();

      expect(node.bleAddress, 'AA:BB:CC:DD:EE:FF');

      expect(node.name, 'Node1');
      expect(node.lastRssi, -55);
      expect(node.proximityZone, 'green');
      expect(node.isSelf, isFalse);
      expect(node.deviceUuid, isNull);
    });

    test('inserts node with nullable name and color', () async {
      final now = _truncateToMs(DateTime.now());

      final id = await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('FF:EE:DD:CC:BB:AA'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[]'),
            ),
          );

      final node = await (db.select(
        db.nodes,
      )..where((n) => n.id.equals(id))).getSingle();

      expect(node.name, isNull);
      expect(node.color, isNull);
    });

    test('enforces bleAddress uniqueness', () async {
      final now = _truncateToMs(DateTime.now());

      await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('11:22:33:44:55:66'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[]'),
            ),
          );

      expect(
        () => db
            .into(db.nodes)
            .insert(
              NodesCompanion(
                bleAddress: const Value('11:22:33:44:55:66'),
                firstSeen: Value(now),
                lastSeen: Value(now),
                rssiHistory: const Value('[]'),
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });

    test('updates a node', () async {
      final now = _truncateToMs(DateTime.now());

      final id = await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('CC:BB:AA:11:22:33'),
              name: const Value('OldNode'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              lastRssi: const Value(-70),
              proximityZone: const Value('amber'),
              rssiHistory: const Value('[-70]'),
            ),
          );

      final later = now.add(const Duration(minutes: 5));

      await (db.update(db.nodes)..where((n) => n.id.equals(id))).write(
        NodesCompanion(
          name: const Value('UpdatedNode'),
          lastSeen: Value(later),
          lastRssi: const Value(-50),
          proximityZone: const Value('green'),
          rssiHistory: const Value('[-70,-50]'),
        ),
      );

      final node = await (db.select(
        db.nodes,
      )..where((n) => n.id.equals(id))).getSingle();

      expect(node.name, 'UpdatedNode');

      expect(
        node.lastSeen.millisecondsSinceEpoch,
        later.millisecondsSinceEpoch,
      );

      expect(node.lastRssi, -50);
      expect(node.proximityZone, 'green');
    });

    test('deletes a node', () async {
      final now = _truncateToMs(DateTime.now());

      final id = await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('DD:EE:FF:00:11:22'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[]'),
            ),
          );

      await (db.delete(db.nodes)..where((n) => n.id.equals(id))).go();

      final allNodes = await db.select(db.nodes).get();

      expect(allNodes, isEmpty);
    });

    test('ARCH-001: permite self-node sin bleAddress', () async {
      final now = _truncateToMs(DateTime.now());

      final id = await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              deviceUuid: const Value('self-uuid-001'),
              bleAddress: const Value(null),
              isSelf: const Value(true),
              name: const Value('Mi dispositivo'),
              color: const Value('#2196F3'),
              firstSeen: Value(now),
              lastSeen: Value(now),
            ),
          );

      final node = await (db.select(
        db.nodes,
      )..where((row) => row.id.equals(id))).getSingle();

      expect(node.deviceUuid, 'self-uuid-001');

      expect(node.bleAddress, isNull);
      expect(node.isSelf, isTrue);
    });

    test('ARCH-001: deviceUuid debe ser único', () async {
      final now = _truncateToMs(DateTime.now());

      await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              deviceUuid: const Value('device-uuid-unique'),
              firstSeen: Value(now),
              lastSeen: Value(now),
            ),
          );

      expect(
        () => db
            .into(db.nodes)
            .insert(
              NodesCompanion(
                deviceUuid: const Value('device-uuid-unique'),
                firstSeen: Value(now),
                lastSeen: Value(now),
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });

    test('ARCH-001: solo permite un self-node', () async {
      final now = _truncateToMs(DateTime.now());

      await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              deviceUuid: const Value('self-uuid-A'),
              isSelf: const Value(true),
              firstSeen: Value(now),
              lastSeen: Value(now),
            ),
          );

      await expectLater(
        () => db
            .into(db.nodes)
            .insert(
              NodesCompanion(
                deviceUuid: const Value('self-uuid-B'),
                isSelf: const Value(true),
                firstSeen: Value(now),
                lastSeen: Value(now),
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ScanSessions CRUD', () {
    test('inserts and reads a scan session', () async {
      final startedAt = _truncateToMs(DateTime.now());

      final id = await db
          .into(db.scanSessions)
          .insert(
            ScanSessionsCompanion(
              startedAt: Value(startedAt),
              nodesDetected: const Value(5),
            ),
          );

      final session = await (db.select(
        db.scanSessions,
      )..where((s) => s.id.equals(id))).getSingle();

      expect(
        session.startedAt.millisecondsSinceEpoch,
        startedAt.millisecondsSinceEpoch,
      );

      expect(session.nodesDetected, 5);
      expect(session.endedAt, isNull);
    });

    test('updates endedAt when session completes', () async {
      final startedAt = _truncateToMs(DateTime.now());

      final id = await db
          .into(db.scanSessions)
          .insert(
            ScanSessionsCompanion(
              startedAt: Value(startedAt),
              nodesDetected: const Value(0),
            ),
          );

      final endedAt = startedAt.add(const Duration(seconds: 10));

      await (db.update(db.scanSessions)..where((s) => s.id.equals(id))).write(
        ScanSessionsCompanion(
          endedAt: Value(endedAt),
          nodesDetected: const Value(3),
        ),
      );

      final session = await (db.select(
        db.scanSessions,
      )..where((s) => s.id.equals(id))).getSingle();

      expect(
        session.endedAt!.millisecondsSinceEpoch,
        endedAt.millisecondsSinceEpoch,
      );

      expect(session.nodesDetected, 3);
    });
  });

  group('Migration v1→v2', () {
    test('creates scan_session_nodes table', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table'"
            " AND name='scan_session_nodes'",
          )
          .get();

      expect(tables, hasLength(1));
    });

    test('creates index on scan_session_nodes.session_id', () async {
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index'"
            " AND name='scan_session_nodes_session_id_idx'",
          )
          .get();

      expect(indexes, hasLength(1));
    });

    test('inserts and reads scan_session_nodes', () async {
      final now = _truncateToMs(DateTime.now());

      final sessionId = await db
          .into(db.scanSessions)
          .insert(
            ScanSessionsCompanion(
              startedAt: Value(now),
              nodesDetected: const Value(3),
            ),
          );

      final nodeId1 = await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('AA:BB:CC:11:22:33'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-55]'),
            ),
          );

      final nodeId2 = await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('AA:BB:CC:11:22:44'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-65]'),
            ),
          );

      await db
          .into(db.scanSessionNodes)
          .insert(
            ScanSessionNodesCompanion(
              sessionId: Value(sessionId),
              nodeId: Value(nodeId1),
              rssi: const Value(-55),
            ),
          );

      await db
          .into(db.scanSessionNodes)
          .insert(
            ScanSessionNodesCompanion(
              sessionId: Value(sessionId),
              nodeId: Value(nodeId2),
              rssi: const Value(-65),
            ),
          );

      final rows = await db.select(db.scanSessionNodes).get();

      expect(rows, hasLength(2));
      expect(rows[0].sessionId, sessionId);
      expect(rows[1].sessionId, sessionId);
      expect(rows[0].rssi, -55);
      expect(rows[1].rssi, -65);
    });

    test('previene duplicados por combinación sessionId+nodeId', () async {
      final now = _truncateToMs(DateTime.now());

      final sessionId = await db
          .into(db.scanSessions)
          .insert(
            ScanSessionsCompanion(
              startedAt: Value(now),
              nodesDetected: const Value(1),
            ),
          );

      final nodeId = await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('DD:EE:FF:00:11:22'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-70]'),
            ),
          );

      await db
          .into(db.scanSessionNodes)
          .insert(
            ScanSessionNodesCompanion(
              sessionId: Value(sessionId),
              nodeId: Value(nodeId),
              rssi: const Value(-70),
            ),
          );

      expect(
        () => db
            .into(db.scanSessionNodes)
            .insert(
              ScanSessionNodesCompanion(
                sessionId: Value(sessionId),
                nodeId: Value(nodeId),
                rssi: const Value(-71),
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ──────────────────────── PR4: Security Hardening ────────────────────────

  group('Migration v4→v5: índices en connections', () {
    test(
      'T4.1: crea índices idx_connections_from_node_id y idx_connections_to_node_id',
      () async {
        final indexes = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='index'"
              " AND name LIKE 'idx_connections_%'",
            )
            .get();

        final names = indexes.map((r) => r.read<String>('name')).toSet();

        expect(
          names,
          containsAll([
            'idx_connections_from_node_id',
            'idx_connections_to_node_id',
          ]),
          reason: 'La migración v5 debe crear ambos índices en connections',
        );

        expect(
          indexes,
          hasLength(2),
          reason:
              'Debe haber exactamente 2 índices con prefijo idx_connections_',
        );
      },
    );
  });

  group('CASCADE delete en scan_session_nodes', () {
    test(
      'T4.2: ON DELETE CASCADE — borrar ScanSession elimina scan_session_nodes asociados',
      () async {
        final now = _truncateToMs(DateTime.now());

        final sessionId = await db
            .into(db.scanSessions)
            .insert(
              ScanSessionsCompanion(
                startedAt: Value(now),
                nodesDetected: const Value(3),
              ),
            );

        final nodeId1 = await db
            .into(db.nodes)
            .insert(
              NodesCompanion(
                bleAddress: const Value('CA:SC:AD:EE:01:01'),
                firstSeen: Value(now),
                lastSeen: Value(now),
                rssiHistory: const Value('[-55]'),
              ),
            );

        final nodeId2 = await db
            .into(db.nodes)
            .insert(
              NodesCompanion(
                bleAddress: const Value('CA:SC:AD:EE:02:02'),
                firstSeen: Value(now),
                lastSeen: Value(now),
                rssiHistory: const Value('[-65]'),
              ),
            );

        final nodeId3 = await db
            .into(db.nodes)
            .insert(
              NodesCompanion(
                bleAddress: const Value('CA:SC:AD:EE:03:03'),
                firstSeen: Value(now),
                lastSeen: Value(now),
                rssiHistory: const Value('[-75]'),
              ),
            );

        await db
            .into(db.scanSessionNodes)
            .insert(
              ScanSessionNodesCompanion(
                sessionId: Value(sessionId),
                nodeId: Value(nodeId1),
                rssi: const Value(-55),
              ),
            );

        await db
            .into(db.scanSessionNodes)
            .insert(
              ScanSessionNodesCompanion(
                sessionId: Value(sessionId),
                nodeId: Value(nodeId2),
                rssi: const Value(-65),
              ),
            );

        await db
            .into(db.scanSessionNodes)
            .insert(
              ScanSessionNodesCompanion(
                sessionId: Value(sessionId),
                nodeId: Value(nodeId3),
                rssi: const Value(-75),
              ),
            );

        var rows = await db.select(db.scanSessionNodes).get();

        expect(
          rows,
          hasLength(3),
          reason: 'Debe haber 3 filas antes de borrar la sesión',
        );

        await (db.delete(
          db.scanSessions,
        )..where((s) => s.id.equals(sessionId))).go();

        rows = await db.select(db.scanSessionNodes).get();

        expect(
          rows,
          isEmpty,
          reason:
              'ON DELETE CASCADE debe eliminar automáticamente '
              'las filas en scan_session_nodes al borrar la sesión padre',
        );
      },
    );
  });

  // ──────────────────────── PR3: Data Layer Performance ────────────────────────

  group('Índices de performance (T-PR3-001)', () {
    test('creates index on nodes.ble_address', () async {
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index'"
            " AND name='idx_nodes_ble_address'",
          )
          .get();

      expect(
        indexes,
        hasLength(1),
        reason: 'Debe existir un índice en nodes(ble_address)',
      );
    });

    test('ARCH-001: creates index on nodes.device_uuid', () async {
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index'"
            " AND name='idx_nodes_device_uuid'",
          )
          .get();

      expect(
        indexes,
        hasLength(1),
        reason: 'Debe existir un índice en nodes(device_uuid)',
      );
    });

    test('ARCH-001: creates unique partial index on nodes.is_self', () async {
      final indexes = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master "
            "WHERE type='index' "
            "AND name='idx_nodes_is_self'",
          )
          .get();

      expect(indexes, hasLength(1));

      final sql = indexes.single.read<String?>('sql');

      expect(sql, isNotNull);

      expect(sql!.toUpperCase(), contains('UNIQUE INDEX'));

      expect(sql.toLowerCase(), contains('where is_self = 1'));
    });

    test('creates index on scan_session_nodes.node_id', () async {
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index'"
            " AND name='idx_scan_session_nodes_node_id'",
          )
          .get();

      expect(
        indexes,
        hasLength(1),
        reason: 'Debe existir un índice en scan_session_nodes(node_id)',
      );
    });

    test('creates index on scan_sessions.started_at', () async {
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index'"
            " AND name='idx_scan_sessions_started_at'",
          )
          .get();

      expect(
        indexes,
        hasLength(1),
        reason: 'Debe existir un índice en scan_sessions(started_at)',
      );
    });

    test('EXPLAIN QUERY PLAN para upsertNode usa índice ble_address', () async {
      final now = _truncateToMs(DateTime.now());

      await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('EX:PL:AI:N0:DE:01'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-55]'),
            ),
          );

      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN '
            'SELECT * FROM nodes WHERE ble_address = ?',
            variables: [Variable.withString('EX:PL:AI:N0:DE:01')],
          )
          .get();

      final detail = plan.map((row) => row.read<String>('detail')).join(' ');

      expect(
        detail,
        contains('USING INDEX'),
        reason:
            'El EXPLAIN QUERY PLAN debe mostrar USING INDEX para '
            'la búsqueda por ble_address',
      );
    });

    test('ARCH-001: EXPLAIN QUERY PLAN por device_uuid usa índice', () async {
      final now = _truncateToMs(DateTime.now());

      await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              deviceUuid: const Value('explain-device-uuid'),
              firstSeen: Value(now),
              lastSeen: Value(now),
            ),
          );

      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN '
            'SELECT * FROM nodes WHERE device_uuid = ?',
            variables: [Variable.withString('explain-device-uuid')],
          )
          .get();

      final detail = plan.map((row) => row.read<String>('detail')).join(' ');

      expect(detail, contains('USING INDEX'));
    });
  });

  group('CHECK(id=1) en Users', () {
    test('solo permite INSERT con id=1', () async {
      final now = _truncateToMs(DateTime.now());

      await db
          .into(db.users)
          .insert(
            UsersCompanion(
              id: const Value(1),
              uuid: const Value('check-user-1'),
              name: const Value('Uno'),
              color: const Value('#000'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      expect(
        () => db
            .into(db.users)
            .insert(
              UsersCompanion(
                id: const Value(2),
                uuid: const Value('check-user-2'),
                name: const Value('Dos'),
                color: const Value('#fff'),
                deviceType: const Value('ios'),
                createdAt: Value(now),
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CASCADE delete en scan_session_nodes.node_id FK', () {
    test(
      'T-PR3-002: ON DELETE CASCADE en node_id — borrar Node elimina scan_session_nodes asociados',
      () async {
        final now = _truncateToMs(DateTime.now());

        final sessionId = await db
            .into(db.scanSessions)
            .insert(
              ScanSessionsCompanion(
                startedAt: Value(now),
                nodesDetected: const Value(1),
              ),
            );

        final nodeId = await db
            .into(db.nodes)
            .insert(
              NodesCompanion(
                bleAddress: const Value('CA:SC:NO:DE:F0:01'),
                firstSeen: Value(now),
                lastSeen: Value(now),
                rssiHistory: const Value('[-55]'),
              ),
            );

        await db
            .into(db.scanSessionNodes)
            .insert(
              ScanSessionNodesCompanion(
                sessionId: Value(sessionId),
                nodeId: Value(nodeId),
                rssi: const Value(-55),
              ),
            );

        var rows = await db.select(db.scanSessionNodes).get();

        expect(rows, hasLength(1));

        await (db.delete(
          db.nodes,
        )..where((node) => node.id.equals(nodeId))).go();

        rows = await db.select(db.scanSessionNodes).get();

        expect(
          rows,
          isEmpty,
          reason:
              'ON DELETE CASCADE en node_id debe eliminar '
              'automáticamente las filas en scan_session_nodes '
              'al borrar el nodo padre',
        );
      },
    );
  });

  group('Transaction atomicity', () {
    test(
      'T4.3: addNodesToSession en transaction — fallo en insert → rollback, 0 filas',
      () async {
        final now = _truncateToMs(DateTime.now());

        final sessionId = await db
            .into(db.scanSessions)
            .insert(
              ScanSessionsCompanion(
                startedAt: Value(now),
                nodesDetected: const Value(0),
              ),
            );

        final nodeId1 = await db
            .into(db.nodes)
            .insert(
              NodesCompanion(
                bleAddress: const Value('TX:AC:TI:ON:01:01'),
                firstSeen: Value(now),
                lastSeen: Value(now),
                rssiHistory: const Value('[-55]'),
              ),
            );

        final nodeId2 = await db
            .into(db.nodes)
            .insert(
              NodesCompanion(
                bleAddress: const Value('TX:AC:TI:ON:02:02'),
                firstSeen: Value(now),
                lastSeen: Value(now),
                rssiHistory: const Value('[-65]'),
              ),
            );

        try {
          await db.transaction(() async {
            await db
                .into(db.scanSessionNodes)
                .insert(
                  ScanSessionNodesCompanion.insert(
                    sessionId: sessionId,
                    nodeId: nodeId1,
                    rssi: -55,
                  ),
                );

            await db
                .into(db.scanSessionNodes)
                .insert(
                  ScanSessionNodesCompanion.insert(
                    sessionId: sessionId,
                    nodeId: nodeId2,
                    rssi: -65,
                  ),
                );

            await db
                .into(db.scanSessionNodes)
                .insert(
                  ScanSessionNodesCompanion.insert(
                    sessionId: sessionId,
                    nodeId: nodeId1,
                    rssi: -70,
                  ),
                );
          });

          fail('Debería haber lanzado excepción por UNIQUE constraint');
        } catch (_) {
          // Esperado: rollback automático.
        }

        final rows = await db.select(db.scanSessionNodes).get();

        expect(
          rows,
          isEmpty,
          reason:
              'La transacción debe hacer rollback completo: '
              '0 filas insertadas tras el fallo',
        );
      },
    );
  });
}
