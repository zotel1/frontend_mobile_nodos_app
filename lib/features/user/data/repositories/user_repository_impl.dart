import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart'
    as domain;
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

class UserRepositoryImpl implements UserRepository {
  final UserLocalDataSource _dataSource;

  UserRepositoryImpl(this._dataSource);

  @override
  Future<domain.User?> getUserProfile() => _dataSource.getUser();

  /// T-PR2-004: Llamada delegada a datasource. Si no hay perfil de usuario,
  /// el datasource lanza [StateError] que es capturado por el use case
  /// [UpdateUserName] y convertido a [Left(UnexpectedFailure)],
  /// propagándose correctamente al BLoC que emite [UserError].
  ///
  /// Antes: el datasource hacía silent no-op → el BLoC creía que la
  /// operación fue exitosa, produciendo inconsistencia UI/BD.
  @override
  Future<void> updateName(String name) => _dataSource.updateName(name);

  /// T-PR2-004: Mismo comportamiento que [updateName].
  /// El StateError del datasource se propaga al use case y al BLoC.
  @override
  Future<void> updateColor(String color) => _dataSource.updateColor(color);

  @override
  Future<void> createUser(domain.User user) => _dataSource.upsertUser(user);
}
