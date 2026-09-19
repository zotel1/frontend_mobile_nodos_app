import 'dart:math';

import 'package:flutter/material.dart';

import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/painters/graph_painter.dart';

/// Vista interactiva 2D del grafo.
///
/// Tiene dos modos de interacción:
///
/// NAVEGACIÓN:
/// - arrastrar el fondo mueve el mapa;
/// - pinch permite acercar/alejar;
/// - los nodos no reciben interacciones;
/// - los botones +/- permanecen ocultos.
///
/// INTERACCIÓN:
/// - el viewport queda bloqueado;
/// - toque simple interactúa con el nodo;
/// - doble toque solicita sus detalles;
/// - long-press + drag mueve el nodo;
/// - los botones +/- permiten controlar el zoom.
///
/// Cambiar de modo nunca modifica la transformación actual del viewport.
class GraphView extends StatefulWidget {
  final LayoutResult layout;
  final int? selectedNodeId;
  final int? detailsNodeId;
  final Offset? barycenter;

  /// Toque simple sobre un nodo.
  final void Function(int nodeId)? onNodeTapped;

  /// Doble toque sobre un nodo.
  ///
  /// Se utilizará para mostrar u ocultar información contextual.
  final void Function(int nodeId)? onNodeDoubleTapped;

  /// Inicio de long-press sobre un nodo.
  final void Function(int nodeId)? onNodeDragStarted;

  /// Movimiento del nodo en coordenadas del canvas lógico.
  final void Function(int nodeId, Offset position)? onNodeDragUpdated;

  /// Fin del drag.
  final void Function(int nodeId)? onNodeDragEnded;

  const GraphView({
    super.key,
    required this.layout,
    this.selectedNodeId,
    this.detailsNodeId,
    this.barycenter,
    this.onNodeTapped,
    this.onNodeDoubleTapped,
    this.onNodeDragStarted,
    this.onNodeDragUpdated,
    this.onNodeDragEnded,
  });

  @override
  State<GraphView> createState() => GraphViewState();
}

/// Modo de interacción actual del grafo.
enum _GraphInteractionMode {
  /// Mano abierta:
  /// el usuario manipula el viewport.
  navigation,

  /// Mano cerrada:
  /// el viewport queda fijo y el usuario manipula nodos.
  nodes,
}

class GraphViewState extends State<GraphView> {
  static const Size _canvasSize = Size(2000, 2000);

  static const double _minScale = 0.05;
  static const double _maxScale = 5.0;
  static const double _zoomStep = 1.25;

  final TransformationController _transformController =
      TransformationController();

  /// Por defecto comenzamos en navegación.
  _GraphInteractionMode _interactionMode = _GraphInteractionMode.navigation;

  /// Nodo actualmente agarrado mediante long-press.
  int? _draggedNodeId;

  /// Nodo detectado al comenzar un posible doble toque.
  ///
  /// onDoubleTapDown proporciona la posición del gesto.
  /// onDoubleTap confirma posteriormente que realmente fue un doble toque.
  int? _doubleTapNodeId;

  bool _isDraggingNode = false;

  bool _hasCentered = false;

  TransformationController get transformController => _transformController;

  bool get _isNavigationMode =>
      _interactionMode == _GraphInteractionMode.navigation;

  bool get _isNodeMode => _interactionMode == _GraphInteractionMode.nodes;

