import 'package:dartz/dartz.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/history/data/datasources/history_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/scan_session.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/session_node.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/repositories/history_repository.dart';

/// Implementación concreta de [HistoryRepository] usando [HistoryDriftDataSource].
///
/// QUÉ: traduce las operaciones del dominio a consultas via el datasource,
/// transformando los resultados crudos en entidades de dominio y manejando
/// errores de infraestructura.
///
/// POR QUÉ: el repositorio depende de la abstracción del datasource, no
/// de [AppDatabase]. Esto permite testear el repositorio con un datasource
/// mock y mantener la lógica de negocio desacoplada del ORM.
class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryDriftDataSource _dataSource;

  /// Crea el repositorio con el datasource inyectado.
  HistoryRepositoryImpl(this._dataSource);

  @override
  Future<Either<Failure, List<ScanSession>>> getSessions() async {
    try {
      final rows = await _dataSource.querySessions();

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
      final rows = await _dataSource.querySessionDetail(sessionId);

      final nodes = rows.map((row) {
        final rssi = row.read<int>('rssi');
        final proximity = rssiToProximity(rssi);

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
      final totalSessions = await _dataSource.countSessions();
      final uniqueNodes = await _dataSource.countUniqueNodes();
      final avgSeconds = await _dataSource.averageSessionSeconds();
      final averageDuration = Duration(seconds: avgSeconds.round());

      String? mostFrequentNodeName;
      try {
        mostFrequentNodeName = await _dataSource.queryMostFrequentNode();
      } catch (_) {
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
