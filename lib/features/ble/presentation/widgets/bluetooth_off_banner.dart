import 'package:flutter/material.dart';

/// Persistent MaterialBanner shown when Bluetooth is disabled.
///
/// Displays a warning message and a button to open system Bluetooth settings.
class BluetoothOffBanner extends StatelessWidget {
  final VoidCallback onGoToSettings;

  const BluetoothOffBanner({
    super.key,
    required this.onGoToSettings,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: const Icon(Icons.bluetooth_disabled, color: Colors.white),
      backgroundColor: Theme.of(context).colorScheme.error,
      content: const Text(
        'Bluetooth desactivado. La app no funciona sin Bluetooth.',
        style: TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
          onPressed: onGoToSettings,
          child: const Text(
            'Configuración',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
