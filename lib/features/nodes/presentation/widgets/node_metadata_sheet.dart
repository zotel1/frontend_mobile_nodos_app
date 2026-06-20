import 'package:flutter/material.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/widgets/color_picker.dart';

/// Bottom sheet para entrada manual de metadatos del nodo (nombre y color).
///
/// QUÉ hace: muestra un formulario con campo de nombre (pre-llenado
/// con [node.suggestedName] si existe) y un selector de color.
/// Al presionar "Guardar", despacha [UpdateNodeName] y [UpdateNodeColor]
/// al [NodeListBloc] recibido por constructor.
///
/// POR QUÉ: cuando la lectura de identidad GATT falla (R5.5, R5.11),
/// el usuario necesita una forma manual de asignar nombre y color
/// al nodo remoto. Este widget provee esa UI.
///
/// El [NodeListBloc] se pasa explícitamente porque el bottom sheet
/// se muestra en un Overlay y no tiene acceso al árbol de providers
/// de la pantalla principal.
class NodeMetadataSheet extends StatefulWidget {
  /// Nodo para el cual se editan los metadatos.
  final Node node;

  /// BLoC para despachar los eventos de actualización.
  final NodeListBloc nodeListBloc;

  const NodeMetadataSheet({
    super.key,
    required this.node,
    required this.nodeListBloc,
  });

  @override
  State<NodeMetadataSheet> createState() => _NodeMetadataSheetState();
}

class _NodeMetadataSheetState extends State<NodeMetadataSheet> {
  late final TextEditingController _nameController;

  /// Color seleccionado en el ColorPicker.
  /// Inicia con el color del nodo si existe, o azul por defecto.
  late String _selectedColor;

  @override
  void initState() {
    super.initState();
    // Pre-llenar con suggestedName si está disponible (R5.5)
    _nameController = TextEditingController(
      text: widget.node.suggestedName ?? widget.node.name ?? '',
    );
    _selectedColor = widget.node.color ?? '#2196F3';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Despacha los eventos de actualización al [NodeListBloc] y cierra
  /// el bottom sheet.
  ///
  /// QUÉ hace: envía [UpdateNodeName] con el nombre ingresado,
  /// [UpdateNodeColor] con el color seleccionado, y cierra el sheet.
  ///
  /// POR QUÉ separar nombre y color en dos eventos: cada evento
  /// actualiza un solo campo en la BD, siguiendo el principio
  /// de single responsibility del BLoC.
  void _onGuardar() {
    final nodeId = widget.node.id;
    if (nodeId == null) return;

    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      widget.nodeListBloc.add(UpdateNodeName(nodeId, name));
    }
    widget.nodeListBloc.add(UpdateNodeColor(nodeId, _selectedColor));

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        // Evita que el teclado tape el contenido
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Título del sheet
          Text(
            'Identificar nodo',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),

          // Campo de nombre
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              hintText: 'Ej: Teléfono de Juan',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            autofocus: true,
          ),
          const SizedBox(height: 16),

          // Selector de color — reusa ColorPicker existente
          Text(
            'Color',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          ColorPicker(
            selectedColor: _selectedColor,
            onColorSelected: (color) {
              setState(() => _selectedColor = color);
            },
          ),
          const SizedBox(height: 16),

          // Botón Guardar
          ElevatedButton.icon(
            onPressed: _onGuardar,
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
