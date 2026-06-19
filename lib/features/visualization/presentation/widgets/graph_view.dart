import 'dart:math';
import 'package:flutter/material.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/painters/graph_painter.dart';

/// Widget que envuelve InteractiveViewer + CustomPaint para visualizar
/// el grafo de nodos BLE con zoom y desplazamiento (pan).
///
/// Usa StatefulWidget en lugar de StatelessWidget porque
/// TransformationController requiere dispose() para liberar recursos.
/// Sin el controller no se puede mapear coordenadas de tap al espacio
/// del canvas bajo transformaciones de zoom/pan.
///
/// Parámetros:
/// - [layout]: resultado del algoritmo FR con nodos posicionados y aristas
/// - [selectedNodeId]: ID del nodo seleccionado (para resaltar en azul)
/// - [onNodeTapped]: callback al tocar un nodo, recibe el ID del nodo
class GraphView extends StatefulWidget {
  final LayoutResult layout;
  final int? selectedNodeId;
  final void Function(int nodeId)? onNodeTapped;

  const GraphView({
    super.key,
    required this.layout,
    this.selectedNodeId,
    this.onNodeTapped,
  });

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView> {
  /// Controlador de transformación para leer la matriz de zoom/pan
  /// y mapear coordenadas de tap al espacio del canvas.
  final TransformationController _transformController =
      TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapUp: (details) => _handleTap(details.localPosition),
          child: InteractiveViewer(
            transformationController: _transformController,
            minScale: 0.5,
            maxScale: 3.0,
            boundaryMargin: const EdgeInsets.all(100),
            child: CustomPaint(
              // Canvas fijo de 2000×2000 donde el algoritmo FR posiciona nodos.
              // InteractiveViewer permite navegar dentro de este espacio.
              size: const Size(2000, 2000),
              painter: GraphPainter(
                layout: widget.layout,
                selectedNodeId: widget.selectedNodeId,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Transforma la posición del tap al espacio del canvas mediante
  /// la matriz inversa del TransformationController y busca el nodo
  /// más cercano dentro de radio + 8px de tolerancia.
  void _handleTap(Offset localPosition) {
    final matrix = _transformController.value;
    final inverseMatrix = Matrix4.inverted(matrix);
    final canvasPoint = MatrixUtils.transformPoint(inverseMatrix, localPosition);

    int? closestId;
    double closestDist = double.infinity;

    for (final node in widget.layout.nodes) {
      if (node.id == null) continue;

      final dx = canvasPoint.dx - node.x;
      final dy = canvasPoint.dy - node.y;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist < node.radius + 8 && dist < closestDist) {
        closestDist = dist;
        closestId = node.id;
      }
    }

    if (closestId != null) {
      widget.onNodeTapped?.call(closestId);
    }
  }
}
