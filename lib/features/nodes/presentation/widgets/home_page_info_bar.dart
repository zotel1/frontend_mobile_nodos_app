import 'package:flutter/material.dart';

/// Displays the number of currently visible BLE nodes and the last scan time.
class HomePageInfoBar extends StatelessWidget {
  const HomePageInfoBar({
    super.key,
    required this.nodeCount,
    required this.lastScanTime,
  });

  final int nodeCount;
  final DateTime? lastScanTime;

  String? _formatRelativeTime(DateTime? time) {
    if (time == null) return null;

    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Ahora';
    final minutes = diff.inMinutes;
    if (minutes == 1) return 'Hace 1 min';
    return 'Hace $minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final timeText = _formatRelativeTime(lastScanTime);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Text(
        '$nodeCount nodos detectados'
        '${timeText != null ? ' · $timeText' : ''}',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
