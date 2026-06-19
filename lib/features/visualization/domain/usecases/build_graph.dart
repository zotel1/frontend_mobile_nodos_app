import 'package:dartz/dartz.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/repositories/graph_repository.dart';

/// Caso de uso: construye el grafo de visualización para una sesión de escaneo.
///
/// Delega en [GraphRepository] la obtención de nodos y aristas, y
/// envuelve el resultado en un Either para manejo de errores.
/// El LayoutResult retornado contiene posiciones iniciales que serán
/// refinadas por CalculateLayout (PR2) usando Fruchterman-Reingold.
class BuildGraph {
  final GraphRepository _repository;

  const BuildGraph(this._repository);

  /// Construye el grafo para la sesión de escaneo [scanSessionId].
  ///
  /// Retorna [Right] con el LayoutResult si la construcción es exitosa,
  /// o [Left] con un Failure si ocurre un error inesperado.
  Future<Either<Failure, LayoutResult>> call(int scanSessionId) async {
    try {
      final result = await _repository.buildGraph(scanSessionId);
      return Right(result);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
