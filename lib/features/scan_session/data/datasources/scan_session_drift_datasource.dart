import 'package:drift/drift.dart' hide Column;
import 'dart:convert';
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
  static const _unknownRssiFallback = -100;
  final AppDatabase _db;

  ScanSessionRepositoryImpl(this._db);

  @override
  Future<int> startSession() async {
    final now = DateTime.now();

    // Un cierre inesperado puede dejar sesiones huérfanas. La operación
    // transaccional garantiza que nunca quede más de una sesión activa.
    return _db.transaction(() async {
      await (_db.update(_db.scanSessions)
            ..where((session) => session.endedAt.isNull()))
          .write(ScanSessionsCompanion(endedAt: Value(now)));

      return _db
          .into(_db.scanSessions)
          .insert(
            ScanSessionsCompanion.insert(startedAt: now, nodesDetected: 0),
          );
    });
  }

  @override
  Future<void> endSession(int sessionId) async {
    await (_db.update(_db.scanSessions)..where((t) => t.id.equals(sessionId)))
        .write(ScanSessionsCompanion(endedAt: Value(DateTime.now())));
  }

  @override
  Future<void> addNodesToSession(
    int sessionId,
    List<int> nodeIds, {
    Map<int, int> rssiByNode = const {},
  }) async {
    // R17: envolver inserts + count update en una transaction
    // para garantizar atomicidad. Si cualquier operación falla,
    // todas las escrituras hacen rollback automáticamente.
    await _db.transaction(() async {
      for (final nodeId in nodeIds) {
        final rssi = rssiByNode[nodeId] ?? await _fallbackRssi(nodeId);
        final existing =
            await (_db.select(_db.scanSessionNodes)..where(
                  (row) =>
                      row.sessionId.equals(sessionId) &
                      row.nodeId.equals(nodeId),
                ))
                .getSingleOrNull();
        if (existing == null) {
          await _db
              .into(_db.scanSessionNodes)
              .insert(
                ScanSessionNodesCompanion.insert(
                  sessionId: sessionId,
                  nodeId: nodeId,
                  rssi: rssi,
                ),
              );
        } else {
          await (_db.update(_db.scanSessionNodes)
                ..where((row) => row.id.equals(existing.id)))
              .write(ScanSessionNodesCompanion(rssi: Value(rssi)));
        }
      }

      // Actualizar el contador de nodos en la sesión
      final count =
          await (_db.select(_db.scanSessionNodes)
                ..where((t) => t.sessionId.equals(sessionId)))
              .get()
              .then((rows) => rows.length);

      await (_db.update(_db.scanSessions)..where((t) => t.id.equals(sessionId)))
          .write(ScanSessionsCompanion(nodesDetected: Value(count)));
    });
  }

  Future<int> _fallbackRssi(int nodeId) async {
    final node = await (_db.select(
      _db.nodes,
    )..where((row) => row.id.equals(nodeId))).getSingleOrNull();
    if (node?.lastRssi != null) return node!.lastRssi!;
    if (node?.rssiHistory != null) {
      final values = jsonDecode(node!.rssiHistory!) as List<dynamic>;
      if (values.isNotEmpty) return (values.last as num).round();
    }
    // Legacy callers may not have an observation yet. Keep the historical
    // far-distance fallback, while production scanning passes the real RSSI.
    return _unknownRssiFallback;
  }

  @override
  Future<int?> getActiveSession() async {
    final session =
        await (_db.select(_db.scanSessions)
              ..where((t) => t.endedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.startedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();
    return session?.id;
  }
}
