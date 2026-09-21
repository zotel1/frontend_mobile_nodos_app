import 'package:drift/drift.dart';

import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';

/// Persistencia local de los snapshots de grafo recibidos desde otras
/// instalaciones Nodos.
///
/// IMPORTANTE:
///
/// `remote_relations` NO representa historial de conexiones.
///
/// Cada conjunto de filas perteneciente a un [reporterUuid] representa el
/// último snapshot activo recibido desde esa instalación.
///
/// Por ejemplo, si anteriormente A25 informó:
///
///   A25 -> Watch
///   A25 -> Charge 3
///
/// y posteriormente informa:
///
///   A25 -> Charge 3
///
/// las filas anteriores de A25 se reemplazan completamente y Watch deja de
/// formar parte del snapshot remoto.
///
/// Un snapshot vacío también es válido y elimina todas las relaciones
/// anteriormente reportadas por esa instalación.
class RemoteRelationDriftDataSource {
  final AppDatabase _db;

  RemoteRelationDriftDataSource(this._db);

  /// Reemplaza de forma atómica el snapshot activo perteneciente a
  /// [reporterUuid].
  ///
  /// La operación completa ocurre dentro de una única transacción:
  ///
  /// 1. elimina el snapshot anterior del reporter;
  /// 2. inserta las relaciones del nuevo snapshot;
  /// 3. confirma todos los cambios juntos.
  ///
  /// Si [connections] está vacío, solamente se ejecuta la eliminación.
  Future<void> replaceSnapshot({
    required String reporterUuid,
    required List<NodosGraphConnection> connections,
  }) async {
    final normalizedReporterUuid = reporterUuid.trim();

    if (normalizedReporterUuid.isEmpty) {
      throw ArgumentError.value(
        reporterUuid,
        'reporterUuid',
        'El UUID del reporter no puede estar vacío.',
      );
    }

    // El payload de dominio ya valida referencias duplicadas.
    // Esta comprobación adicional protege al datasource si en el futuro
    // también es utilizado desde otro punto de entrada.
    final remoteRefs = <String>{};

    for (final connection in connections) {
      final remoteRef = connection.ref.trim();

      if (remoteRef.isEmpty) {
        throw ArgumentError(
          'Una relación remota no puede tener remoteRef vacío.',
        );
      }

      if (!remoteRefs.add(remoteRef)) {
        throw ArgumentError(
          'El snapshot contiene remoteRef duplicado: $remoteRef',
        );
      }

      _validateConnection(
        reporterUuid: normalizedReporterUuid,
        connection: connection,
      );
    }

    final receivedAt = DateTime.now();

    await _db.transaction(() async {
      // Un payload representa el snapshot COMPLETO del reporter.
      //
      // Por eso no hacemos upsert individual: cualquier relación que ya no
      // venga en el nuevo payload debe desaparecer.
      await (_db.delete(_db.remoteRelations)..where(
            (table) => table.reporterUuid.equals(normalizedReporterUuid),
          ))
          .go();

      for (final connection in connections) {
        await _db
            .into(_db.remoteRelations)
            .insert(
              RemoteRelationsCompanion.insert(
                reporterUuid: normalizedReporterUuid,
                remoteRef: connection.ref.trim(),
                remoteDeviceUuid: Value(
                  _normalizeNullable(connection.deviceUuid),
                ),
                remoteName: Value(_normalizeNullable(connection.name)),
                remoteColor: Value(_normalizeNullable(connection.color)),
                remoteDeviceType: Value(
                  _normalizeNullable(connection.deviceType),
                ),
                lastReceivedAt: receivedAt,
              ),
            );
      }
    });
  }

  /// Elimina el snapshot almacenado para una instalación concreta.
  ///
  /// Es diferente de [replaceSnapshot] únicamente a nivel semántico:
  /// permite expresar explícitamente que queremos descartar el snapshot
  /// conocido de un reporter.
  Future<void> clearSnapshot(String reporterUuid) async {
    final normalizedReporterUuid = reporterUuid.trim();

    if (normalizedReporterUuid.isEmpty) {
      return;
    }

    await (_db.delete(_db.remoteRelations)
          ..where((table) => table.reporterUuid.equals(normalizedReporterUuid)))
        .go();
  }

  /// Devuelve las relaciones actualmente almacenadas para [reporterUuid].
  ///
  /// Será útil posteriormente para integrar estos snapshots en la
  /// visualización del grafo.
  Future<List<RemoteRelation>> getSnapshot(String reporterUuid) async {
    final normalizedReporterUuid = reporterUuid.trim();

    if (normalizedReporterUuid.isEmpty) {
      return const <RemoteRelation>[];
    }

    return (_db.select(_db.remoteRelations)
          ..where((table) => table.reporterUuid.equals(normalizedReporterUuid))
          ..orderBy([(table) => OrderingTerm.asc(table.remoteRef)]))
        .get();
  }

  /// Observa todos los snapshots remotos almacenados.
  ///
  /// GraphRepository podrá utilizar este stream más adelante para reconstruir
  /// automáticamente la visualización cuando llegue un nuevo snapshot.
  Stream<List<RemoteRelation>> watchAll() {
    return (_db.select(_db.remoteRelations)..orderBy([
          (table) => OrderingTerm.asc(table.reporterUuid),
          (table) => OrderingTerm.asc(table.remoteRef),
        ]))
        .watch();
  }

  void _validateConnection({
    required String reporterUuid,
    required NodosGraphConnection connection,
  }) {
    final remoteRef = connection.ref.trim();

    switch (connection.kind) {
      case NodosGraphNodeKind.nodos:
        final deviceUuid = connection.deviceUuid?.trim();

        if (deviceUuid == null || deviceUuid.isEmpty) {
          throw ArgumentError('Una relación Nodos debe contener deviceUuid.');
        }

        if (deviceUuid == reporterUuid) {
          throw ArgumentError(
            'El reporter no puede declararse como su propio vecino.',
          );
        }

        if (remoteRef != 'nodos:$deviceUuid') {
          throw ArgumentError('remoteRef no coincide con el deviceUuid Nodos.');
        }

      case NodosGraphNodeKind.generic:
        final expectedPrefix = 'local:$reporterUuid:';

        if (!remoteRef.startsWith(expectedPrefix)) {
          throw ArgumentError(
            'Una relación BLE genérica debe pertenecer al namespace '
            'del reporter.',
          );
        }

        if (connection.deviceUuid != null) {
          throw ArgumentError(
            'Una relación BLE genérica no debe contener deviceUuid.',
          );
        }
    }
  }

  String? _normalizeNullable(String? value) {
    final normalized = value?.trim();

    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }
}
