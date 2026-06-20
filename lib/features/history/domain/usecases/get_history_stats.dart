import 'package:dartz/dartz.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/repositories/history_repository.dart';

/// Calcula estadísticas agregadas de todas las sesiones de escaneo.
///
/// QUÉ: delega el cálculo de estadísticas al [HistoryRepository].
///
/// POR QUÉ: el dominio depende de la abstracción [HistoryRepository],
/// no de [AppDatabase]. El repositorio ejecuta las queries de agregación
/// (COUNT, AVG, GROUP BY) y retorna la entidad [HistoryStats].
///
/// Retorna `Either<Failure, HistoryStats>`.
class GetHistoryStats {
  final HistoryRepository _repository;

  const GetHistoryStats(this._repository);

  Future<Either<Failure, HistoryStats>> call() async {
    return _repository.getStats();
  }
}
