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

  // QUÉ: F14 — Usa node.color si existe, sino usa el color de proximidad.
  // POR QUÉ: el usuario puede asignar un color personalizado al nodo desde
  //   la UI; ese color debe reflejarse como fondo del Card en la lista.
  Color get _backgroundColor {
    // Si el nodo tiene color personalizado, usarlo como fondo.
    if (node.color != null) {
      return Color(int.parse(node.color!.replaceFirst('#', '0xFF')));
    }
    // Fallback: color de proximidad con alpha bajo.
    return switch (_proximity) {
      ProximityLevel.close => Colors.green.withValues(alpha: 0.08),
      ProximityLevel.medium => Colors.amber.withValues(alpha: 0.08),
      ProximityLevel.far => Colors.red.withValues(alpha: 0.06),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: _backgroundColor,
      child: ListTile(
        leading: ProximityBadge(proximity: _proximity),
        title: Text(
          node.isKnown ? node.name! : (node.suggestedName ?? 'Desconocido'),
          style: TextStyle(
            fontWeight: node.isKnown ? FontWeight.w600 : FontWeight.w400,
            color: node.isKnown ? null : Colors.grey.shade600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // T1.9: badge de tipo de dispositivo
            if (node.deviceType != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _DeviceTypeBadge(type: node.deviceType!),
              ),
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

/// Badge compacto que muestra el tipo de dispositivo clasificado.
///
/// QUÉ hace: renderiza un chip pequeño con ícono y texto indicando
/// la categoría del dispositivo (ej: "⌚ Reloj/Fitness", "🎧 Auriculares").
///
/// POR QUÉ: R3.5 — la UI debe comunicar visualmente el tipo de
/// dispositivo clasificado para enriquecer la identidad.
class _DeviceTypeBadge extends StatelessWidget {
  final String type;

  const _DeviceTypeBadge({required this.type});

  IconData get _icon => switch (type) {
        'Reloj/Fitness' => Icons.watch,
        'Batería' => Icons.battery_std,
        'Teclado' => Icons.keyboard,
        'Nodo' => Icons.sensors,
        _ => Icons.devices,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 12, color: Colors.blue.shade700),
          const SizedBox(width: 3),
          Text(
            type,
            style: TextStyle(
              fontSize: 11,
              color: Colors.blue.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
