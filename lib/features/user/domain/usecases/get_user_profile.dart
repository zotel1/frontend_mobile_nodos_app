import 'package:dartz/dartz.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/usecases/usecase.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

class GetUserProfile extends UseCase<User, NoParams> {
  final UserRepository repository;

  GetUserProfile(this.repository);

  @override
  Future<Either<Failure, User>> call(NoParams params) async {
    try {
      final user = await repository.getUserProfile();
      if (user != null) {
        return Right(user);
      }
      return Left(CacheFailure('No user profile found'));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
