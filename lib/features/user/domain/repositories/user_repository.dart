import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';

abstract class UserRepository {
  Future<User?> getUserProfile();
  Future<void> updateName(String name);
  Future<void> updateColor(String color);
  Future<void> createUser(User user);
}
