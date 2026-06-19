import 'package:flutter/material.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

/// Small colored circle showing the proximity zone of a BLE device.
///
/// Colors:
///   - Green (close): RSSI ≥ -55 dBm → < 3m
///   - Amber (medium): RSSI -70 to -55 → 3-6m
///   - Red (far): RSSI < -70 → > 6m
class ProximityBadge extends StatelessWidget {
  final ProximityLevel proximity;
  final double size;

  const ProximityBadge({
    super.key,
    required this.proximity,
    this.size = 14,
  });

  Color get _color => switch (proximity) {
        ProximityLevel.close => Colors.green,
        ProximityLevel.medium => Colors.amber,
        ProximityLevel.far => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _color,
        shape: BoxShape.circle,
        border: Border.all(
          color: _color.withValues(alpha: 0.8),
          width: 1,
        ),
      ),
    );
  }
}
