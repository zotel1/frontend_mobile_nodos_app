import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

abstract class NodeLocalDataSource {
  Stream<List<Node>> watchNodes();
  Future<Node?> getNodeById(int id);
  Future<void> upsertNode(Node node);
  Future<void> deleteNode(int id);
}
