import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';

/// Tooltip flotante que muestra información del nodo tocado en el grafo.
///
/// Se renderiza como un OverlayEntry posicionado cerca del nodo tocado.
/// Muestra: nombre (o "Desconocido"), nivel de proximidad con indicador
/// de color, y el ID del nodo.
///
/// Auto-dismiss: se cierra automáticamente después de 5 segundos o
/// cuando el usuario toca fuera del tooltip.
///
/// NOTA: lastSeen y RSSI no están disponibles en GraphNode actualmente.
/// Se agregarán cuando la entidad incluya esos campos.
class NodeTooltip extends StatefulWidget {
  final GraphNode node;
  final Offset globalPosition; // posición del nodo en coordenadas globales
  final VoidCallback onDismiss;

  const NodeTooltip({
    super.key,
    required this.node,
    required this.globalPosition,
    required this.onDismiss,
  });

  /// Abre el tooltip como overlay y retorna el OverlayEntry para control externo.
  static OverlayEntry show({
    required BuildContext context,
    required GraphNode node,
    required Offset globalPosition,
    required VoidCallback onDismiss,
    VoidCallback? onEnlazar,
  }) {
    // Usamos late para romper la referencia circular: el builder necesita
    // la referencia a entry, que aún no está declarada.
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _TooltipContent(
        node: node,
        globalPosition: globalPosition,
        onDismiss: () {
          entry.remove();
          onDismiss();
        },
        onEnlazar: onEnlazar,
      ),
    );
    Overlay.of(context).insert(entry);
    return entry;
  }

  @override
  State<NodeTooltip> createState() => _NodeTooltipState();
}

class _NodeTooltipState extends State<NodeTooltip> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _autoDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No renderiza nada directamente — usa el método estático show()
    // para crear un OverlayEntry.
    return const SizedBox.shrink();
  }
}

/// Contenido visual del tooltip renderizado dentro del Overlay.
///
/// Muestra una Card con la información del nodo, posicionada cerca
/// de la posición global del nodo en pantalla.
class _TooltipContent extends StatefulWidget {
  final GraphNode node;
  final Offset globalPosition;
  final VoidCallback onDismiss;

  /// Callback opcional al presionar "Enlazar".
  /// El caller (HomePage) ya conoce el nodo seleccionado desde el
  /// estado del VisualizationBloc, por lo que no necesita recibir el ID.
  final VoidCallback? onEnlazar;

  const _TooltipContent({
    required this.node,
    required this.globalPosition,
    required this.onDismiss,
    this.onEnlazar,
  });

  @override
  State<_TooltipContent> createState() => _TooltipContentState();
}

class _TooltipContentState extends State<_TooltipContent> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    // Cierra automáticamente después de 5 segundos
    _autoDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  /// Formatea la distancia estimada de forma adaptativa (R5.15).
  ///
  /// ≥1.0m → "~2.3m", <1.0m → "~35cm".
  static String _formatDistance(double distance) {
    if (distance >= 1.0) {
      return '~${distance.toStringAsFixed(1)}m';
    } else {
      return '~${(distance * 100).round()}cm';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Indicador textual del nivel de proximidad
    final proximityLabel = switch (widget.node.proximity) {
      ProximityLevel.close => 'Cerca',
      ProximityLevel.medium => 'Medio',
      ProximityLevel.far => 'Lejos',
    };

    return Stack(
      children: [
        // Fondo transparente que captura taps para dismiss
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
            child: Container(color: Colors.transparent),
          ),
        ),
        // Card posicionada cerca del nodo
        Positioned(
          left: (widget.globalPosition.dx - 80).clamp(0.0, 500),
          top: widget.globalPosition.dy - 110,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 160,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.node.color, width: 1),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nombre del nodo
                  Text(
                    widget.node.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Indicador de proximidad con punto de color
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: widget.node.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        proximityLabel,
                        style: TextStyle(
                          color: widget.node.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // ID del nodo
                  Text(
                    'ID: ${widget.node.id ?? "—"}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                    ),
                  ),
                  // T3.9: Label de distancia adaptativo (R5.15)
                  // ≥1m → "~2.3m", <1m → "~35cm"
                  if (widget.node.estimatedDistance != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatDistance(widget.node.estimatedDistance!),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  // T3.6 + T3.10: Botón "Enlazar" — inicia conexión GATT.
                  // Deshabilitado si el dispositivo no es conectable.
                  if (widget.onEnlazar != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 28,
                      child: ElevatedButton.icon(
                        onPressed:
                            widget.node.connectable ? widget.onEnlazar : null,
                        icon: const Icon(Icons.link, size: 14),
                        label: const Text(
                          'Enlazar',
                          style: TextStyle(fontSize: 11),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          backgroundColor: widget.node.connectable
                              ? const Color(0xFF2A3A5C)
                              : Colors.grey.shade700,
                          foregroundColor: widget.node.connectable
                              ? Colors.white
                              : Colors.grey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    // Tooltip informativo cuando no es conectable
                    if (!widget.node.connectable)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          'Dispositivo no conectable',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
