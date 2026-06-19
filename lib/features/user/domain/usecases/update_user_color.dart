import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/usecases/usecase.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

class UpdateUserColorParams extends Equatable {
  final String color;

  const UpdateUserColorParams({required this.color});

  @override
  List<Object> get props => [color];
}

class UpdateUserColor extends UseCase<void, UpdateUserColorParams> {
  final UserRepository repository;

  UpdateUserColor(this.repository);

  @override
  Future<Either<Failure, void>> call(UpdateUserColorParams params) async {
    try {
      await repository.updateColor(params.color);
      return const Right(null);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
