import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

enum NodeInteractionAction { none, link, connect, disconnect, connecting }

/// Immutable UI projection of persistent, runtime and presence state.
///
/// It has no mutable source of truth: callers provide the current catalog,
/// BLE visibility, persistent links and GATT runtime sets.
class NodeInteractionState {
  final bool visible;
  final bool linked;
  final bool connected;
  final bool connecting;
  final bool bluetoothAvailable;
  final bool isLocal;
  final NodeInteractionAction action;

  const NodeInteractionState({
    required this.visible,
    required this.linked,
    required this.connected,
    required this.connecting,
    required this.bluetoothAvailable,
    required this.isLocal,
    required this.action,
  });

  factory NodeInteractionState.fromNode({
    required Node node,
    required Set<String> visibleDeviceIds,
    required Set<int> linkedNodeIds,
    required Set<String> connectedRemoteIds,
    required Set<String> connectingRemoteIds,
    required bool bluetoothAvailable,
  }) {
    final remoteId = node.bleAddress;
    final visible = remoteId != null && visibleDeviceIds.contains(remoteId);
    final linked = node.id != null && linkedNodeIds.contains(node.id);
    final connected = remoteId != null && connectedRemoteIds.contains(remoteId);
    final connecting =
        remoteId != null && connectingRemoteIds.contains(remoteId);
    final isLocal = node.isSelf;

    final NodeInteractionAction action;
    if (isLocal || !bluetoothAvailable || !visible || !node.connectable) {
      action = NodeInteractionAction.none;
    } else if (connecting) {
      action = NodeInteractionAction.connecting;
    } else if (connected) {
      action = NodeInteractionAction.disconnect;
    } else if (linked) {
      action = NodeInteractionAction.connect;
    } else {
      action = NodeInteractionAction.link;
    }

    return NodeInteractionState(
      visible: visible,
      linked: linked,
      connected: connected,
      connecting: connecting,
      bluetoothAvailable: bluetoothAvailable,
      isLocal: isLocal,
      action: action,
    );
  }

  String get statusLabel {
    if (isLocal) return 'Este dispositivo';
    if (connecting) return 'Conectando...';
    if (connected) return 'Conectado';
    if (linked && visible) return 'Enlazado';
    if (visible) return 'Visible';
    if (linked) return 'Enlazado';
    return 'Histórico';
  }

  String? get actionLabel => switch (action) {
    NodeInteractionAction.link => 'Enlazar',
    NodeInteractionAction.connect => 'Conectar',
    NodeInteractionAction.disconnect => 'Desconectar',
    NodeInteractionAction.connecting => 'Conectando...',
    NodeInteractionAction.none => null,
  };
}
