import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';

abstract class UserLocalDataSource {
  Future<User?> getUser();

  Future<void> upsertUser(User user);

  Future<void> updateName(String name);

  Future<void> updateColor(String color);

  /// Persiste la referencia Users.localNodeId → Nodes.id.
  Future<void> setLocalNodeId(int nodeId);
}
