import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/data/datasources/scan_session_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/domain/repositories/scan_session_repository.dart';

/// Helper para truncar precisión de DateTime a milisegundos (precisión SQLite).
DateTime _ms(DateTime dt) =>
    DateTime.fromMillisecondsSinceEpoch(dt.millisecondsSinceEpoch);

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
      final nodeId1 = await database.into(database.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('SE:SS:IO:N0:DE:01'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('[-55]'),
            ),
          );
      final nodeId2 = await database.into(database.nodes).insert(
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
      expect(rows, hasLength(2),
          reason: 'Debe insertar ambas filas en la transacción');

      // Verificar que nodesDetected se actualizó
      final session = await (database.select(database.scanSessions)
            ..where((s) => s.id.equals(sessionId)))
          .getSingle();
      expect(session.nodesDetected, 2,
          reason: 'nodesDetected debe reflejar el conteo real');
    });

    test('addNodesToSession — rollback en nodo inexistente → 0 filas', () async {
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
      expect(rows, isEmpty,
          reason: 'La transacción debe hacer rollback completo:'
              ' 0 filas insertadas tras FK violation');
    });

    test('addNodesToSession con lista vacía no inserta nada', () async {
      final sessionId = await repository.startSession();

      // QUÉ: addNodesToSession con lista vacía no debe insertar nada
      // ni crashear.
      await repository.addNodesToSession(sessionId, []);

      final rows = await database.select(database.scanSessionNodes).get();
      expect(rows, isEmpty);
    });

    test('addNodesToSession — insertOrIgnore evita duplicados sin error', () async {
      final now = _ms(DateTime.now());
      final sessionId = await repository.startSession();

      final nodeId = await database.into(database.nodes).insert(
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
      expect(rows, hasLength(1),
          reason: 'insertOrIgnore debe evitar duplicados sin lanzar error');
    });

    test('endSession actualiza endedAt correctamente', () async {
      final sessionId = await repository.startSession();

      await repository.endSession(sessionId);

      final session = await (database.select(database.scanSessions)
            ..where((s) => s.id.equals(sessionId)))
          .getSingle();
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
  });
}
