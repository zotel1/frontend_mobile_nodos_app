import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/usecases/usecase.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';

class GetNodeDetailParams extends Equatable {
  final int id;

  const GetNodeDetailParams({required this.id});

  @override
  List<Object> get props => [id];
}

class GetNodeDetail extends UseCase<Node, GetNodeDetailParams> {
  final NodeRepository repository;

  GetNodeDetail(this.repository);

  @override
  Future<Either<Failure, Node>> call(GetNodeDetailParams params) async {
    try {
      final node = await repository.getNodeById(params.id);
      if (node != null) {
        return Right(node);
      }
      return Left(CacheFailure('Node not found'));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
