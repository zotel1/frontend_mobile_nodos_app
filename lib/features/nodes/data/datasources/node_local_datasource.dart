import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

/// Contrato de persistencia local de Node.
abstract class NodeLocalDataSource {
  Stream<List<Node>> watchNodes();

  Future<Node?> getNodeById(int id);

  Future<Node?> getNodeByBleAddress(String bleAddress);

  Future<Node?> getNodeByDeviceUuid(String deviceUuid);

  Future<Node?> getSelfNode();

  Future<void> upsertNode(Node node);

  Future<void> deleteNode(int id);

  /// Actualmente elimina filas persistentes.
  /// Su semántica será corregida en BUG-002.
  Future<void> deleteAllNodes();
}
