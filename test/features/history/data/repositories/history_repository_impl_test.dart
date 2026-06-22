import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart' hide ScanSession;
import 'package:frontend_mobile_nodos_app/features/history/data/datasources/history_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/history/data/repositories/history_repository_impl.dart';

/// Tests para HistoryRepositoryImpl usando HistoryDriftDataSource real.
///
/// Verifica que el repositorio transforma correctamente los resultados
/// crudos del datasource en entidades de dominio.
void main() {
  late AppDatabase db;
  late HistoryDriftDataSource dataSource;
  late HistoryRepositoryImpl repo;

  setUp(() async {
    db = AppDatabase.inMemory();
    dataSource = HistoryDriftDataSource(db);
    repo = HistoryRepositoryImpl(dataSource);
  });

  tearDown(() async {
    await db.close();
  });

  // ── Helpers ──

  Future<int> insertSession(DateTime startedAt,
      [DateTime? endedAt]) async {
    return db.into(db.scanSessions).insert(
          ScanSessionsCompanion(
            startedAt: Value(startedAt),
            endedAt: Value(endedAt),
            nodesDetected: const Value(0),
          ),
        );
  }

  Future<int> insertNode(String address, [String? name]) async {
    return db.into(db.nodes).insert(
          NodesCompanion(
            bleAddress: Value(address),
            name: Value(name),
            firstSeen: Value(DateTime(2026, 6, 1)),
            lastSeen: Value(DateTime(2026, 6, 19)),
            lastRssi: const Value(-60),
            proximityZone: const Value('medium'),
            rssiHistory: const Value('[-60]'),
          ),
        );
  }

  Future<void> insertSessionNode(int sessionId, int nodeId,
      [int rssi = -60]) async {
    await db.into(db.scanSessionNodes).insert(
          ScanSessionNodesCompanion.insert(
            sessionId: sessionId,
            nodeId: nodeId,
            rssi: rssi,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  // ── getSessions() ──

  group('getSessions', () {
    test('retorna lista vacía cuando no hay sesiones', () async {
      final result = await repo.getSessions();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (sessions) => expect(sessions, isEmpty),
      );
    });

    test('retorna sesiones ordenadas por startedAt DESC con conteo de nodos',
        () async {
      final s1 = await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));
      final s2 = await insertSession(
          DateTime(2026, 6, 18, 15, 0), DateTime(2026, 6, 18, 15, 3));
      final s3 = await insertSession(
          DateTime(2026, 6, 20, 8, 0), null);

      final nodeA = await insertNode('AA:BB:CC:DD:EE:01');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02');

      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);
      await insertSessionNode(s2, nodeA);

      final result = await repo.getSessions();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (sessions) {
          expect(sessions.length, equals(3));
          expect(sessions[0].id, equals(s3));
          expect(sessions[0].nodeCount, equals(0));
          expect(sessions[1].id, equals(s1));
          expect(sessions[1].nodeCount, equals(2));
          expect(sessions[2].id, equals(s2));
          expect(sessions[2].nodeCount, equals(1));
        },
      );
    });

    test('calcula duration cuando endedAt no es null', () async {
      await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));

      final result = await repo.getSessions();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (sessions) {
          expect(sessions.length, equals(1));
          expect(sessions[0].duration, equals(const Duration(minutes: 5)));
        },
      );
    });

    test('retorna null duration cuando endedAt es null', () async {
      await insertSession(DateTime(2026, 6, 19, 10, 0), null);

      final result = await repo.getSessions();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (sessions) {
          expect(sessions[0].duration, isNull);
        },
      );
    });
  });

  // ── getSessionDetail() ──

  group('getSessionDetail', () {
    test('retorna lista vacía cuando la sesión no tiene nodos', () async {
      final session = await insertSession(DateTime(2026, 6, 19));

      final result = await repo.getSessionDetail(session);

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) => expect(nodes, isEmpty),
      );
    });

    test('retorna lista vacía cuando la sesión no existe', () async {
      final result = await repo.getSessionDetail(999);

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) => expect(nodes, isEmpty),
      );
    });

    test('retorna nodos con RSSI y nombre para una sesión con 2 nodos',
        () async {
      final session = await insertSession(DateTime(2026, 6, 19));
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Nodo Alpha');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Nodo Beta');

      await insertSessionNode(session, nodeA, -45);
      await insertSessionNode(session, nodeB, -75);

      final result = await repo.getSessionDetail(session);

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) {
          expect(nodes.length, equals(2));
          final nodeAData = nodes.firstWhere((n) => n.nodeId == nodeA);
          expect(nodeAData.rssi, equals(-45));
          expect(nodeAData.nodeName, equals('Nodo Alpha'));

          final nodeBData = nodes.firstWhere((n) => n.nodeId == nodeB);
          expect(nodeBData.rssi, equals(-75));
          expect(nodeBData.nodeName, equals('Nodo Beta'));
        },
      );
    });

    test('retorna nombre null para nodos sin nombre asignado', () async {
      final session = await insertSession(DateTime(2026, 6, 19));
      final node = await insertNode('FF:EE:DD:CC:BB:01', null);

      await insertSessionNode(session, node, -85);

      final result = await repo.getSessionDetail(session);

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) {
          expect(nodes.length, equals(1));
          expect(nodes[0].nodeName, isNull);
          expect(nodes[0].rssi, equals(-85));
        },
      );
    });

    test('calcula proximityLevel correctamente desde RSSI', () async {
      final session = await insertSession(DateTime(2026, 6, 19));
      final closeNode = await insertNode('11:22:33:44:55:01');
      final mediumNode = await insertNode('11:22:33:44:55:02');
      final farNode = await insertNode('11:22:33:44:55:03');

      await insertSessionNode(session, closeNode, -50);
      await insertSessionNode(session, mediumNode, -75);
      await insertSessionNode(session, farNode, -90);

      final result = await repo.getSessionDetail(session);

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) {
          expect(nodes.length, equals(3));
          final close = nodes.firstWhere((n) => n.nodeId == closeNode);
          expect(close.proximityLevel, equals('close'));
          final medium = nodes.firstWhere((n) => n.nodeId == mediumNode);
          expect(medium.proximityLevel, equals('medium'));
          final far = nodes.firstWhere((n) => n.nodeId == farNode);
          expect(far.proximityLevel, equals('far'));
        },
      );
    });
  });

  // ── getStats() ──

  group('getStats', () {
    test('retorna cero en todas las stats cuando no hay sesiones', () async {
      final result = await repo.getStats();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          expect(stats.totalSessions, equals(0));
          expect(stats.uniqueNodes, equals(0));
          expect(stats.averageDuration, equals(Duration.zero));
          expect(stats.mostFrequentNodeName, isNull);
        },
      );
    });

    test('retorna cero uniqueNodes cuando hay sesiones sin nodos', () async {
      await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));
      await insertSession(
          DateTime(2026, 6, 19, 12, 0), DateTime(2026, 6, 19, 12, 10));

      final result = await repo.getStats();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          expect(stats.totalSessions, equals(2));
          expect(stats.uniqueNodes, equals(0));
          expect(stats.mostFrequentNodeName, isNull);
        },
      );
    });

    test('calcula totalSessions, uniqueNodes y mostFrequentNode', () async {
      final nodeA = await insertNode('AA:01', 'Nodo A');
      final nodeB = await insertNode('BB:02', 'Nodo B');
      final nodeC = await insertNode('CC:03', 'Nodo C');

      final s1 = await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);

      final s2 = await insertSession(
          DateTime(2026, 6, 19, 12, 0), DateTime(2026, 6, 19, 12, 10));
      await insertSessionNode(s2, nodeA);
      await insertSessionNode(s2, nodeB);
      await insertSessionNode(s2, nodeC);

      final s3 = await insertSession(
          DateTime(2026, 6, 19, 14, 0), DateTime(2026, 6, 19, 14, 3));
      await insertSessionNode(s3, nodeA);

      final result = await repo.getStats();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          expect(stats.totalSessions, equals(3));
          expect(stats.uniqueNodes, equals(3));
          expect(stats.mostFrequentNodeName, equals('Nodo A'));
        },
      );
    });

    test('calcula averageDuration correctamente', () async {
      await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));
      await insertSession(
          DateTime(2026, 6, 19, 11, 0), DateTime(2026, 6, 19, 11, 15));

      final result = await repo.getStats();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          expect(stats.averageDuration, equals(const Duration(minutes: 10)));
        },
      );
    });

    test('ignora sesiones sin endedAt en el cálculo de averageDuration',
        () async {
      await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));
      await insertSession(DateTime(2026, 6, 19, 12, 0), null);

      final result = await repo.getStats();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          expect(stats.totalSessions, equals(2));
          expect(stats.averageDuration, equals(const Duration(minutes: 5)));
        },
      );
    });

    test('nodo más frecuente con empate — retorna uno de los empatados',
        () async {
      final nodeA = await insertNode('AA:01', 'Nodo A');
      final nodeB = await insertNode('BB:02', 'Nodo B');

      final s1 = await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);

      final s2 = await insertSession(
          DateTime(2026, 6, 19, 12, 0), DateTime(2026, 6, 19, 12, 5));
      await insertSessionNode(s2, nodeA);
      await insertSessionNode(s2, nodeB);

      final result = await repo.getStats();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          expect(stats.mostFrequentNodeName, isNotNull);
          expect(
            stats.mostFrequentNodeName,
            anyOf(equals('Nodo A'), equals('Nodo B')),
          );
        },
      );
    });
  });
}
