import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

/// Contrato de persistencia local de Node.
abstract class NodeLocalDataSource {
  Stream<List<Node>> watchNodes();

  Future<Node?> getNodeById(int id);

  Future<Node?> getNodeByBleAddress(String bleAddress);

  Future<Node?> getNodeByDeviceUuid(String deviceUuid);

  Future<Node?> getSelfNode();

  Future<void> upsertNode(Node node);

  /// Asocia una identidad Nodos estable a un nodo detectado por BLE.
  ///
  /// Si [deviceUuid] ya pertenece a otra fila de nodes, ambas filas
  /// representan el mismo dispositivo físico y deben reconciliarse.
  ///
  /// La implementación debe preservar:
  /// - connections;
  /// - scanSessionNodes;
  /// - identidad persistente;
  /// - la dirección BLE más reciente.
  ///
  /// Retorna el Node canónico resultante.
  Future<Node?> reconcileNodeIdentity(
    int nodeId, {
    required String deviceUuid,
    required String name,
    required String color,
  });

  Future<void> deleteNode(int id);

  /// Actualmente elimina filas persistentes.
  /// Su semántica será corregida en BUG-002.
  Future<void> deleteAllNodes();
}
