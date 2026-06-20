import 'package:dartz/dartz.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/scan_session.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/repositories/history_repository.dart';

/// Consulta todas las sesiones de escaneo ordenadas por fecha de inicio
/// descendente (más reciente primero), con conteo de nodos por sesión.
///
/// QUÉ: delega la consulta de sesiones al [HistoryRepository].
///
/// POR QUÉ: el dominio depende de la abstracción [HistoryRepository],
/// no de [AppDatabase]. Esto permite testear el caso de uso con mocks
/// y cambiar la implementación de datos sin afectar el dominio.
///
/// Retorna `Either<Failure, List<ScanSession>>`.
class GetScanSessions {
  final HistoryRepository _repository;

  const GetScanSessions(this._repository);

  Future<Either<Failure, List<ScanSession>>> call() async {
    return _repository.getSessions();
  }
}
