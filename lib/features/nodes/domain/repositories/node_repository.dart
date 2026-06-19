import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

abstract class NodeRepository {
  Stream<List<Node>> observeNodes();
  Future<Node?> getNodeById(int id);
  Future<void> upsertNode(Node node);
  Future<void> updateNodeMetadata(int id, {String? name, String? color});
}
