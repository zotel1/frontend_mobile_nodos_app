import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';

/// Contrato de acceso a los snapshots de relaciones activas recibidos
/// desde otras instalaciones Nodos.
///
/// Estas relaciones son distintas de `connections`:
///
/// - `connections`: enlaces locales persistentes.
/// - `remote_relations`: último snapshot activo declarado por otro Nodos.
///
/// Un snapshot recibido reemplaza completamente al snapshot anterior
/// perteneciente al mismo reporter.
abstract class RemoteRelationRepository {
  /// Reemplaza el snapshot activo almacenado para [reporterUuid].
  ///
  /// Si [connections] está vacío, el snapshot anterior queda eliminado.
  Future<void> replaceSnapshot({
    required String reporterUuid,
    required List<NodosGraphConnection> connections,
  });

  /// Elimina explícitamente el snapshot conocido de [reporterUuid].
  Future<void> clearSnapshot(String reporterUuid);

  /// Obtiene el último snapshot almacenado para un reporter concreto.
  Future<List<RemoteRelation>> getSnapshot(String reporterUuid);

  /// Observa todos los snapshots remotos almacenados.
  ///
  /// Más adelante permitirá que la visualización reaccione automáticamente
  /// cuando llegue información nueva desde otro dispositivo Nodos.
  Stream<List<RemoteRelation>> watchAll();
}

/// Capacidad opcional de lifecycle para invalidar la caché completa.
///
/// Se mantiene separada del contrato de lectura/escritura de snapshots para
/// no forzar a dobles de prueba ni a adaptadores históricos a implementar una
/// operación global que no necesitan.
abstract class RemoteRelationLifecycle {
  Future<void> clearAllSnapshots();
}
