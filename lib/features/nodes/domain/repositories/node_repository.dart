import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

/// Contrato de repositorio para la entidad Node.
///
/// Regla arquitectónica:
/// - Node.id identifica vértices del grafo.
/// - User.id NO debe usarse como Node.id.
/// - deviceUuid representa identidad estable Nodos.
/// - bleAddress representa identidad de transporte BLE.
/// - remoteRef representa identidad namespaced de un BLE genérico
///   aprendido mediante Graph Exchange.
abstract class NodeRepository {
  Stream<List<Node>> observeNodes();

  Future<Node?> getNodeById(int id);

  /// Busca por remoteId / dirección BLE observada localmente.
  Future<Node?> getNodeByBleAddress(String bleAddress);

  /// Busca un dispositivo Nodos por su UUID estable.
  Future<Node?> getNodeByDeviceUuid(String deviceUuid);

  /// Busca un dispositivo BLE genérico conocido mediante Graph Exchange
  /// utilizando su referencia namespaced.
  ///
  /// Ejemplo:
  /// `local:reporterUuid:42`
  ///
  /// Esta referencia solamente es estable dentro del namespace del
  /// dispositivo Nodos que reportó la relación.
  Future<Node?> getNodeByRemoteRef(String remoteRef);

  /// Retorna el único nodo local persistente.
  ///
  /// Retorna null si todavía no fue creado.
  Future<Node?> getSelfNode();

  /// Inserta o actualiza un nodo.
  ///
  /// La implementación debe resolver identidad usando:
  /// 1. id, si existe;
  /// 2. deviceUuid, si existe;
  /// 3. bleAddress, si existe;
  /// 4. remoteRef, si existe.
  Future<void> upsertNode(Node node);

  /// Persiste la identidad estable obtenida mediante el protocolo Nodos.
  ///
  /// Si [deviceUuid] ya está asociado a otro Node, la implementación debe
  /// reconciliar ambas filas preservando conexiones e historial de sesiones.
  ///
  /// Retorna el Node canónico resultante.
  Future<Node?> reconcileNodeIdentity(
    int nodeId, {
    required String deviceUuid,
    required String name,
    required String color,
  });

  Future<void> updateNodeMetadata(int id, {String? name, String? color});

  /// Elimina todos los nodos.
  ///
  /// ATENCIÓN: este método será revisado en BUG-002 porque actualmente
  /// no debe utilizarse para limpiar solamente la UI de dispositivos
  /// cercanos.
  Future<void> clearAllNodes();
}