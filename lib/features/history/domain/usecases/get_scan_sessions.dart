import 'package:dartz/dartz.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart' hide ScanSession;
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/scan_session.dart';

/// Consulta todas las sesiones de escaneo ordenadas por fecha de inicio
/// descendente (más reciente primero), con conteo de nodos por sesión.
///
/// QUÉ: lee la tabla scan_sessions y hace LEFT JOIN con
/// scan_session_nodes para contar cuántos nodos fueron detectados
/// en cada sesión.
///
/// POR QUÉ: la UI de Historial necesita listar sesiones con su
/// metadata (fecha, duración, cantidad de nodos). El orden DESC
/// asegura que las sesiones más recientes aparezcan primero.
///
/// Retorna `Either<Failure, List<ScanSession>>`.
class GetScanSessions {
  final AppDatabase _db;

  const GetScanSessions(this._db);

  Future<Either<Failure, List<ScanSession>>> call() async {
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
          // nodes se mantiene vacío; se puebla en GetSessionDetail
        );
      }).toList();

      return Right(sessions);
    } catch (e) {
      return Left(UnexpectedFailure('Error al cargar sesiones: $e'));
    }
  }
}
