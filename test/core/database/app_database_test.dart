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

    test('impide insertar segundo usuario por CHECK (id=1)', () async {
      final now = _truncateToMs(DateTime.now());
      // Primer usuario: id=1 (válido según CHECK)
      await db.into(db.users).insert(
            UsersCompanion(
              uuid: const Value('a-1'),
              name: const Value('Alice'),
              color: const Value('#aaa'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );
      // T-PR2-005: CHECK (id = 1) impide un segundo usuario.
      // El segundo insert intentaría asignar id=2, violando la constraint.
      expect(
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
        reason: 'CHECK (id = 1) debe impedir insertar un segundo usuario',
      );

      // Solo debe existir el primer usuario
      final users = await db.select(db.users).get();
      expect(users, hasLength(1));
      expect(users.first.name, 'Alice');
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

    // ──────────────────────────────────────────────────────────
    // T-PR2-005 RED: ON DELETE CASCADE en scan_session_nodes
    //
    // QUÉ: al eliminar un nodo de la tabla nodes, las filas
    // correspondientes en scan_session_nodes deben eliminarse
    // automáticamente por ON DELETE CASCADE.
    //
    // POR QUÉ problema existe: las foreign keys actuales no tienen
    // ON DELETE CASCADE → al eliminar un nodo, scan_session_nodes
    // retiene referencias huérfanas que producen edges fantasma
    // en el grafo (bug: nodos eliminados siguen apareciendo).
    //
    // Estado RED esperado: el expect final (isEmpty) falla porque
    // sin ON DELETE CASCADE, scan_session_nodes conserva los
    // registros tras eliminar el nodo.
    // ──────────────────────────────────────────────────────────
    test(
        'T-PR2-005 RED: ON DELETE CASCADE — eliminar nodo limpia scan_session_nodes',
        () async {
      final now = _truncateToMs(DateTime.now());

      // Crear sesión de escaneo
      final sessionId = await db.into(db.scanSessions).insert(
            ScanSessionsCompanion(
              startedAt: Value(now),
              nodesDetected: const Value(2),
            ),
          );

      // Crear dos nodos
      final nodeId1 = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('AA:BB:CC:DD:EE:01'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-55]'),
            ),
          );
      final nodeId2 = await db.into(db.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('AA:BB:CC:DD:EE:02'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-65]'),
            ),
          );

      // Registrar ambos nodos en scan_session_nodes
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

      // Verificar que hay 2 registros
      var rows = await db.select(db.scanSessionNodes).get();
      expect(rows, hasLength(2));

      // Eliminar nodo 1
      await (db.delete(db.nodes)..where((n) => n.id.equals(nodeId1))).go();

      // Verificar que scan_session_nodes ahora solo tiene el nodo 2
      rows = await db.select(db.scanSessionNodes).get();
      expect(rows, hasLength(1));
      expect(rows.first.nodeId, nodeId2);

      // Eliminar nodo 2 también
      await (db.delete(db.nodes)..where((n) => n.id.equals(nodeId2))).go();

      // scan_session_nodes debe quedar vacío (cascade total)
      rows = await db.select(db.scanSessionNodes).get();
      expect(rows, isEmpty,
          reason: 'ON DELETE CASCADE debe eliminar registros huérfanos');
    });

    // ──────────────────────────────────────────────────────────
    // T-PR2-005 RED: CHECK constraint singleton en Users
    //
    // QUÉ: la tabla users debe aceptar exactamente UN registro
    // (id=1). Insertar un segundo usuario debe violar una
    // constraint CHECK.
    //
    // POR QUÉ problema existe: actualmente nada impide insertar
    // múltiples usuarios. Como la app es single-user (un solo
    // dispositivo), tener múltiples registros produce
    // ambigüedad — getUser() retorna cualquiera.
    //
    // Estado RED esperado: el expect de throwsA falla porque
    // actualmente se pueden insertar múltiples users sin error.
    // ──────────────────────────────────────────────────────────
    test(
        'T-PR2-005 RED: CHECK constraint — insertar segundo usuario lanza error',
        () async {
      final now = _truncateToMs(DateTime.now());

      // Insertar primer usuario
      await db.into(db.users).insert(
            UsersCompanion(
              uuid: const Value('user-1-uuid'),
              name: const Value('Usuario Uno'),
              color: const Value('#2196F3'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );

      // Intentar insertar un segundo usuario debe fallar
      expect(
        () => db.into(db.users).insert(
              UsersCompanion(
                uuid: const Value('user-2-uuid'),
                name: const Value('Usuario Dos'),
                color: const Value('#FF5722'),
                deviceType: const Value('ios'),
                createdAt: Value(now),
              ),
            ),
        throwsA(isA<Exception>()),
        reason: 'CHECK (id = 1) debe impedir un segundo usuario',
      );
    });

    // ──────────────────────────────────────────────────────────
    // T-PR2-005 RED: Migración v3→v4 con datos existentes
    //
    // QUÉ: una BD creada con schema v3 (con datos reales) debe
    // migrar correctamente a v4, agregando la columna connectable
    // sin perder los datos existentes.
    //
    // POR QUÉ problema existe: la migración v3→v4 no existe aún.
    // El nuevo schema v4 agrega una columna connectable a Nodes
    // que debe ser nullable para no romper datos existentes.
    //
    // Estado RED esperado: el test falla porque el schema actual
    // es v3 y la columna connectable no existe en Nodes.
    // ──────────────────────────────────────────────────────────
    test(
        'T-PR2-005 RED: migración v3→v4 agrega columna connectable (nullable) en Nodes',
        () async {
      // Verificar que la columna connectable existe en la tabla nodes
      final columns = await db.customSelect(
        "PRAGMA table_info('nodes')",
      ).get();

      // Buscar la columna 'connectable' con tipo nullable
      final connectableCol = columns.where(
        (row) => row.read<String>('name') == 'connectable',
      );
      expect(connectableCol, isNotEmpty,
          reason: 'La columna connectable debe existir en schema v4');

      // Verificar que es nullable (notnull = 0)
      final notnull = connectableCol.first.read<int>('notnull');
      expect(notnull, 0,
          reason: 'connectable debe ser nullable para no romper datos existentes');
    });
  });
}
