import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';

/// Reactive stream of all nodes. No Either — this is a pure reactive query.
class ObserveNodes {
  final NodeRepository repository;

  const ObserveNodes(this.repository);

  Stream<List<Node>> call() => repository.observeNodes();
}
