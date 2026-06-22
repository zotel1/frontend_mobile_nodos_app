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

    // T-PR2-002: Al construir el Node actualizado, preservar suggestedName
    // y deviceType del nodo original.
    //
    // QUÉ: estos campos se enriquecen en la primera detección (Phase 4
    // identity enrichment). Si no se incluyen al actualizar metadata,
    // se pierden silenciosamente — el nodo vuelve a aparecer como
    // "Desconocido" sin tipo de dispositivo.
    //
    // POR QUÉ bug existía: el código anterior construía Node{...} sin
    // los campos suggestedName ni deviceType. Cualquier llamada a
    // updateNodeMetadata (ej: desde el diálogo de edición de nodo)
    // causaba pérdida irreversible de datos de identidad.
    final updated = Node(
      id: existing.id,
      bleAddress: existing.bleAddress,
      name: name ?? existing.name,
      color: color ?? existing.color,
      firstSeen: existing.firstSeen,
      lastSeen: existing.lastSeen,
      rssiHistory: existing.rssiHistory,
      // T-PR2-002: Preservar metadatos de identidad del nodo original
      suggestedName: existing.suggestedName,
      deviceType: existing.deviceType,
    );
    await _dataSource.upsertNode(updated);
  }
}
