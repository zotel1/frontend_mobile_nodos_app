import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart' hide ScanSession;
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/scan_session.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/session_node.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/repositories/history_repository.dart';

/// Implementación concreta de [HistoryRepository] usando Drift/AppDatabase.
///
/// QUÉ: traduce las operaciones del dominio a queries SQL sobre las
/// tablas scan_sessions, scan_session_nodes y nodes via Drift customSelect.
///
/// POR QUÉ: la capa data/ contiene los detalles de infraestructura.
/// El dominio no sabe que usamos Drift ni cómo se mapean las tablas —
/// solo conoce la interfaz [HistoryRepository].
class HistoryRepositoryImpl implements HistoryRepository {
  final AppDatabase _db;

  /// Crea el repositorio con la base de datos inyectada.
  ///
  /// [db] debe ser una instancia de [AppDatabase], típicamente
  /// registrada como LazySingleton en el contenedor de DI.
  HistoryRepositoryImpl(this._db);

  @override
  Future<Either<Failure, List<ScanSession>>> getSessions() async {
    try {
      // Consulta sesiones con conteo de nodos via LEFT JOIN
      final query = _db.customSelect(
        'SELECT s.id, s.started_at, s.ended_at, '
        'COUNT(sn.id) AS node_count '
        'FROM scan_sessions s '
        'LEFT JOIN scan_session_nodes sn ON s.id = sn.session_id '
        'GROUP BY s.id '
        'ORDER BY s.started_at DESC',
      );

      final rows = await query.get();

      final sessions = rows.map((row) {
        return ScanSession(
          id: row.read<int>('id'),
          startedAt: row.read<DateTime>('started_at'),
          endedAt: row.read<DateTime?>('ended_at'),
          nodeCount: row.read<int>('node_count'),
        );
      }).toList();

      return Right(sessions);
    } catch (e) {
      return Left(UnexpectedFailure('Error al cargar sesiones: $e'));
    }
  }

  @override
  Future<Either<Failure, List<SessionNode>>> getSessionDetail(
      int sessionId) async {
    try {
      final query = _db.customSelect(
        'SELECT sn.id, sn.session_id, sn.node_id, sn.rssi, '
        'n.name AS node_name '
        'FROM scan_session_nodes sn '
        'JOIN nodes n ON sn.node_id = n.id '
        'WHERE sn.session_id = ?',
        variables: [Variable.withInt(sessionId)],
      );

      final rows = await query.get();

      final nodes = rows.map((row) {
        final rssi = row.read<int>('rssi');
        final proximity = rssiToProximity(rssi);

        // Mapear el nivel de proximidad a string legible
        String proximityLevel;
        switch (proximity) {
          case ProximityLevel.close:
            proximityLevel = 'close';
          case ProximityLevel.medium:
            proximityLevel = 'medium';
          case ProximityLevel.far:
            proximityLevel = 'far';
        }

        return SessionNode(
          id: row.read<int>('id'),
          sessionId: row.read<int>('session_id'),
          nodeId: row.read<int>('node_id'),
          rssi: rssi,
          nodeName: row.read<String?>('node_name'),
          proximityLevel: proximityLevel,
        );
      }).toList();

      return Right(nodes);
    } catch (e) {
      return Left(UnexpectedFailure('Error al cargar detalle: $e'));
    }
  }

  @override
  Future<Either<Failure, HistoryStats>> getStats() async {
    try {
      // 1. Total de sesiones
      final totalResult = await _db.customSelect(
        'SELECT COUNT(*) AS total FROM scan_sessions',
      ).getSingle();
      final totalSessions = totalResult.read<int>('total');

      // 2. Nodos únicos detectados
      final uniqueResult = await _db.customSelect(
        'SELECT COUNT(DISTINCT node_id) AS unique_nodes FROM scan_session_nodes',
      ).getSingle();
      final uniqueNodes = uniqueResult.read<int>('unique_nodes');

      // 3. Duración promedio de sesiones completadas
      final avgResult = await _db.customSelect(
        'SELECT AVG('
        'CAST(strftime(\'%s\', ended_at) AS REAL) - '
        'CAST(strftime(\'%s\', started_at) AS REAL)'
        ') AS avg_seconds '
        'FROM scan_sessions '
        'WHERE ended_at IS NOT NULL',
      ).getSingle();
      final avgSeconds = avgResult.read<double?>('avg_seconds') ?? 0.0;
      final averageDuration = Duration(seconds: avgSeconds.round());

      // 4. Nodo más frecuente
      String? mostFrequentNodeName;
      try {
        final freqResult = await _db.customSelect(
          'SELECT n.name '
          'FROM scan_session_nodes sn '
          'JOIN nodes n ON sn.node_id = n.id '
          'GROUP BY sn.node_id '
          'ORDER BY COUNT(*) DESC '
          'LIMIT 1',
        ).getSingle();
        mostFrequentNodeName = freqResult.read<String?>('name');
      } catch (_) {
        // Si no hay nodos, getSingle() fallará — es esperado.
        mostFrequentNodeName = null;
      }

      return Right(HistoryStats(
        totalSessions: totalSessions,
        uniqueNodes: uniqueNodes,
        averageDuration: averageDuration,
        mostFrequentNodeName: mostFrequentNodeName,
      ));
    } catch (e) {
      return Left(
          UnexpectedFailure('Error al calcular estadísticas: $e'));
    }
  }
}
