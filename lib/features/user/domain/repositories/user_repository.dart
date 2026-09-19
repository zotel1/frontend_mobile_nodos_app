import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';

abstract class UserRepository {
  Future<User?> getUserProfile();

  Future<void> updateName(String name);

  Future<void> updateColor(String color);

  Future<void> createUser(User user);

  /// Asocia el perfil local con el Node real que representa
  /// este dispositivo dentro del grafo.
  Future<void> setLocalNodeId(int nodeId);
}
