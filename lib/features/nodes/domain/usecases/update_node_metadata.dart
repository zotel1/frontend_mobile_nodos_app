import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/usecases/usecase.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';

class UpdateNodeMetadataParams extends Equatable {
  final int id;
  final String? name;
  final String? color;

  const UpdateNodeMetadataParams({required this.id, this.name, this.color});

  @override
  List<Object?> get props => [id, name, color];
}

class UpdateNodeMetadata extends UseCase<void, UpdateNodeMetadataParams> {
  final NodeRepository repository;

  UpdateNodeMetadata(this.repository);

  @override
  Future<Either<Failure, void>> call(UpdateNodeMetadataParams params) async {
    try {
      await repository.updateNodeMetadata(
        params.id,
        name: params.name,
        color: params.color,
      );
      return const Right(null);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
