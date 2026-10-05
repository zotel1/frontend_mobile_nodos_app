import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/models/node_interaction_state.dart';

Node _node({int id = 1, bool isSelf = false, bool connectable = true}) {
  return Node(
    id: id,
    bleAddress: 'remote-$id',
    isSelf: isSelf,
    connectable: connectable,
    firstSeen: DateTime(2026),
    lastSeen: DateTime(2026),
  );
}

NodeInteractionState _state({
  Node? node,
  Set<String> visible = const {'remote-1'},
  Set<int> linked = const {},
  Set<String> connected = const {},
  Set<String> connecting = const {},
  bool bluetoothAvailable = true,
}) {
  return NodeInteractionState.fromNode(
    node: node ?? _node(),
    visibleDeviceIds: visible,
    linkedNodeIds: linked,
    connectedRemoteIds: connected,
    connectingRemoteIds: connecting,
    bluetoothAvailable: bluetoothAvailable,
  );
}

void main() {
  group('NodeInteractionState', () {
    test('visible and unlinked exposes Enlazar', () {
      final state = _state();
      expect(state.action, NodeInteractionAction.link);
      expect(state.actionLabel, 'Enlazar');
    });

    test('visible linked and disconnected exposes Conectar', () {
      final state = _state(linked: {1});
      expect(state.action, NodeInteractionAction.connect);
      expect(state.actionLabel, 'Conectar');
    });

    test('visible linked and connected exposes Desconectar', () {
      final state = _state(linked: {1}, connected: {'remote-1'});
      expect(state.action, NodeInteractionAction.disconnect);
      expect(state.actionLabel, 'Desconectar');
    });

    test('historical node has no immediate action', () {
      final state = _state(visible: const {});
      expect(state.visible, isFalse);
      expect(state.action, NodeInteractionAction.none);
    });

    test('Bluetooth OFF disables action but preserves LINKED', () {
      final state = _state(linked: {1}, bluetoothAvailable: false);
      expect(state.linked, isTrue);
      expect(state.action, NodeInteractionAction.none);
    });

    test('connecting disables duplicate action', () {
      final state = _state(connecting: {'remote-1'});
      expect(state.action, NodeInteractionAction.connecting);
      expect(state.actionLabel, 'Conectando...');
    });

    test('local node never exposes a connection action', () {
      final state = _state(node: _node(isSelf: true));
      expect(state.isLocal, isTrue);
      expect(state.action, NodeInteractionAction.none);
    });
  });
}
