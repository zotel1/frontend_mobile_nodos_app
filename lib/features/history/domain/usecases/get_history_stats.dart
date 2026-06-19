import 'package:dartz/dartz.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/history_stats.dart';

/// Calcula estadísticas agregadas de todas las sesiones de escaneo
/// usando queries SQL via Drift customSelect.
///
/// QUÉ: ejecuta tres queries de agregación:
/// 1. Total de sesiones registradas (`COUNT(*)`).
/// 2. Nodos únicos detectados (`COUNT(DISTINCT node_id)` en
///    scan_session_nodes).
/// 3. Duración promedio de sesiones completadas
///    (`AVG(ended_at - started_at)` donde ended_at IS NOT NULL).
/// 4. Nodo más frecuente: `GROUP BY node_id ORDER BY COUNT(*) DESC
///    LIMIT 1`, con JOIN a nodes para el nombre.
///
/// POR QUÉ: la UI de Stats necesita métricas agregadas. SQL es más
/// eficiente que procesar en Dart para operaciones de agregación.
/// Drift customSelect mantiene type-safety dentro del ecosistema Drift.
///
/// Retorna `Either<Failure, HistoryStats>`.
class GetHistoryStats {
  final AppDatabase _db;

  const GetHistoryStats(this._db);

  Future<Either<Failure, HistoryStats>> call() async {
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
      //    Usamos julianday() para diferencia en días, convertimos a segundos.
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
      return Left(UnexpectedFailure('Error al calcular estadísticas: $e'));
    }
  }
}
