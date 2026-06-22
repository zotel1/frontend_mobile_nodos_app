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
    // PR4: .limit(1) hace explícito que solo esperamos una fila.
    // QUÉ: agrega LIMIT 1 a la query SQL generada por Drift.
    // POR QUÉ: getSingleOrNull ya lanza si hay más de una fila,
    // pero sin LIMIT el plan de ejecución podría escanear toda la
    // tabla. Con CHECK(id=1) solo hay una fila, pero .limit(1)
    // es documentación ejecutable del contrato.
    final row = await (_db.select(_db.users)..limit(1)).getSingleOrNull();
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
    // T-PR2-004: Lanzar StateError en lugar de silent no-op cuando
    // no hay perfil de usuario creado.
    //
    // QUÉ: si la tabla users está vacía, lanzamos StateError con
    // mensaje descriptivo. El repository que llama a este datasource
    // captura la excepción y la convierte en Left(Failure).
    //
    // POR QUÉ: el código anterior hacía `if (existing == null) return;`
    // → el BLoC creía que la operación fue exitosa pero el dato nunca
    // se persistió. Esto producía UI inconsistente: el usuario veía
    // su nombre "cambiado" en pantalla pero al recargar volvía al
    // estado anterior (porque el cambio nunca llegó a la BD).
    if (existing == null) {
      throw StateError('No hay perfil de usuario creado. '
          'Usá createUser() primero para inicializar el perfil.');
    }
    await (_db.update(_db.users)..where((t) => t.id.equals(existing.id)))
        .write(db.UsersCompanion(name: Value(name)));
  }

  @override
  Future<void> updateColor(String color) async {
    final existing = await _db.select(_db.users).getSingleOrNull();
    // T-PR2-004: StateError en lugar de silent no-op (mismo rationale
    // que updateName arriba).
    if (existing == null) {
      throw StateError('No hay perfil de usuario creado. '
          'Usá createUser() primero para inicializar el perfil.');
    }
    await (_db.update(_db.users)..where((t) => t.id.equals(existing.id)))
        .write(db.UsersCompanion(color: Value(color)));
  }

  // ── Mappers ────────────────────────────────────────────────

  domain.User _toDomain(db.User row) {
    return domain.User(
      id: row.id,
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
