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
/// PR2: [barycenter] opcional permite centrar automáticamente la vista
/// en el cluster de nodos la primera vez que se recibe (R5.13).
///
/// Parámetros:
/// - [layout]: resultado del algoritmo FR con nodos posicionados y aristas
/// - [selectedNodeId]: ID del nodo seleccionado (para resaltar en azul)
/// - [barycenter]: centro geométrico del cluster para auto-centrado inicial
/// - [onNodeTapped]: callback al tocar un nodo, recibe el ID del nodo
class GraphView extends StatefulWidget {
  final LayoutResult layout;
  final int? selectedNodeId;
  final Offset? barycenter;
  final void Function(int nodeId)? onNodeTapped;

  const GraphView({
    super.key,
    required this.layout,
    this.selectedNodeId,
    this.barycenter,
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

  /// PR2: evita re-centrar después del primer centrado automático.
  /// Solo la primera vez que llega un barycenter no-nulo se centra.
  bool _hasCentered = false;

  @override
  void didUpdateWidget(GraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // PR2: centrar automáticamente en el barycenter la primera vez
    // que se recibe un barycenter no-nulo con layout convergido.
    _maybeCenterOnBarycenter();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // PR2: intentar centrar en el primer frame después del build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeCenterOnBarycenter();
        });

        return GestureDetector(
          onTapUp: (details) => _handleTap(details.localPosition),
          //child: InteractiveViewer(
            //transformationController: _transformController,
            //minScale: 0.5,
            //maxScale: 3.0,
            //boundaryMargin: const EdgeInsets.all(100),
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.05,
              maxScale: 5,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              constrained: false,
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

  /// PR2: Centra la vista en el barycenter del cluster de nodos.
  ///
  /// Solo ejecuta el centrado UNA vez (_hasCentered=false) cuando
  /// [barycenter] no es null. Después de centrar, el usuario puede
  /// navegar libremente con zoom/pan sin que el widget le pelee.
  ///
  /// Usa [Matrix4.identity] con translate para posicionar el viewport
  /// de modo que el barycenter quede en el centro de la pantalla.
  /// R5.13 — viewport must auto-center on node cluster at GraphReady.
  void _maybeCenterOnBarycenter() {
    if (_hasCentered || widget.barycenter == null) return;

    final size = context.size;
    if (size == null || size.isEmpty) return;

    _hasCentered = true;
    final matrix = Matrix4.identity();
    matrix.setTranslationRaw(
      -widget.barycenter!.dx + size.width / 2,
      -widget.barycenter!.dy + size.height / 2,
      0,
    );
    _transformController.value = matrix;
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
