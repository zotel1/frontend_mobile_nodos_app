import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/data/datasources/scan_session_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/domain/repositories/scan_session_repository.dart';

/// Helper para truncar precisión de DateTime a milisegundos (precisión SQLite).
DateTime _ms(DateTime dt) =>
    DateTime.fromMillisecondsSinceEpoch(dt.millisecondsSinceEpoch);

Future<int> _insertNode(AppDatabase database, String address) async {
  final now = _ms(DateTime.now());
  return database
      .into(database.nodes)
      .insert(
        NodesCompanion(
          bleAddress: Value(address),
          firstSeen: Value(now),
          lastSeen: Value(now),
          rssiHistory: const Value('[-55]'),
        ),
      );
}

Future<List<int>> _sessionNodeIds(AppDatabase database, int sessionId) async {
  final rows = await (database.select(
    database.scanSessionNodes,
  )..where((row) => row.sessionId.equals(sessionId))).get();
  return rows.map((row) => row.nodeId).toList();
}

void main() {
  late AppDatabase database;
  late ScanSessionRepository repository;

  setUp(() async {
    database = AppDatabase.inMemory();
    repository = ScanSessionRepositoryImpl(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('ScanSessionRepositoryImpl (T-PR3-003)', () {
    // ── Tests de transacción y atomicidad ─────────────────────────

    test('creates session and returns valid id', () async {
      final sessionId = await repository.startSession();
      expect(sessionId, greaterThan(0));
    });

    test('addNodesToSession en transaction — atomicidad exitosa', () async {
      final now = _ms(DateTime.now());

      // Crear sesión
      final sessionId = await repository.startSession();

      // Crear nodos directamente en la DB
      final nodeId1 = await database
          .into(database.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('SE:SS:IO:N0:DE:01'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-55]'),
            ),
          );
      final nodeId2 = await database
          .into(database.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('SE:SS:IO:N0:DE:02'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-65]'),
            ),
          );

      // QUÉ: addNodesToSession debe insertar los nodos y actualizar
      // nodesDetected dentro de una transacción atómica.
      // POR QUÉ: si cualquier insert falla, toda la operación debe
      // hacer rollback para mantener la consistencia de datos.
      await repository.addNodesToSession(sessionId, [nodeId1, nodeId2]);

      // Verificar que ambas filas existen en scan_session_nodes
      final rows = await database.select(database.scanSessionNodes).get();
      expect(
        rows,
        hasLength(2),
        reason: 'Debe insertar ambas filas en la transacción',
      );

      // Verificar que nodesDetected se actualizó
      final session = await (database.select(
        database.scanSessions,
      )..where((s) => s.id.equals(sessionId))).getSingle();
      expect(
        session.nodesDetected,
        2,
        reason: 'nodesDetected debe reflejar el conteo real',
      );
    });

    test(
      'addNodesToSession — rollback en nodo inexistente → 0 filas',
      () async {
        // QUÉ: si se intenta insertar un nodeId que no existe en la tabla
        // nodes, la FK constraint debe fallar y toda la transacción hace
        // rollback.
        // POR QUÉ: garantiza que no queden referencias huérfanas en
        // scan_session_nodes.

        final sessionId = await repository.startSession();

        // nodeId 999 no existe en la tabla nodes
        try {
          await repository.addNodesToSession(sessionId, [999]);
          fail('Debería haber lanzado excepción por FK constraint');
        } catch (_) {
          // Esperado: rollback automático
        }

        // Verificar que ninguna fila fue insertada
        final rows = await database.select(database.scanSessionNodes).get();
        expect(
          rows,
          isEmpty,
          reason:
              'La transacción debe hacer rollback completo:'
              ' 0 filas insertadas tras FK violation',
        );
      },
    );

    test('addNodesToSession con lista vacía no inserta nada', () async {
      final sessionId = await repository.startSession();

      // QUÉ: addNodesToSession con lista vacía no debe insertar nada
      // ni crashear.
      await repository.addNodesToSession(sessionId, []);

      final rows = await database.select(database.scanSessionNodes).get();
      expect(rows, isEmpty);
    });

    test(
      'addNodesToSession — insertOrIgnore evita duplicados sin error',
      () async {
        final now = _ms(DateTime.now());
        final sessionId = await repository.startSession();

        final nodeId = await database
            .into(database.nodes)
            .insert(
              NodesCompanion(
                bleAddress: const Value('DU:PL:IC:AT:ED:01'),
                firstSeen: Value(now),
                lastSeen: Value(now),
                rssiHistory: const Value('[-55]'),
              ),
            );

        // Primer insert
        await repository.addNodesToSession(sessionId, [nodeId]);

        // Segundo insert con el mismo par (sessionId, nodeId)
        // insertOrIgnore debe ignorarlo silenciosamente
        await repository.addNodesToSession(sessionId, [nodeId]);

        final rows = await database.select(database.scanSessionNodes).get();
        expect(
          rows,
          hasLength(1),
          reason: 'insertOrIgnore debe evitar duplicados sin lanzar error',
        );
      },
    );

    test('addNodesToSession conserva el último RSSI observado', () async {
      final sessionId = await repository.startSession();
      final nodeId = await database
          .into(database.nodes)
          .insert(
            NodesCompanion(
              bleAddress: const Value('RS:SI:HI:ST:OR:01'),
              firstSeen: Value(DateTime.now()),
              lastSeen: Value(DateTime.now()),
            ),
          );

      await repository.addNodesToSession(
        sessionId,
        [nodeId],
        rssiByNode: {nodeId: -48},
      );
      await repository.addNodesToSession(
        sessionId,
        [nodeId],
        rssiByNode: {nodeId: -72},
      );

      final rows = await database.select(database.scanSessionNodes).get();
      expect(rows, hasLength(1));
      expect(rows.single.rssi, -72);
    });

    test('endSession actualiza endedAt correctamente', () async {
      final sessionId = await repository.startSession();

      await repository.endSession(sessionId);

      final session = await (database.select(
        database.scanSessions,
      )..where((s) => s.id.equals(sessionId))).getSingle();
      expect(session.endedAt, isNotNull);
    });

    test('getActiveSession retorna sesión sin endedAt', () async {
      final sessionId = await repository.startSession();

      final activeId = await repository.getActiveSession();
      expect(activeId, equals(sessionId));
    });

    test('getActiveSession retorna null cuando todas tienen endedAt', () async {
      final sessionId = await repository.startSession();
      await repository.endSession(sessionId);

      final activeId = await repository.getActiveSession();
      expect(activeId, isNull);
    });

    test('FEAT-004B A: la sesión solo contiene nodos observados', () async {
      final nodeA = await _insertNode(database, 'FEAT:B:A:01');
      final nodeB = await _insertNode(database, 'FEAT:B:B:01');
      final nodeC = await _insertNode(database, 'FEAT:B:C:01');
      final sessionId = await repository.startSession();

      await repository.addNodesToSession(sessionId, [nodeA, nodeC]);

      final ids = await _sessionNodeIds(database, sessionId);
      expect(ids, containsAll(<int>[nodeA, nodeC]));
      expect(ids, isNot(contains(nodeB)));
      expect(ids, hasLength(2));
    });

    test(
      'FEAT-004B B: detecciones repetidas mantienen nodeCount en 1',
      () async {
        final nodeA = await _insertNode(database, 'FEAT:B:REPEAT');
        final sessionId = await repository.startSession();

        await repository.addNodesToSession(sessionId, [nodeA]);
        await repository.addNodesToSession(sessionId, [nodeA]);
        await repository.addNodesToSession(sessionId, [nodeA]);

        final ids = await _sessionNodeIds(database, sessionId);
        final session = await (database.select(
          database.scanSessions,
        )..where((row) => row.id.equals(sessionId))).getSingle();
        expect(ids, [nodeA]);
        expect(session.nodesDetected, 1);
      },
    );

    test(
      'FEAT-004B C: la sesión incorpora nodos de forma incremental',
      () async {
        final nodeA = await _insertNode(database, 'FEAT:B:INCREMENT:A');
        final nodeC = await _insertNode(database, 'FEAT:B:INCREMENT:C');
        final sessionId = await repository.startSession();

        await repository.addNodesToSession(sessionId, [nodeA]);
        await repository.addNodesToSession(sessionId, [nodeC]);

        final ids = await _sessionNodeIds(database, sessionId);
        final session = await (database.select(
          database.scanSessions,
        )..where((row) => row.id.equals(sessionId))).getSingle();
        expect(ids, containsAll(<int>[nodeA, nodeC]));
        expect(ids, hasLength(2));
        expect(session.nodesDetected, 2);
      },
    );

    test(
      'FEAT-004B D: una nueva sesión no hereda miembros anteriores',
      () async {
        final nodeA = await _insertNode(database, 'FEAT:B:SESSION1:A');
        final nodeC = await _insertNode(database, 'FEAT:B:SESSION1:C');
        final nodeB = await _insertNode(database, 'FEAT:B:SESSION2:B');
        final firstSession = await repository.startSession();
        await repository.addNodesToSession(firstSession, [nodeA, nodeC]);
        await repository.endSession(firstSession);

        final secondSession = await repository.startSession();
        await repository.addNodesToSession(secondSession, [nodeB]);

        expect(
          await _sessionNodeIds(database, firstSession),
          containsAll(<int>[nodeA, nodeC]),
        );
        expect(await _sessionNodeIds(database, secondSession), [nodeB]);
      },
    );

    test('FEAT-004B E: startSession cierra sesiones huérfanas', () async {
      final orphanStartedAt = _ms(
        DateTime.now().subtract(const Duration(hours: 1)),
      );
      final orphanId = await database
          .into(database.scanSessions)
          .insert(
            ScanSessionsCompanion.insert(
              startedAt: orphanStartedAt,
              nodesDetected: 0,
            ),
          );

      final newSessionId = await repository.startSession();
      final orphan = await (database.select(
        database.scanSessions,
      )..where((row) => row.id.equals(orphanId))).getSingle();
      final activeRows = await (database.select(
        database.scanSessions,
      )..where((row) => row.endedAt.isNull())).get();

      expect(orphan.endedAt, isNotNull);
      expect(newSessionId, isNot(orphanId));
      expect(activeRows, hasLength(1));
      expect(activeRows.single.id, newSessionId);
      expect(await repository.getActiveSession(), newSessionId);
    });

    test(
      'FEAT-004B F: finalizar la sesión conserva el catálogo nodes',
      () async {
        final nodeA = await _insertNode(database, 'FEAT:B:HISTORY');
        final sessionId = await repository.startSession();
        await repository.addNodesToSession(sessionId, [nodeA]);
        await repository.endSession(sessionId);

        final node = await (database.select(
          database.nodes,
        )..where((row) => row.id.equals(nodeA))).getSingle();
        expect(node.id, nodeA);
        expect(await repository.getActiveSession(), isNull);
      },
    );
  });
}
