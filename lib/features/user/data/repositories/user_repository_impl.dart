import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart'
    as domain;
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

class UserRepositoryImpl implements UserRepository {
  final UserLocalDataSource _dataSource;

  UserRepositoryImpl(this._dataSource);

  @override
  Future<domain.User?> getUserProfile() => _dataSource.getUser();

  @override
  Future<void> updateName(String name) => _dataSource.updateName(name);

  @override
  Future<void> updateColor(String color) => _dataSource.updateColor(color);

  @override
  Future<void> createUser(domain.User user) => _dataSource.upsertUser(user);
}
