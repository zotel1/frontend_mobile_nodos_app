import 'package:drift/drift.dart' hide Column, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart' hide ScanSession;
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_scan_sessions.dart';

/// T3.2: Tests para GetScanSessions — consulta sesiones de escaneo
/// ordenadas por startedAt DESC con conteo de nodos por sesión.
///
/// S4.1: 3 sesiones pasadas → lista muestra fecha, duración y conteo
/// de nodos por sesión.
void main() {
  late AppDatabase db;
  late GetScanSessions useCase;

  setUp(() async {
    db = AppDatabase.inMemory();
    useCase = GetScanSessions(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ── Helpers ──

  /// Inserta una sesión de escaneo.
  Future<int> insertSession(DateTime startedAt,
      [DateTime? endedAt, int nodesDetected = 0]) async {
    return db.into(db.scanSessions).insert(
          ScanSessionsCompanion(
            startedAt: Value(startedAt),
            endedAt: Value(endedAt),
            nodesDetected: Value(nodesDetected),
          ),
        );
  }

  /// Inserta un nodo en la tabla nodes.
  Future<int> insertNode(String address) async {
    return db.into(db.nodes).insert(
          NodesCompanion(
            bleAddress: Value(address),
            firstSeen: Value(DateTime(2026, 6, 1)),
            lastSeen: Value(DateTime(2026, 6, 19)),
            lastRssi: const Value(-60),
            proximityZone: const Value('medium'),
            rssiHistory: const Value('[-60]'),
          ),
        );
  }

  /// Inserta un registro en scan_session_nodes.
  Future<void> insertSessionNode(int sessionId, int nodeId,
      [int rssi = -60]) async {
    await db.into(db.scanSessionNodes).insert(
          ScanSessionNodesCompanion.insert(
            sessionId: sessionId,
            nodeId: nodeId,
            rssi: Value(rssi),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  group('T3.2: GetScanSessions', () {
    test('retorna lista vacía cuando no hay sesiones', () async {
      final result = await useCase();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (sessions) => expect(sessions, isEmpty),
      );
    });

    test('retorna sesiones ordenadas por startedAt DESC con conteo de nodos',
        () async {
      // Insertar sesiones en orden no cronológico
      final s1 = await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5), 0);
      final s2 = await insertSession(
          DateTime(2026, 6, 18, 15, 0), DateTime(2026, 6, 18, 15, 3), 0);
      final s3 = await insertSession(
          DateTime(2026, 6, 20, 8, 0), null, 0); // más reciente pero sin fin

      // Insertar nodos para simular conteo en scan_session_nodes
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02');

      // s1 tiene 2 nodos
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);

      // s2 tiene 1 nodo
      await insertSessionNode(s2, nodeA);

      // s3 sin nodos

      final result = await useCase();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (sessions) {
          expect(sessions.length, equals(3));

          // Más reciente primero → s3 (20-jun)
          expect(sessions[0].id, equals(s3));
          expect(sessions[0].startedAt, equals(DateTime(2026, 6, 20, 8, 0)));
          expect(sessions[0].endedAt, isNull);
          expect(sessions[0].nodeCount, equals(0));

          // Segundo → s1 (19-jun)
          expect(sessions[1].id, equals(s1));
          expect(sessions[1].nodeCount, equals(2));

          // Tercero → s2 (18-jun)
          expect(sessions[2].id, equals(s2));
          expect(sessions[2].nodeCount, equals(1));
        },
      );
    });

    test('calcula duration cuando endedAt no es null', () async {
      await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));

      final result = await useCase();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (sessions) {
          expect(sessions.length, equals(1));
          expect(sessions[0].startedAt, equals(DateTime(2026, 6, 19, 10, 0)));
          expect(sessions[0].endedAt, equals(DateTime(2026, 6, 19, 10, 5)));
          expect(sessions[0].duration, equals(const Duration(minutes: 5)));
        },
      );
    });

    test('retorna null duration cuando endedAt es null', () async {
      await insertSession(DateTime(2026, 6, 19, 10, 0), null);

      final result = await useCase();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (sessions) {
          expect(sessions.length, equals(1));
          expect(sessions[0].duration, isNull);
        },
      );
    });
  });
}
