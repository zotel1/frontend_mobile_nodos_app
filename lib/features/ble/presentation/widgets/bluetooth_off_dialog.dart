import 'package:flutter/material.dart';

/// Dialog shown when Bluetooth is off at launch.
///
/// Offers two actions: navigate to system settings or cancel.
class BluetoothOffDialog extends StatelessWidget {
  final VoidCallback onGoToSettings;
  final VoidCallback onCancel;

  const BluetoothOffDialog({
    super.key,
    required this.onGoToSettings,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bluetooth requerido'),
      content: const Text(
        'Esta aplicación necesita Bluetooth activado para funcionar. '
        'Por favor, activá Bluetooth desde la configuración del dispositivo.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onCancel();
          },
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            onGoToSettings();
          },
          child: const Text('Ir a Configuración'),
        ),
      ],
    );
  }
}
