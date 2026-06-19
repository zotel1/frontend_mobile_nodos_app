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

    test('reads all users', () async {
      final now = _truncateToMs(DateTime.now());
      await db.into(db.users).insert(
            UsersCompanion(
              uuid: const Value('a-1'),
              name: const Value('Alice'),
              color: const Value('#aaa'),
              deviceType: const Value('android'),
              createdAt: Value(now),
            ),
          );
      await db.into(db.users).insert(
            UsersCompanion(
              uuid: const Value('b-2'),
              name: const Value('Bob'),
              color: const Value('#bbb'),
              deviceType: const Value('ios'),
              createdAt: Value(now),
            ),
          );

      final users = await db.select(db.users).get();
      expect(users, hasLength(2));
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
}
