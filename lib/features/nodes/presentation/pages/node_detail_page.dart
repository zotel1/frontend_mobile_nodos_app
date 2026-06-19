import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/widgets/proximity_badge.dart';

/// Detail screen for a single BLE node.
///
/// Receives the node id from the GoRouter route parameter `:id`.
/// Displays name, BLE address, first/last seen timestamps, proximity badge,
/// and RSSI history chart (placeholder).
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
            title: Text(node?.name ?? 'Detalle del nodo'),
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
      return nodes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  Widget _buildDetail(BuildContext context, Node node) {
    final proximity = node.rssiHistory.isNotEmpty
        ? rssiToProximity(node.rssiHistory.last)
        : ProximityLevel.far;
    final lastRssi =
        node.rssiHistory.isNotEmpty ? '${node.rssiHistory.last} dBm' : 'N/A';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Name
        ListTile(
          leading: const Icon(Icons.devices),
          title: const Text('Nombre'),
          subtitle: Text(node.name ?? 'Desconocido'),
        ),
        // BLE Address
        ListTile(
          leading: const Icon(Icons.bluetooth),
          title: const Text('Dirección BLE'),
          subtitle: Text(node.bleAddress),
        ),
        // First Seen
        ListTile(
          leading: const Icon(Icons.access_time),
          title: const Text('Primera vez'),
          subtitle: Text(_formatDate(node.firstSeen)),
        ),
        // Last Seen
        ListTile(
          leading: const Icon(Icons.update),
          title: const Text('Última vez'),
          subtitle: Text(_formatDate(node.lastSeen)),
        ),
        // Proximity
        ListTile(
          leading: ProximityBadge(proximity: proximity, size: 20),
          title: const Text('Proximidad'),
          subtitle: Text(_proximityLabel(proximity)),
        ),
        // RSSI
        ListTile(
          leading: const Icon(Icons.signal_cellular_alt),
          title: const Text('Último RSSI'),
          subtitle: Text(lastRssi),
        ),
        // RSSI History
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      ],
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

  String _proximityLabel(ProximityLevel level) => switch (level) {
        ProximityLevel.close => 'Cerca (< 3m)',
        ProximityLevel.medium => 'Media (3-6m)',
        ProximityLevel.far => 'Lejos (> 6m)',
      };

  Color _rssiColor(int rssi) => rssiToProximity(rssi) == ProximityLevel.close
      ? Colors.green
      : rssiToProximity(rssi) == ProximityLevel.medium
          ? Colors.amber
          : Colors.red;
}
