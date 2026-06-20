import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/session_node.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/repositories/history_repository.dart';

/// Parámetros para GetSessionDetail: el ID de la sesión.
class GetSessionDetailParams extends Equatable {
  final int sessionId;

  const GetSessionDetailParams({required this.sessionId});

  @override
  List<Object?> get props => [sessionId];
}

/// Consulta los nodos detectados en una sesión específica con sus
/// valores RSSI y nivel de proximidad.
///
/// QUÉ: delega la consulta de nodos de sesión al [HistoryRepository].
///
/// POR QUÉ: el dominio depende de la abstracción [HistoryRepository],
/// no de [AppDatabase]. El repositorio se encarga del mapeo SQL y
/// la derivación de proximidad desde RSSI.
///
/// Retorna `Either<Failure, List<SessionNode>>`.
class GetSessionDetail {
  final HistoryRepository _repository;

  const GetSessionDetail(this._repository);

  Future<Either<Failure, List<SessionNode>>> call(
      GetSessionDetailParams params) async {
    return _repository.getSessionDetail(params.sessionId);
  }
}
