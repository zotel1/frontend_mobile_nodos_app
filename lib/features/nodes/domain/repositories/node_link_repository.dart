/// Read-only projection of persistent LINKED relationships for presentation.
///
/// This is deliberately separate from runtime CONNECTED state. A link remains
/// present after a GATT disconnect and must never be inferred from visibility.
abstract class NodeLinkRepository {
  Stream<Set<int>> observeLinkedNodeIds();
}
