import 'package:drift/drift.dart' hide Column;
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/domain/repositories/scan_session_repository.dart';

/// Implementación concreta de [ScanSessionRepository] usando Drift.
///
/// QUÉ: traduce las operaciones del dominio a queries SQL sobre las
/// tablas [ScanSessions] y [ScanSessionNodes] de Drift.
///
/// POR QUÉ: la capa data/ contiene los detalles de infraestructura.
/// El dominio no necesita saber que usamos Drift ni cómo se mapean
/// las tablas — solo conoce la interfaz [ScanSessionRepository].
class ScanSessionRepositoryImpl implements ScanSessionRepository {
  final AppDatabase _db;

  ScanSessionRepositoryImpl(this._db);

  @override
  Future<int> startSession() async {
    final now = DateTime.now();
    return _db.into(_db.scanSessions).insert(
          ScanSessionsCompanion.insert(
            startedAt: now,
            nodesDetected: 0,
          ),
        );
  }

  @override
  Future<void> endSession(int sessionId) async {
    await (_db.update(_db.scanSessions)
          ..where((t) => t.id.equals(sessionId)))
        .write(ScanSessionsCompanion(
      endedAt: Value(DateTime.now()),
    ));
  }

  @override
  Future<void> addNodesToSession(int sessionId, List<int> nodeIds) async {
    for (final nodeId in nodeIds) {
      await _db.into(_db.scanSessionNodes).insert(
            ScanSessionNodesCompanion.insert(
              sessionId: sessionId,
              nodeId: nodeId,
              rssi: -100,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }

    // Actualizar el contador de nodos en la sesión
    final count = await (_db.select(_db.scanSessionNodes)
          ..where((t) => t.sessionId.equals(sessionId)))
        .get()
        .then((rows) => rows.length);

    await (_db.update(_db.scanSessions)
          ..where((t) => t.id.equals(sessionId)))
        .write(ScanSessionsCompanion(
      nodesDetected: Value(count),
    ));
  }

  @override
  Future<int?> getActiveSession() async {
    final session = await (_db.select(_db.scanSessions)
          ..where((t) => t.endedAt.isNull())
          ..orderBy(
              [(t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return session?.id;
  }
}
