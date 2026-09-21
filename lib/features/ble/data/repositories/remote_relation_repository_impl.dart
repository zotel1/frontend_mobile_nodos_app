import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/remote_relation_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';

/// Implementación local del repositorio de snapshots remotos.
///
/// Mantiene separadas las responsabilidades:
///
/// - el dominio trabaja con [RemoteRelationRepository];
/// - este repository delega la persistencia;
/// - [RemoteRelationDriftDataSource] conoce Drift y SQLite.
///
/// `remote_relations` representa el último snapshot activo recibido de cada
/// instalación Nodos. No debe confundirse con `connections`, que contiene
/// relaciones locales persistentes.
class RemoteRelationRepositoryImpl implements RemoteRelationRepository {
  final RemoteRelationDriftDataSource _dataSource;

  RemoteRelationRepositoryImpl(this._dataSource);

  @override
  Future<void> replaceSnapshot({
    required String reporterUuid,
    required List<NodosGraphConnection> connections,
  }) {
    return _dataSource.replaceSnapshot(
      reporterUuid: reporterUuid,
      connections: connections,
    );
  }

  @override
  Future<void> clearSnapshot(String reporterUuid) {
    return _dataSource.clearSnapshot(reporterUuid);
  }

  @override
  Future<List<RemoteRelation>> getSnapshot(String reporterUuid) {
    return _dataSource.getSnapshot(reporterUuid);
  }

  @override
  Stream<List<RemoteRelation>> watchAll() {
    return _dataSource.watchAll();
  }
}
