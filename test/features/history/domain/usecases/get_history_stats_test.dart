import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart' hide ScanSession;
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_history_stats.dart';

/// T3.5: Tests para GetHistoryStats — queries de agregación via Drift
/// customSelect: COUNT(*), COUNT(DISTINCT node_id), AVG duración,
/// nodo más frecuente.
///
/// S5.1: 10 sesiones con 5 nodos únicos → cards: 10 total, 5 únicos,
/// duración promedio, nombre del más frecuente.
/// S5.2: 0 sesiones → cards muestran cero con mensaje apropiado.
void main() {
  late AppDatabase db;
  late GetHistoryStats useCase;

  setUp(() async {
    db = AppDatabase.inMemory();
    useCase = GetHistoryStats(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ── Helpers ──

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

  Future<int> insertNode(String address, String? name) async {
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

  group('T3.5: GetHistoryStats', () {
    // ── S5.2: cero sesiones ──
    test('retorna cero en todas las stats cuando no hay sesiones', () async {
      final result = await useCase();

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

    // ── S5.2: sesiones sin nodos ──
    test('retorna cero uniqueNodes cuando hay sesiones sin nodos', () async {
      await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));
      await insertSession(
          DateTime(2026, 6, 19, 12, 0), DateTime(2026, 6, 19, 12, 10));

      final result = await useCase();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          expect(stats.totalSessions, equals(2));
          expect(stats.uniqueNodes, equals(0));
          expect(stats.mostFrequentNodeName, isNull);
        },
      );
    });

    // ── S5.1: 3 sesiones con nodos ──
    test('calcula totalSessions, uniqueNodes y mostFrequentNode', () async {
      final nodeA = await insertNode('AA:01', 'Nodo A');
      final nodeB = await insertNode('BB:02', 'Nodo B');
      final nodeC = await insertNode('CC:03', 'Nodo C');

      // Sesión 1: A, B
      final s1 = await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);

      // Sesión 2: A, B, C
      final s2 = await insertSession(
          DateTime(2026, 6, 19, 12, 0), DateTime(2026, 6, 19, 12, 10));
      await insertSessionNode(s2, nodeA);
      await insertSessionNode(s2, nodeB);
      await insertSessionNode(s2, nodeC);

      // Sesión 3: solo A
      final s3 = await insertSession(
          DateTime(2026, 6, 19, 14, 0), DateTime(2026, 6, 19, 14, 3));
      await insertSessionNode(s3, nodeA);

      final result = await useCase();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          expect(stats.totalSessions, equals(3));
          expect(stats.uniqueNodes, equals(3)); // A, B, C
          // Nodo A aparece en 3 sesiones → más frecuente
          expect(stats.mostFrequentNodeName, equals('Nodo A'));
        },
      );
    });

    // ── AVG duración: promedio de (endedAt - startedAt) ──
    test('calcula averageDuration correctamente', () async {
      // Sesión de 5 minutos
      await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));
      // Sesión de 15 minutos
      await insertSession(
          DateTime(2026, 6, 19, 11, 0), DateTime(2026, 6, 19, 11, 15));

      final result = await useCase();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          // Promedio: (5 + 15) / 2 = 10 minutos
          expect(stats.averageDuration, equals(const Duration(minutes: 10)));
        },
      );
    });

    // ── Sesiones sin endedAt no se incluyen en el promedio ──
    test('ignora sesiones sin endedAt en el cálculo de averageDuration',
        () async {
      // Sesión completada: 5 minutos
      await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));
      // Sesión sin terminar (endedAt = null) — no cuenta para promedio
      await insertSession(DateTime(2026, 6, 19, 12, 0), null);

      final result = await useCase();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          // Solo la primera sesión contribuye al promedio
          expect(stats.totalSessions, equals(2));
          expect(stats.averageDuration, equals(const Duration(minutes: 5)));
        },
      );
    });

    // ── Nodo más frecuente con empate ──
    test('nodo más frecuente con empate — retorna el de más sesiones', () async {
      final nodeA = await insertNode('AA:01', 'Nodo A');
      final nodeB = await insertNode('BB:02', 'Nodo B');

      // Ambos en las mismas 2 sesiones → empate
      final s1 = await insertSession(
          DateTime(2026, 6, 19, 10, 0), DateTime(2026, 6, 19, 10, 5));
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);

      final s2 = await insertSession(
          DateTime(2026, 6, 19, 12, 0), DateTime(2026, 6, 19, 12, 5));
      await insertSessionNode(s2, nodeA);
      await insertSessionNode(s2, nodeB);

      final result = await useCase();

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          // Ambos con 2 apariciones — cualquiera de los dos es válido
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
