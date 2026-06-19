import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/usecases/usecase.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

class UpdateUserNameParams extends Equatable {
  final String name;

  const UpdateUserNameParams({required this.name});

  @override
  List<Object> get props => [name];
}

class UpdateUserName extends UseCase<void, UpdateUserNameParams> {
  final UserRepository repository;

  UpdateUserName(this.repository);

  @override
  Future<Either<Failure, void>> call(UpdateUserNameParams params) async {
    try {
      await repository.updateName(params.name);
      return const Right(null);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
