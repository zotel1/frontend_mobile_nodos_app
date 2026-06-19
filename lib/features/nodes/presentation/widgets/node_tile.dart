import 'package:flutter/material.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/widgets/proximity_badge.dart';

/// ListTile displaying a detected node with proximity indicator.
///
/// Shows:
///   - Device name (or "Desconocido" for unknown nodes)
///   - Last seen timestamp
///   - RSSI indicator via [ProximityBadge]
///   - Background tint based on proximity zone
class NodeTile extends StatelessWidget {
  final Node node;
  final VoidCallback? onTap;

  const NodeTile({
    super.key,
    required this.node,
    this.onTap,
  });

  int get _lastRssi =>
      node.rssiHistory.isNotEmpty ? node.rssiHistory.last : -100;

  ProximityLevel get _proximity => rssiToProximity(_lastRssi);

  Color get _backgroundColor => switch (_proximity) {
        ProximityLevel.close => Colors.green.withValues(alpha: 0.08),
        ProximityLevel.medium => Colors.amber.withValues(alpha: 0.08),
        ProximityLevel.far => Colors.red.withValues(alpha: 0.06),
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: _backgroundColor,
      child: ListTile(
        leading: ProximityBadge(proximity: _proximity),
        title: Text(
          node.isKnown ? node.name! : 'Desconocido',
          style: TextStyle(
            fontWeight: node.isKnown ? FontWeight.w600 : FontWeight.w400,
            color: node.isKnown ? null : Colors.grey.shade600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RSSI: $_lastRssi dBm',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Visto: ${_formatLastSeen(node.lastSeen)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: node.isKnown
            ? null
            : Icon(Icons.help_outline, color: Colors.grey.shade400),
        onTap: onTap,
      ),
    );
  }

  String _formatLastSeen(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inSeconds < 60) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}
