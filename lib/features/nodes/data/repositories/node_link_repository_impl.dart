import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_link_repository.dart';

class NodeLinkRepositoryImpl implements NodeLinkRepository {
  final AppDatabase _database;

  NodeLinkRepositoryImpl(this._database);

  @override
  Stream<Set<int>> observeLinkedNodeIds() {
    return _database.select(_database.connections).watch().map((rows) {
      final ids = <int>{};
      for (final row in rows) {
        ids.add(row.fromNodeId);
        ids.add(row.toNodeId);
      }
      return Set<int>.unmodifiable(ids);
    });
  }
}
