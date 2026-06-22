import 'package:drift/drift.dart' hide isNull;
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
    test('creates users table', () async {
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
      ).get();
      expect(tables, hasLength(1));
    });

    test('creates nodes table', () async {
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='nodes'",
      ).get();
      expect(tables, hasLength(1));
    });

    test('creates scan_sessions table', () async {
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='scan_sessions'",
      ).get();
      expect(tables, hasLength(1));
    });
  });

  group('Users CRUD', () {
    test('inserts and reads a user', () async {
      final now = _truncateToMs(DateTime.now());
      final id = await db.into(db.users).insert(
            UsersCompanion(
              uuid: const Value('abc-123'),
              name: const Value('TestUser'),
              color: const Value('#2196F3'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      expect(id, greaterThan(0));

      final user = await (db.select(db.users)..where((u) => u.id.equals(id)))
          .getSingle();
      expect(user.uuid, 'abc-123');
      expect(user.name, 'TestUser');
      expect(user.color, '#2196F3');
      expect(user.deviceType, 'android');
      expect(user.createdAt.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch);
    });

    test('enforces uuid uniqueness', () async {
      final now = _truncateToMs(DateTime.now());
      await db.into(db.users).insert(
            UsersCompanion(
              uuid: const Value('unique-123'),
              name: const Value('User1'),
              color: const Value('#000'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      expect(
        () => db.into(db.users).insert(
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
      final id = await db.into(db.users).insert(
            UsersCompanion(
              uuid: const Value('upd-123'),
              name: const Value('OldName'),
              color: const Value('#111'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      await (db.update(db.users)..where((u) => u.id.equals(id))).write(
            const UsersCompanion(
              name: Value('NewName'),
              color: Value('#222'),
            ),
          );

      final user = await (db.select(db.users)..where((u) => u.id.equals(id)))
          .getSingle();
      expect(user.name, 'NewName');
      expect(user.color, '#222');
    });

    test('deletes a user', () async {
      final now = _truncateToMs(DateTime.now());
      final id = await db.into(db.users).insert(
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
      await db.into(db.users).insert(
            UsersCompanion(
              id: const Value(1),
              uuid: const Value('a-1'),
              name: const Value('Alice'),
              color: const Value('#aaa'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      // CHECK(id=1): un segundo usuario con id≠1 debe fallar.
      await expectLater(
        () => db.into(db.users).insert(
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
  });

  group('Nodes CRUD', () {
    test('inserts and reads a node', () async {
      final now = _truncateToMs(DateTime.now());
      final id = await db.into(db.nodes).insert(
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

      final node =
          await (db.select(db.nodes)..where((n) => n.id.equals(id)))
              .getSingle();
      expect(node.bleAddress, 'AA:BB:CC:DD:EE:FF');
      expect(node.name, 'Node1');
      expect(node.lastRssi, -55);
      expect(node.proximityZone, 'green');
    });

    test('inserts node with nullable name and color', () async {
      final now = _truncateToMs(DateTime.now());
      final id = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('FF:EE:DD:CC:BB:AA'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[]'),
            ),
          );

      final node =
          await (db.select(db.nodes)..where((n) => n.id.equals(id)))
              .getSingle();
      expect(node.name, isNull);
      expect(node.color, isNull);
    });

    test('enforces bleAddress uniqueness', () async {
      final now = _truncateToMs(DateTime.now());
      await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('11:22:33:44:55:66'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[]'),
            ),
          );

      expect(
        () => db.into(db.nodes).insert(
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
      final id = await db.into(db.nodes).insert(
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

      final node =
          await (db.select(db.nodes)..where((n) => n.id.equals(id)))
              .getSingle();
      expect(node.name, 'UpdatedNode');
      expect(node.lastSeen.millisecondsSinceEpoch,
          later.millisecondsSinceEpoch);
      expect(node.lastRssi, -50);
      expect(node.proximityZone, 'green');
    });

    test('deletes a node', () async {
      final now = _truncateToMs(DateTime.now());
      final id = await db.into(db.nodes).insert(
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
  });

  group('ScanSessions CRUD', () {
    test('inserts and reads a scan session', () async {
      final startedAt = _truncateToMs(DateTime.now());
      final id = await db.into(db.scanSessions).insert(
            ScanSessionsCompanion(
              startedAt: Value(startedAt),
              nodesDetected: const Value(5),
            ),
          );

      final session = await (db.select(db.scanSessions)
            ..where((s) => s.id.equals(id)))
          .getSingle();
      expect(session.startedAt.millisecondsSinceEpoch,
          startedAt.millisecondsSinceEpoch);
      expect(session.nodesDetected, 5);
      expect(session.endedAt, isNull);
    });

    test('updates endedAt when session completes', () async {
      final startedAt = _truncateToMs(DateTime.now());
      final id = await db.into(db.scanSessions).insert(
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

      final session = await (db.select(db.scanSessions)
            ..where((s) => s.id.equals(id)))
          .getSingle();
      expect(session.endedAt!.millisecondsSinceEpoch,
          endedAt.millisecondsSinceEpoch);
      expect(session.nodesDetected, 3);
    });
  });

  group('Migration v1→v2', () {
    test('creates scan_session_nodes table', () async {
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table'"
        " AND name='scan_session_nodes'",
      ).get();
      expect(tables, hasLength(1));
    });

    test('creates index on scan_session_nodes.session_id', () async {
      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index'"
        " AND name='scan_session_nodes_session_id_idx'",
      ).get();
      expect(indexes, hasLength(1));
    });

    test('inserts and reads scan_session_nodes', () async {
      final now = _truncateToMs(DateTime.now());

      // Inserta una sesión
      final sessionId = await db.into(db.scanSessions).insert(
            ScanSessionsCompanion(
              startedAt: Value(now),
              nodesDetected: const Value(3),
            ),
          );

      // Inserta nodos
      final nodeId1 = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('AA:BB:CC:11:22:33'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-55]'),
            ),
          );
      final nodeId2 = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('AA:BB:CC:11:22:44'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-65]'),
            ),
          );

      // Inserta en scan_session_nodes
      await db.into(db.scanSessionNodes).insert(
            ScanSessionNodesCompanion(
              sessionId: Value(sessionId),
              nodeId: Value(nodeId1),
              rssi: const Value(-55),
            ),
          );
      await db.into(db.scanSessionNodes).insert(
            ScanSessionNodesCompanion(
              sessionId: Value(sessionId),
              nodeId: Value(nodeId2),
              rssi: const Value(-65),
            ),
          );

      // Verifica
      final rows = await db.select(db.scanSessionNodes).get();
      expect(rows, hasLength(2));
      expect(rows[0].sessionId, sessionId);
      expect(rows[1].sessionId, sessionId);
      expect(rows[0].rssi, -55);
      expect(rows[1].rssi, -65);
    });

    test('previene duplicados por combinación sessionId+nodeId', () async {
      final now = _truncateToMs(DateTime.now());

      final sessionId = await db.into(db.scanSessions).insert(
            ScanSessionsCompanion(
              startedAt: Value(now),
              nodesDetected: const Value(1),
            ),
          );

      final nodeId = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('DD:EE:FF:00:11:22'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-70]'),
            ),
          );

      await db.into(db.scanSessionNodes).insert(
            ScanSessionNodesCompanion(
              sessionId: Value(sessionId),
              nodeId: Value(nodeId),
              rssi: const Value(-70),
            ),
          );

      // Insert duplicado debe lanzar excepción (UNIQUE constraint)
      expect(
        () => db.into(db.scanSessionNodes).insert(
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
    test('T4.1: crea índices idx_connections_from_node_id y idx_connections_to_node_id',
        () async {
      // R15: connections table MUST have non-unique indices on
      // (from_node_id) and (to_node_id).
      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index'"
        " AND name LIKE 'idx_connections_%'",
      ).get();

      final names = indexes.map((r) => r.read<String>('name')).toSet();
      expect(names,
          containsAll(['idx_connections_from_node_id', 'idx_connections_to_node_id']),
          reason: 'La migración v5 debe crear ambos índices en connections');
      expect(indexes, hasLength(2),
          reason: 'Debe haber exactamente 2 índices con prefijo idx_connections_');
    });
  });

  group('CASCADE delete en scan_session_nodes', () {
    test('T4.2: ON DELETE CASCADE — borrar ScanSession elimina scan_session_nodes asociados',
        () async {
      // R16: scan_session_nodes FK to scan_sessions MUST include ON DELETE CASCADE.
      final now = _truncateToMs(DateTime.now());

      // Crear sesión
      final sessionId = await db.into(db.scanSessions).insert(
            ScanSessionsCompanion(
              startedAt: Value(now),
              nodesDetected: const Value(3),
            ),
          );

      // Crear 3 nodos
      final nodeId1 = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('CA:SC:AD:EE:01:01'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-55]'),
            ),
          );
      final nodeId2 = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('CA:SC:AD:EE:02:02'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-65]'),
            ),
          );
      final nodeId3 = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('CA:SC:AD:EE:03:03'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-75]'),
            ),
          );

      // Insertar 3 filas en scan_session_nodes
      await db.into(db.scanSessionNodes).insert(
            ScanSessionNodesCompanion(
              sessionId: Value(sessionId),
              nodeId: Value(nodeId1),
              rssi: const Value(-55),
            ),
          );
      await db.into(db.scanSessionNodes).insert(
            ScanSessionNodesCompanion(
              sessionId: Value(sessionId),
              nodeId: Value(nodeId2),
              rssi: const Value(-65),
            ),
          );
      await db.into(db.scanSessionNodes).insert(
            ScanSessionNodesCompanion(
              sessionId: Value(sessionId),
              nodeId: Value(nodeId3),
              rssi: const Value(-75),
            ),
          );

      // Verificar que existen 3 filas
      var rows = await db.select(db.scanSessionNodes).get();
      expect(rows, hasLength(3),
          reason: 'Debe haber 3 filas antes de borrar la sesión');

      // Borrar la sesión → CASCADE debe eliminar las filas asociadas
      await (db.delete(db.scanSessions)
            ..where((s) => s.id.equals(sessionId)))
          .go();

      // Verificar que las filas asociadas fueron eliminadas automáticamente
      rows = await db.select(db.scanSessionNodes).get();
      expect(rows, isEmpty,
          reason: 'ON DELETE CASCADE debe eliminar automáticamente'
              ' las filas en scan_session_nodes al borrar la sesión padre');
    });
  });

  // ──────────────────────── PR3: Data Layer Performance ────────────────────────

  group('Índices de performance (T-PR3-001)', () {
    // QUÉ: verifica que los índices definidos en el schema existen físicamente
    // en la base de datos.
    // POR QUÉ: los índices son necesarios para acelerar las queries frecuentes:
    //   - nodes.ble_address: upsert lookup en cada detección BLE
    //   - scan_session_nodes.node_id: JOIN en queries de grafo social
    //   - scan_sessions.started_at: ordenamiento en historial de sesiones

    test('creates index on nodes.ble_address', () async {
      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index'"
        " AND name='idx_nodes_ble_address'",
      ).get();
      expect(indexes, hasLength(1),
          reason: 'Debe existir un índice en nodes(ble_address)');
    });

    test('creates index on scan_session_nodes.node_id', () async {
      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index'"
        " AND name='idx_scan_session_nodes_node_id'",
      ).get();
      expect(indexes, hasLength(1),
          reason: 'Debe existir un índice en scan_session_nodes(node_id)');
    });

    test('creates index on scan_sessions.started_at', () async {
      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index'"
        " AND name='idx_scan_sessions_started_at'",
      ).get();
      expect(indexes, hasLength(1),
          reason: 'Debe existir un índice en scan_sessions(started_at)');
    });

    test('EXPLAIN QUERY PLAN para upsertNode usa índice ble_address', () async {
      // Inserta un nodo primero para que el EXPLAIN tenga datos reales.
      final now = _truncateToMs(DateTime.now());
      await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('EX:PL:AI:N0:DE:01'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-55]'),
            ),
          );

      // QUÉ: verifica que el query planner de SQLite usa el índice
      // idx_nodes_ble_address cuando se hace un SELECT por bleAddress.
      // POR QUÉ: el upsertNode busca por bleAddress en cada detección BLE
      // y debe usar el índice para evitar un full table scan.
      final plan = await db.customSelect(
        "EXPLAIN QUERY PLAN SELECT * FROM nodes WHERE ble_address = ?",
        variables: [Variable.withString('EX:PL:AI:N0:DE:01')],
      ).get();

      final detail = plan.map((r) => r.read<String>('detail')).join(' ');
      expect(detail, contains('USING INDEX'),
          reason: 'El EXPLAIN QUERY PLAN debe mostrar USING INDEX para'
              ' la búsqueda por ble_address');
    });
  });

  group('CHECK(id=1) en Users', () {
    // QUÉ: verifica que la tabla Users tiene un CHECK constraint que
    // limita la columna id a valor 1.
    // POR QUÉ: la app es single-user por diseño (MVP). Forzar CHECK(id=1)
    // previene la creación accidental de múltiples filas de usuario y
    // simplifica las queries del repositorio.

    test('solo permite INSERT con id=1', () async {
      final now = _truncateToMs(DateTime.now());
      // Insert con id=1 debe funcionar.
      await db.into(db.users).insert(
            UsersCompanion(
              id: const Value(1),
              uuid: const Value('check-user-1'),
              name: const Value('Uno'),
              color: const Value('#000'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      // Insert con id distinto de 1 debe fallar.
      expect(
        () => db.into(db.users).insert(
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
    test('T-PR3-002: ON DELETE CASCADE en node_id — borrar Node elimina'
        ' scan_session_nodes asociados', () async {
      // QUÉ: verifica que eliminar un nodo borra automáticamente sus
      // filas en scan_session_nodes (CASCADE).
      // POR QUÉ: actualmente solo session_id tiene CASCADE. Si un nodo
      // se borra, scan_session_nodes quedaría con referencias huérfanas.
      final now = _truncateToMs(DateTime.now());

      // Crear sesión
      final sessionId = await db.into(db.scanSessions).insert(
            ScanSessionsCompanion(
              startedAt: Value(now),
              nodesDetected: const Value(1),
            ),
          );

      // Crear nodo
      final nodeId = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('CA:SC:NO:DE:F0:01'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-55]'),
            ),
          );

      // Insertar en scan_session_nodes
      await db.into(db.scanSessionNodes).insert(
            ScanSessionNodesCompanion(
              sessionId: Value(sessionId),
              nodeId: Value(nodeId),
              rssi: const Value(-55),
            ),
          );

      // Verificar que existe
      var rows = await db.select(db.scanSessionNodes).get();
      expect(rows, hasLength(1));

      // Borrar el nodo → CASCADE debe eliminar la fila asociada
      await (db.delete(db.nodes)..where((n) => n.id.equals(nodeId))).go();

      // Verificar que scan_session_nodes quedó vacío
      rows = await db.select(db.scanSessionNodes).get();
      expect(rows, isEmpty,
          reason: 'ON DELETE CASCADE en node_id debe eliminar'
              ' automáticamente las filas en scan_session_nodes'
              ' al borrar el nodo padre');
    });
  });

  group('Transaction atomicity', () {
    test('T4.3: addNodesToSession en transaction — fallo en insert → rollback, 0 filas',
        () async {
      // R17: Multi-table writes MUST be wrapped in a transaction for atomicity.
      final now = _truncateToMs(DateTime.now());

      // Crear sesión
      final sessionId = await db.into(db.scanSessions).insert(
            ScanSessionsCompanion(
              startedAt: Value(now),
              nodesDetected: const Value(0),
            ),
          );

      // Crear nodos válidos
      final nodeId1 = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('TX:AC:TI:ON:01:01'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-55]'),
            ),
          );
      final nodeId2 = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('TX:AC:TI:ON:02:02'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-65]'),
            ),
          );

      // Ejecutar inserts dentro de una transaction.
      // El 3er insert es duplicado (mismo sessionId+nodeId que el 1ro)
      // SIN usar insertOrIgnore → debe lanzar UNIQUE constraint violation.
      try {
        await db.transaction(() async {
          // Insert 1: válido (sessionId, nodeId1)
          await db.into(db.scanSessionNodes).insert(
                ScanSessionNodesCompanion.insert(
                  sessionId: sessionId,
                  nodeId: nodeId1,
                  rssi: -55,
                ),
              );
          // Insert 2: válido (sessionId, nodeId2)
          await db.into(db.scanSessionNodes).insert(
                ScanSessionNodesCompanion.insert(
                  sessionId: sessionId,
                  nodeId: nodeId2,
                  rssi: -65,
                ),
              );
          // Insert 3: DUPLICADO del insert 1 → debe lanzar excepción
          // (sin insertOrIgnore para que falle realmente)
          await db.into(db.scanSessionNodes).insert(
                ScanSessionNodesCompanion.insert(
                  sessionId: sessionId,
                  nodeId: nodeId1,
                  rssi: -70,
                ),
              );
        });
        fail('Debería haber lanzado excepción por UNIQUE constraint');
      } catch (_) {
        // Esperado: la transaction hizo rollback automático
      }

      // Verificar rollback: ninguna fila fue insertada
      final rows = await db.select(db.scanSessionNodes).get();
      expect(rows, isEmpty,
          reason: 'La transacción debe hacer rollback completo:'
              ' 0 filas insertadas tras el fallo');
    });
  });
}
