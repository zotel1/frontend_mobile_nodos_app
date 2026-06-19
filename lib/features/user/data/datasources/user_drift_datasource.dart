import 'package:drift/drift.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart' as db;
import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart'
    as domain;

class UserDriftDataSource implements UserLocalDataSource {
  final db.AppDatabase _db;

  UserDriftDataSource(this._db);

  @override
  Future<domain.User?> getUser() async {
    final row = await _db.select(_db.users).getSingleOrNull();
    return row != null ? _toDomain(row) : null;
  }

  @override
  Future<void> upsertUser(domain.User user) async {
    final existing = await (_db.select(_db.users)
          ..where((t) => t.uuid.equals(user.uuid)))
        .getSingleOrNull();

    if (existing != null) {
      final companion = _toCompanion(user);
      await (_db.update(_db.users)
            ..where((t) => t.id.equals(existing.id)))
          .write(companion);
    } else {
      await _db.into(_db.users).insert(_toInsertCompanion(user));
    }
  }

  @override
  Future<void> updateName(String name) async {
    final existing = await _db.select(_db.users).getSingleOrNull();
    if (existing == null) return;
    await (_db.update(_db.users)..where((t) => t.id.equals(existing.id)))
        .write(db.UsersCompanion(name: Value(name)));
  }

  @override
  Future<void> updateColor(String color) async {
    final existing = await _db.select(_db.users).getSingleOrNull();
    if (existing == null) return;
    await (_db.update(_db.users)..where((t) => t.id.equals(existing.id)))
        .write(db.UsersCompanion(color: Value(color)));
  }

  // ── Mappers ────────────────────────────────────────────────

  domain.User _toDomain(db.User row) {
    return domain.User(
      uuid: row.uuid,
      name: row.name,
      color: row.color,
      deviceType: row.deviceType,
      createdAt: row.createdAt,
    );
  }

  db.UsersCompanion _toCompanion(domain.User user) {
    return db.UsersCompanion(
      uuid: Value(user.uuid),
      name: Value(user.name),
      color: Value(user.color),
      deviceType: Value(user.deviceType),
      createdAt: Value(user.createdAt),
    );
  }

  db.UsersCompanion _toInsertCompanion(domain.User user) {
    return db.UsersCompanion.insert(
      uuid: user.uuid,
      name: user.name,
      color: user.color,
      deviceType: user.deviceType,
      createdAt: user.createdAt,
    );
  }
}
