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
  /// ARCH-001:
  /// el self-node es una entidad Node persistente real y no utiliza id=-1.
  ///
  /// Los parámetros [myDeviceUuid], [userName] y [userColor] permanecen
  /// temporalmente por compatibilidad mientras se completa la migración
  /// de los consumidores del grafo.
  Future<Either<Failure, LayoutResult>> call(
    int scanSessionId, {
    String? myDeviceUuid,
    String? userName,
    String? userColor,
  }) async {
    try {
      final result = await _repository.buildGraph(
        scanSessionId,
        myDeviceUuid: myDeviceUuid,
        userName: userName,
        userColor: userColor,
      );
      return Right(result);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
