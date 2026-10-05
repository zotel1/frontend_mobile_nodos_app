import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/core/di/injection_container.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/widgets/proximity_badge.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_link_repository.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/models/node_interaction_state.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';

/// Detail screen for a single BLE node.
///
/// Receives the node id from the GoRouter route parameter `:id`.
/// Displays name, BLE address, first/last seen timestamps, proximity badge,
/// and RSSI history.
///
/// BUG-004:
/// La acción "Enlazar" ya no depende de que la ruta inyecte un callback.
///
/// NodeDetailPage reutiliza el mismo flujo de conexión utilizado por HomePage:
///
/// UI → ConnectToDevice → BleConnectionBloc → BleConnectionRepository
///
/// [User.localNodeId] se utiliza como ID persistente del nodo local.
/// Nunca se utiliza User.id porque pertenece a la tabla users.
class NodeDetailPage extends StatelessWidget {
  final int id;

  const NodeDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NodeListBloc, NodeListState>(
      builder: (context, state) {
        final node = switch (state) {
          NodeListLoaded(:final nodes) => _findNode(nodes),
          _ => null,
        };

        return Scaffold(
          appBar: AppBar(
            title: Text(
              node?.name ?? node?.suggestedName ?? 'Detalle del nodo',
            ),
          ),
          body: node == null
              ? const Center(child: Text('Nodo no encontrado'))
              : _buildDetail(context, node),
        );
      },
    );
  }

  Node? _findNode(List<Node> nodes) {
    try {
      return nodes.firstWhere((node) => node.id == id);
    } catch (_) {
      return null;
    }
  }

  Widget _buildDetail(BuildContext context, Node node) {
    final bleBloc = _maybeBleBloc(context);
    final linkStream = sl.isRegistered<NodeLinkRepository>()
        ? sl<NodeLinkRepository>().observeLinkedNodeIds()
        : Stream<Set<int>>.value(const <int>{});

    return StreamBuilder<Set<int>>(
      stream: linkStream,
      initialData: const <int>{},
      builder: (context, linkSnapshot) {
        Widget buildForBleState(BleState bleState) {
          final connectionBloc = _maybeConnectionBloc(context);
          final visibleIds = bleBloc == null && node.bleAddress != null
              ? {node.bleAddress!}
              : bleState is BleScanning
              ? bleState.devices.map((device) => device.deviceId).toSet()
              : const <String>{};
          final interaction = NodeInteractionState.fromNode(
            node: node,
            visibleDeviceIds: visibleIds,
            linkedNodeIds: linkSnapshot.data ?? const <int>{},
            connectedRemoteIds: _safeRemoteIds(
              () => connectionBloc?.connectedRemoteIds,
            ),
            connectingRemoteIds: _safeRemoteIds(
              () => connectionBloc?.connectingRemoteIds,
            ),
            bluetoothAvailable: bleBloc == null || bleState is! BluetoothOff,
          );
          return _buildDetailContent(context, node, interaction);
        }

        if (bleBloc == null) {
          final connectionBloc = _maybeConnectionBloc(context);
          return connectionBloc == null
              ? buildForBleState(const BleInitial())
              : BlocBuilder<BleConnectionBloc, BleConnectionState>(
                  builder: (context, _) => buildForBleState(const BleInitial()),
                );
        }
        final connectionBloc = _maybeConnectionBloc(context);
        Widget withConnection(BleState state) {
          return connectionBloc == null
              ? buildForBleState(state)
              : BlocBuilder<BleConnectionBloc, BleConnectionState>(
                  builder: (context, _) => buildForBleState(state),
                );
        }

        return BlocBuilder<BleBloc, BleState>(
          builder: (context, bleState) => withConnection(bleState),
        );
      },
    );
  }

  Set<String> _safeRemoteIds(Set<String>? Function() read) {
    try {
      return read() ?? const <String>{};
    } on Object {
      return const <String>{};
    }
  }

  BleBloc? _maybeBleBloc(BuildContext context) {
    try {
      return context.read<BleBloc>();
    } on Object {
      return null;
    }
  }

  BleConnectionBloc? _maybeConnectionBloc(BuildContext context) {
    try {
      return context.read<BleConnectionBloc>();
    } on Object {
      return null;
    }
  }

  Widget _buildDetailContent(
    BuildContext context,
    Node node,
    NodeInteractionState interaction,
  ) {
    final proximity = node.rssiHistory.isNotEmpty
        ? rssiToProximity(node.rssiHistory.last)
        : ProximityLevel.far;

    final lastRssi = node.rssiHistory.isNotEmpty
        ? '${node.rssiHistory.last} dBm'
        : 'N/A';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ListTile(
          leading: const Icon(Icons.devices),
          title: const Text('Nombre'),
          subtitle: Text(node.name ?? node.suggestedName ?? 'Desconocido'),
        ),

        if (node.deviceType != null)
          ListTile(
            leading: const Icon(Icons.category),
            title: const Text('Tipo de dispositivo'),
            subtitle: Text(node.deviceType!),
          ),

        ListTile(
          leading: const Icon(Icons.bluetooth),
          title: const Text('Dirección BLE'),
          subtitle: Text(node.bleAddress ?? 'No disponible'),
        ),

        ListTile(
          leading: const Icon(Icons.access_time),
          title: const Text('Primera vez'),
          subtitle: Text(_formatDate(node.firstSeen)),
        ),

        ListTile(
          leading: const Icon(Icons.update),
          title: const Text('Última vez'),
          subtitle: Text(_formatDate(node.lastSeen)),
        ),

        ListTile(
          leading: ProximityBadge(proximity: proximity, size: 20),
          title: const Text('Proximidad'),
          subtitle: Text(_proximityLabel(proximity)),
        ),

        ListTile(
          leading: const Icon(Icons.signal_cellular_alt),
          title: const Text('Último RSSI'),
          subtitle: Text(lastRssi),
        ),

        if (node.rssiHistory.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Historial RSSI',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: node.rssiHistory.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final rssi = node.rssiHistory[index];
                final color = _rssiColor(rssi);

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$rssi',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // BUG-004:
        // Un nodo remoto conectable debe poder iniciar el mismo flujo
        // ConnectToDevice usado desde el tooltip del grafo.
        //
        // El self-node nunca puede conectarse consigo mismo.
        // Tampoco mostramos la acción si no existe una dirección BLE
        // utilizable o si el dispositivo fue marcado como no conectable.
        if (interaction.actionLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    interaction.action == NodeInteractionAction.connecting
                    ? null
                    : () => _performAction(context, node, interaction),
                icon: Icon(
                  interaction.action == NodeInteractionAction.disconnect
                      ? Icons.link_off
                      : Icons.link,
                ),
                label: Text(interaction.actionLabel!),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Inicia el flujo de conexión compartido con HomePage.
  ///
  /// IMPORTANTE:
  /// User.id pertenece a la tabla users y NO debe utilizarse
  /// como fromNodeId.
  ///
  /// ConnectToDevice espera Nodes.id, por eso utilizamos
  /// User.localNodeId.
  void _connectToNode(BuildContext context, Node node) {
    final bleAddress = node.bleAddress;

    if (bleAddress == null) {
      return;
    }

    final userState = context.read<UserBloc>().state;

    if (userState is! UserLoaded) {
      return;
    }

    final localNodeId = userState.user.localNodeId;

    if (localNodeId == null) {
      return;
    }

    context.read<BleConnectionBloc>().add(
      ConnectToDevice(bleAddress, myNodeId: localNodeId),
    );
  }

  void _performAction(
    BuildContext context,
    Node node,
    NodeInteractionState interaction,
  ) {
    if (node.bleAddress == null) return;
    if (interaction.action == NodeInteractionAction.disconnect) {
      context.read<BleConnectionBloc>().add(DisconnectDevice(node.bleAddress!));
      return;
    }
    _connectToNode(context, node);
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _proximityLabel(ProximityLevel level) {
    return switch (level) {
      ProximityLevel.close => 'Cerca (< 3m)',
      ProximityLevel.medium => 'Media (3-6m)',
      ProximityLevel.far => 'Lejos (> 6m)',
    };
  }

  Color _rssiColor(int rssi) {
    return switch (rssiToProximity(rssi)) {
      ProximityLevel.close => Colors.green,
      ProximityLevel.medium => Colors.amber,
      ProximityLevel.far => Colors.red,
    };
  }
}
