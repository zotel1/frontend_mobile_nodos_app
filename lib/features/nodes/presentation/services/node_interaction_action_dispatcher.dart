import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/models/node_interaction_state.dart';

/// Dispatches only actions allowed by a previously computed UI projection.
class NodeInteractionActionDispatcher {
  const NodeInteractionActionDispatcher._();

  static void dispatch(
    BuildContext context, {
    required Node node,
    required NodeInteractionState interaction,
    required int? localNodeId,
  }) {
    final remoteId = node.bleAddress;
    if (remoteId == null) return;

    final bloc = context.read<BleConnectionBloc>();
    if (interaction.action == NodeInteractionAction.disconnect) {
      bloc.add(DisconnectDevice(remoteId));
      return;
    }

    if ((interaction.action == NodeInteractionAction.link ||
            interaction.action == NodeInteractionAction.connect) &&
        localNodeId != null) {
      bloc.add(ConnectToDevice(remoteId, myNodeId: localNodeId));
    }
  }
}
