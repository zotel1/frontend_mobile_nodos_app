import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

/// Contrato de acceso a datos locales para la entidad Node.
///
/// Define las operaciones CRUD que cualquier implementación de
/// persistencia local debe soportar (Drift, in-memory, etc.).
abstract class NodeLocalDataSource {
  Stream<List<Node>> watchNodes();
  Future<Node?> getNodeById(int id);
  Future<void> upsertNode(Node node);
  Future<void> deleteNode(int id);

  /// Elimina todos los nodos de la tabla.
  /// Usado en el pipeline ClearNodes cuando se apaga Bluetooth (R5.17).
  Future<void> deleteAllNodes();

  /// Busca un nodo por su dirección BLE.
  /// Retorna null si no existe. Usado para lookup en el flujo
  /// de inserción de connections (mapear bleAddress → id).
  Future<Node?> getNodeByBleAddress(String bleAddress);
}
