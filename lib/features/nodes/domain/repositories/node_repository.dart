import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

/// Contrato de repositorio para la entidad Node (Clean Architecture).
///
/// Define las operaciones de dominio que abstraen la capa de datos.
/// Las implementaciones concretas (Drift, in-memory) viven en data/.
abstract class NodeRepository {
  Stream<List<Node>> observeNodes();
  Future<Node?> getNodeById(int id);
  Future<void> upsertNode(Node node);
  Future<void> updateNodeMetadata(int id, {String? name, String? color});

  /// Elimina todos los nodos de la base de datos.
  /// Usado en el pipeline ClearNodes cuando se apaga Bluetooth (R5.17).
  Future<void> clearAllNodes();

  /// Busca un nodo por su dirección BLE.
  /// Retorna null si no existe. Usado para lookup en el flujo
  /// de inserción de connections (mapear bleAddress → nodeId).
  Future<Node?> getNodeByBleAddress(String bleAddress);
}
