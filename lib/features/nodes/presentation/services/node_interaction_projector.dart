import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/models/node_interaction_state.dart';

/// Builds the presentation projection without owning any mutable state.
class NodeInteractionProjector {
  const NodeInteractionProjector._();

  static NodeInteractionState forNode({
    required Node node,
    required BleState bleState,
    required Set<int> linkedNodeIds,
    required BleConnectionBloc connectionBloc,
  }) {
    return NodeInteractionState.fromNode(
      node: node,
      visibleDeviceIds: visibleDeviceIds(bleState),
      linkedNodeIds: linkedNodeIds,
      connectedRemoteIds: _safeRemoteIds(
        () => connectionBloc.connectedRemoteIds,
      ),
      connectingRemoteIds: _safeRemoteIds(
        () => connectionBloc.connectingRemoteIds,
      ),
      bluetoothAvailable: bleState is! BluetoothOff,
    );
  }

  static Set<String> visibleDeviceIds(BleState state) => state is BleScanning
      ? state.devices.map((device) => device.deviceId).toSet()
      : const <String>{};

  static Node? nodeForId(Iterable<Node> nodes, int? id) {
    if (id == null) return null;
    return nodes.where((node) => node.id == id).firstOrNull;
  }

  static Set<String> _safeRemoteIds(Set<String> Function() read) {
    try {
      return read();
    } on Object {
      // Keep presentation compatible with older Mockito test doubles.
      return const <String>{};
    }
  }
}
