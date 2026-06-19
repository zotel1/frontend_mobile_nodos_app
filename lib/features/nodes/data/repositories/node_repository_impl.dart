import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';

class NodeRepositoryImpl implements NodeRepository {
  final NodeLocalDataSource _dataSource;

  NodeRepositoryImpl(this._dataSource);

  @override
  Stream<List<Node>> observeNodes() => _dataSource.watchNodes();

  @override
  Future<Node?> getNodeById(int id) => _dataSource.getNodeById(id);

  @override
  Future<void> upsertNode(Node node) => _dataSource.upsertNode(node);

  @override
  Future<void> updateNodeMetadata(int id, {String? name, String? color}) async {
    final existing = await _dataSource.getNodeById(id);
    if (existing == null) return;
    final updated = Node(
      id: existing.id,
      bleAddress: existing.bleAddress,
      name: name ?? existing.name,
      color: color ?? existing.color,
      firstSeen: existing.firstSeen,
      lastSeen: existing.lastSeen,
      rssiHistory: existing.rssiHistory,
    );
    await _dataSource.upsertNode(updated);
  }
}
