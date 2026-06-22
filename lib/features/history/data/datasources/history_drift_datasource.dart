import 'package:drift/drift.dart' hide Column;
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';

/// Datasource que encapsula las queries SQL sobre las tablas de historial.
///
/// QUÉ: contiene las operaciones crudas sobre scan_sessions,
/// scan_session_nodes y nodes usando el query builder de Drift.
///
/// POR QUÉ: separa la infraestructura SQL (datasource) de la lógica
/// de negocio (HistoryRepositoryImpl). El repositorio transforma los
/// resultados del datasource en entidades de dominio y maneja errores.
///
/// Depende de [AppDatabase] — la abstracción de Drift que agrupa
/// todas las tablas y el query builder customSelect.
class HistoryDriftDataSource {
  final AppDatabase _db;

  HistoryDriftDataSource(this._db);

  /// Retorna sesiones ordenadas por started_at DESC con conteo de nodos.
  Future<List<QueryRow>> querySessions() {
    final query = _db.customSelect(
      'SELECT s.id, s.started_at, s.ended_at, '
      'COUNT(sn.id) AS node_count '
      'FROM scan_sessions s '
      'LEFT JOIN scan_session_nodes sn ON s.id = sn.session_id '
      'GROUP BY s.id '
      'ORDER BY s.started_at DESC',
    );

    return query.get();
  }

  /// Retorna los nodos detectados en una sesión con su nombre y RSSI.
  Future<List<QueryRow>> querySessionDetail(int sessionId) {
    final query = _db.customSelect(
      'SELECT sn.id, sn.session_id, sn.node_id, sn.rssi, '
      'n.name AS node_name '
      'FROM scan_session_nodes sn '
      'JOIN nodes n ON sn.node_id = n.id '
      'WHERE sn.session_id = ?',
      variables: [Variable.withInt(sessionId)],
    );

    return query.get();
  }

  /// Cuenta el total de sesiones registradas.
  Future<int> countSessions() {
    return _db
        .customSelect('SELECT COUNT(*) AS total FROM scan_sessions')
        .getSingle()
        .then((row) => row.read<int>('total'));
  }

  /// Cuenta nodos únicos en todas las sesiones.
  Future<int> countUniqueNodes() {
    return _db
        .customSelect(
          'SELECT COUNT(DISTINCT node_id) AS unique_nodes FROM scan_session_nodes',
        )
        .getSingle()
        .then((row) => row.read<int>('unique_nodes'));
  }

  /// Calcula la duración promedio (en segundos) de sesiones completadas.
  Future<double> averageSessionSeconds() {
    return _db
        .customSelect(
          'SELECT AVG('
          'CAST(strftime(\'%s\', ended_at) AS REAL) - '
          'CAST(strftime(\'%s\', started_at) AS REAL)'
          ') AS avg_seconds '
          'FROM scan_sessions '
          'WHERE ended_at IS NOT NULL',
        )
        .getSingle()
        .then((row) => row.read<double?>('avg_seconds') ?? 0.0);
  }

  /// Retorna el nombre del nodo más frecuente entre todas las sesiones.
  Future<String?> queryMostFrequentNode() {
    return _db
        .customSelect(
          'SELECT n.name '
          'FROM scan_session_nodes sn '
          'JOIN nodes n ON sn.node_id = n.id '
          'GROUP BY sn.node_id '
          'ORDER BY COUNT(*) DESC '
          'LIMIT 1',
        )
        .getSingleOrNull()
        .then((row) => row?.read<String?>('name'));
  }
}