  @override
  void didUpdateWidget(covariant GraphView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final draggedId = _draggedNodeId;

    if (draggedId != null && !_containsNode(draggedId)) {
      _draggedNodeId = null;
      _isDraggingNode = false;
    }

    final doubleTapId = _doubleTapNodeId;

    if (doubleTapId != null && !_containsNode(doubleTapId)) {
      _doubleTapNodeId = null;
    }

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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _maybeCenterOnBarycenter();
          }
        });

        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,

              // ─────────────────────────────────────────────
              // TOQUE SIMPLE
              // ─────────────────────────────────────────────
              onTapUp: _isNodeMode
                  ? (details) {
                      _handleTap(details.localPosition);
                    }
                  : null,

              // ─────────────────────────────────────────────
              // DOBLE TOQUE
              // ─────────────────────────────────────────────
              onDoubleTapDown: _isNodeMode
                  ? (details) {
                      _handleDoubleTapDown(details.localPosition);
                    }
                  : null,

              onDoubleTap: _isNodeMode ? _handleDoubleTap : null,

              onDoubleTapCancel: _isNodeMode ? _handleDoubleTapCancel : null,

              // ─────────────────────────────────────────────
              // LONG PRESS + DRAG
              // ─────────────────────────────────────────────
              onLongPressStart: _isNodeMode
                  ? (details) {
                      _handleLongPressStart(details.localPosition);
                    }
                  : null,

              onLongPressMoveUpdate: _isNodeMode
                  ? (details) {
                      _handleLongPressMove(details.localPosition);
                    }
                  : null,

              onLongPressEnd: _isNodeMode
                  ? (_) {
                      _handleLongPressEnd();
                    }
                  : null,

              onLongPressCancel: _isNodeMode ? _handleLongPressCancel : null,

              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: _minScale,
                maxScale: _maxScale,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                constrained: false,

                // Mano abierta:
                // el usuario puede desplazar y escalar el mapa.
                //
                // Mano cerrada:
                // el viewport queda completamente fijo.
                panEnabled: _isNavigationMode && !_isDraggingNode,
                scaleEnabled: _isNavigationMode && !_isDraggingNode,

                child: CustomPaint(
                  size: _canvasSize,
                  painter: GraphPainter(
                    layout: widget.layout,
                    selectedNodeId: widget.selectedNodeId,
                    detailsNodeId: widget.detailsNodeId,
                  ),
                ),
              ),
            ),

            // ─────────────────────────────────────────────
            // SELECTOR NAVEGACIÓN / NODOS
            // ─────────────────────────────────────────────
            Positioned(
              left: 16,
              bottom: 20,
              child: _InteractionModeButton(
                isNavigationMode: _isNavigationMode,
                onPressed: _toggleInteractionMode,
              ),
            ),

            // ─────────────────────────────────────────────
            // ZOOM + / -
            // ─────────────────────────────────────────────
            //
            // Solo aparecen con la mano cerrada.
            if (_isNodeMode)
              Positioned(
                right: 16,
                bottom: 20,
                child: _ZoomControls(onZoomIn: zoomIn, onZoomOut: zoomOut),
              ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // INTERACTION MODE
  // ─────────────────────────────────────────────────────────────

  void _toggleInteractionMode() {
    // Si existe un drag activo lo finalizamos antes de cambiar de modo.
    final draggedNodeId = _draggedNodeId;

    if (draggedNodeId != null) {
      widget.onNodeDragEnded?.call(draggedNodeId);
    }

    setState(() {
      _draggedNodeId = null;
      _doubleTapNodeId = null;
      _isDraggingNode = false;

      _interactionMode = _isNavigationMode
          ? _GraphInteractionMode.nodes
          : _GraphInteractionMode.navigation;
    });

    // No modificamos _transformController.
    //
    // El mapa conserva exactamente la posición y escala elegidas
    // por el usuario.
  }

  // ─────────────────────────────────────────────────────────────
  // TAP
  // ─────────────────────────────────────────────────────────────

  void _handleTap(Offset localPosition) {
    if (!_isNodeMode || _isDraggingNode) {
      return;
    }

    final node = _findNodeAt(localPosition);
    final id = node?.id;

    if (id != null) {
      widget.onNodeTapped?.call(id);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DOUBLE TAP
  // ─────────────────────────────────────────────────────────────

  void _handleDoubleTapDown(Offset localPosition) {
    if (!_isNodeMode || _isDraggingNode) {
      _doubleTapNodeId = null;
      return;
    }

    final node = _findNodeAt(localPosition);

    _doubleTapNodeId = node?.id;
  }

  void _handleDoubleTap() {
    if (!_isNodeMode || _isDraggingNode) {
      _doubleTapNodeId = null;
      return;
    }

    final nodeId = _doubleTapNodeId;

    _doubleTapNodeId = null;

    if (nodeId != null) {
      widget.onNodeDoubleTapped?.call(nodeId);
    }
  }

  void _handleDoubleTapCancel() {
    _doubleTapNodeId = null;
  }

  // ─────────────────────────────────────────────────────────────
  // LONG PRESS / DRAG
  // ─────────────────────────────────────────────────────────────

  void _handleLongPressStart(Offset localPosition) {
    if (!_isNodeMode) {
      return;
    }

    final node = _findNodeAt(localPosition);
    final nodeId = node?.id;

    if (nodeId == null) {
      return;
    }

    setState(() {
      _doubleTapNodeId = null;
      _draggedNodeId = nodeId;
      _isDraggingNode = true;
    });

    widget.onNodeDragStarted?.call(nodeId);
  }

  void _handleLongPressMove(Offset localPosition) {
    if (!_isNodeMode) {
      return;
    }

    final nodeId = _draggedNodeId;

    if (!_isDraggingNode || nodeId == null) {
      return;
    }

    final canvasPoint = _screenToCanvas(localPosition);

    final clampedPosition = Offset(
      canvasPoint.dx.clamp(0.0, _canvasSize.width).toDouble(),
      canvasPoint.dy.clamp(0.0, _canvasSize.height).toDouble(),
    );

    widget.onNodeDragUpdated?.call(nodeId, clampedPosition);
  }

  void _handleLongPressEnd() {
    final nodeId = _draggedNodeId;

    if (nodeId != null) {
      widget.onNodeDragEnded?.call(nodeId);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _draggedNodeId = null;
      _isDraggingNode = false;
    });
  }

  void _handleLongPressCancel() {
    _handleLongPressEnd();
  }

  // ─────────────────────────────────────────────────────────────
  // HIT TEST
  // ─────────────────────────────────────────────────────────────

  GraphNode? _findNodeAt(Offset localPosition) {
    final canvasPoint = _screenToCanvas(localPosition);

    final scale = _currentScale;

    final logicalTolerance = 10.0 / max(scale, 0.01);

    GraphNode? closestNode;
    double closestDistance = double.infinity;

    for (final node in widget.layout.nodes) {
      if (node.id == null) {
        continue;
      }

      final dx = canvasPoint.dx - node.x;
      final dy = canvasPoint.dy - node.y;

      final distance = sqrt(dx * dx + dy * dy);

      final hitRadius = node.radius + logicalTolerance;

      if (distance <= hitRadius && distance < closestDistance) {
        closestDistance = distance;
        closestNode = node;
      }
    }

    return closestNode;
  }

  Offset _screenToCanvas(Offset localPosition) {
    final inverseMatrix = Matrix4.inverted(_transformController.value);

    return MatrixUtils.transformPoint(inverseMatrix, localPosition);
  }

  bool _containsNode(int nodeId) {
    for (final node in widget.layout.nodes) {
      if (node.id == nodeId) {
        return true;
      }
    }

    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // ZOOM
  // ─────────────────────────────────────────────────────────────

  double get _currentScale {
    return _transformController.value.getMaxScaleOnAxis();
  }

  void zoomIn() {
    if (!_isNodeMode) {
      return;
    }

    _zoomBy(_zoomStep);
  }

  void zoomOut() {
    if (!_isNodeMode) {
      return;
    }

    _zoomBy(1 / _zoomStep);
  }

  void _zoomBy(double factor) {
    final renderBox = context.findRenderObject();

    if (renderBox is! RenderBox || !renderBox.hasSize) {
      return;
    }

    final viewportCenter = renderBox.size.center(Offset.zero);

    final currentScale = _currentScale;

    final desiredScale = (currentScale * factor)
        .clamp(_minScale, _maxScale)
        .toDouble();

    if ((desiredScale - currentScale).abs() < 0.0001) {
      return;
    }

    final effectiveFactor = desiredScale / currentScale;

    final scenePoint = _transformController.toScene(viewportCenter);

    final matrix = _transformController.value.clone();

    matrix.translateByDouble(scenePoint.dx, scenePoint.dy, 0, 1);

    matrix.scaleByDouble(effectiveFactor, effectiveFactor, 1, 1);

    matrix.translateByDouble(-scenePoint.dx, -scenePoint.dy, 0, 1);

    _transformController.value = matrix;
  }

  // ─────────────────────────────────────────────────────────────
  // INITIAL VIEWPORT
  // ─────────────────────────────────────────────────────────────

  void _maybeCenterOnBarycenter() {
    if (_hasCentered || widget.barycenter == null) {
      return;
    }

    final size = context.size;

    if (size == null || size.isEmpty) {
      return;
    }

    _hasCentered = true;

    final matrix = Matrix4.identity();

    matrix.setTranslationRaw(
      -widget.barycenter!.dx + size.width / 2,
      -widget.barycenter!.dy + size.height / 2,
      0,
    );

    _transformController.value = matrix;
  }
}

/// Botón que alterna entre:
///
/// 🖐 navegación del viewport
/// ✊ interacción con nodos
class _InteractionModeButton extends StatelessWidget {
  final bool isNavigationMode;
  final VoidCallback onPressed;

  const _InteractionModeButton({
    required this.isNavigationMode,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: colorScheme.surface.withAlpha(235),
      child: IconButton(
        tooltip: isNavigationMode
            ? 'Bloquear mapa e interactuar con nodos'
            : 'Mover y ampliar mapa',
        onPressed: onPressed,
        icon: Icon(
          isNavigationMode ? Icons.pan_tool_outlined : Icons.back_hand,
        ),
      ),
    );
  }
}

/// Controles explícitos de zoom.
///
/// Solo se muestran en modo interacción, cuando los gestos de navegación
/// del InteractiveViewer están bloqueados.
class _ZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _ZoomControls({required this.onZoomIn, required this.onZoomOut});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      color: Theme.of(context).colorScheme.surface.withAlpha(235),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Acercar',
            onPressed: onZoomIn,
            icon: const Icon(Icons.add),
          ),
          Container(
            width: 28,
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant.withAlpha(120),
          ),
          IconButton(
            tooltip: 'Alejar',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
          ),
        ],
      ),
    );
  }
}
