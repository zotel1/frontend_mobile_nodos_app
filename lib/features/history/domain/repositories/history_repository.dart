import 'package:dartz/dartz.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/scan_session.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/session_node.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/history_stats.dart';

/// Interfaz abstracta del repositorio de historial de escaneo.
///
/// QUÉ: define los métodos que la capa de dominio necesita para acceder
/// a los datos de sesiones de escaneo, detalle de nodos y estadísticas
/// agregadas.
///
/// POR QUÉ: separa el dominio de la infraestructura de datos (Drift).
/// Los casos de uso dependen de esta abstracción, no de AppDatabase.
abstract class HistoryRepository {
  /// Consulta todas las sesiones de escaneo ordenadas por fecha de inicio
  /// descendente (más reciente primero), con conteo de nodos por sesión.
  Future<Either<Failure, List<ScanSession>>> getSessions();

  /// Consulta los nodos detectados en una sesión específica con sus
  /// valores RSSI y nivel de proximidad derivado.
  Future<Either<Failure, List<SessionNode>>> getSessionDetail(int sessionId);

  /// Calcula estadísticas agregadas de todas las sesiones de escaneo:
  /// total de sesiones, nodos únicos, duración promedio y nodo más frecuente.
  Future<Either<Failure, HistoryStats>> getStats();
}
