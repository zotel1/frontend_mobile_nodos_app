import 'dart:math';

import 'package:flutter/material.dart';

import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/painters/graph_painter.dart';

/// Vista interactiva 2D del grafo.
///
/// Responsabilidades:
///
/// - renderizar el grafo mediante [GraphPainter];
/// - permitir navegación por el canvas;
/// - detectar toque simple sobre nodos;
/// - detectar long-press + drag sobre nodos;
/// - transformar coordenadas de pantalla al canvas lógico;
/// - ofrecer zoom explícito mediante botones + y -;
/// - conservar la transformación elegida por el usuario.
///
/// La posición real de los nodos NO se almacena aquí.
/// GraphView únicamente informa las interacciones al exterior.
/// El BLoC continúa siendo la fuente de verdad espacial.
class GraphView extends StatefulWidget {
  final LayoutResult layout;
  final int? selectedNodeId;
  final Offset? barycenter;

  /// Toque simple:
  /// mantiene el comportamiento actual de selección/menú.
  final void Function(int nodeId)? onNodeTapped;

  /// Inicio de long-press sobre un nodo.
  final void Function(int nodeId)? onNodeDragStarted;

  /// Movimiento del nodo.
  ///
  /// [position] pertenece al canvas lógico 2000×2000.
  final void Function(int nodeId, Offset position)? onNodeDragUpdated;

  /// Fin del drag.
  final void Function(int nodeId)? onNodeDragEnded;

  const GraphView({
    super.key,
    required this.layout,
    this.selectedNodeId,
    this.barycenter,
    this.onNodeTapped,
    this.onNodeDragStarted,
    this.onNodeDragUpdated,
    this.onNodeDragEnded,
  });

  @override
  State<GraphView> createState() => GraphViewState();
}

/// Estado de [GraphView].
///
/// Mantiene exclusivamente estado de interacción local:
///
/// - transformación del viewport;
/// - nodo actualmente agarrado por el gesto;
/// - centrado inicial.
///
/// Las posiciones persistentes siguen perteneciendo al BLoC.
class GraphViewState extends State<GraphView> {
  static const Size _canvasSize = Size(2000, 2000);

  static const double _minScale = 0.05;
  static const double _maxScale = 5.0;

  /// Factor utilizado por los botones +/-.
  static const double _zoomStep = 1.25;

  final TransformationController _transformController =
      TransformationController();

  /// Nodo agarrado actualmente mediante long press.
  int? _draggedNodeId;

  /// Evita que InteractiveViewer desplace el mapa mientras arrastramos
  /// manualmente un nodo.
  bool _isDraggingNode = false;

  /// El centrado automático se realiza una sola vez.
  bool _hasCentered = false;

  /// Expuesto para HomePage, que lo utiliza para convertir coordenadas
  /// del canvas a coordenadas globales al posicionar tooltips.
  TransformationController get transformController => _transformController;

  @override
  void didUpdateWidget(covariant GraphView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Si el nodo que estaba siendo arrastrado desapareció debido al scan,
    // cancelamos la interacción local.
    final draggedId = _draggedNodeId;

    if (draggedId != null && !_containsNode(draggedId)) {
      _draggedNodeId = null;
      _isDraggingNode = false;
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
              onTapUp: (details) {
                _handleTap(details.localPosition);
              },

              // ─────────────────────────────────────────────
              // LONG PRESS + DRAG
              // ─────────────────────────────────────────────
              onLongPressStart: (details) {
                _handleLongPressStart(details.localPosition);
              },

              onLongPressMoveUpdate: (details) {
                _handleLongPressMove(details.localPosition);
              },

              onLongPressEnd: (_) {
                _handleLongPressEnd();
              },

              onLongPressCancel: _handleLongPressCancel,

              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: _minScale,
                maxScale: _maxScale,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                constrained: false,

                // Cuando un nodo está agarrado, el mismo movimiento del dedo
                // debe pertenecer al nodo y no al viewport.
                panEnabled: !_isDraggingNode,

                // También bloqueamos zoom durante el drag para evitar que un
                // segundo dedo cambie accidentalmente la transformación.
                scaleEnabled: !_isDraggingNode,

                child: CustomPaint(
                  size: _canvasSize,
                  painter: GraphPainter(
                    layout: widget.layout,
                    selectedNodeId: widget.selectedNodeId,
                  ),
                ),
              ),
            ),

            // ─────────────────────────────────────────────
            // ZOOM CONTROLS
            // ─────────────────────────────────────────────
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
  // TAP
  // ─────────────────────────────────────────────────────────────

  /// Detecta un nodo bajo un toque simple.
  void _handleTap(Offset localPosition) {
    // Un tap residual inmediatamente después de un drag no debe abrir
    // accidentalmente el menú del nodo.
    if (_isDraggingNode) {
      return;
    }

    final node = _findNodeAt(localPosition);

    final id = node?.id;

    if (id != null) {
      widget.onNodeTapped?.call(id);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // LONG PRESS / DRAG
  // ─────────────────────────────────────────────────────────────

  void _handleLongPressStart(Offset localPosition) {
    final node = _findNodeAt(localPosition);

    final nodeId = node?.id;

    // Long press sobre el fondo:
    // no inicia movimiento de nodos.
    if (nodeId == null) {
      return;
    }

    setState(() {
      _draggedNodeId = nodeId;
      _isDraggingNode = true;
    });

    widget.onNodeDragStarted?.call(nodeId);
  }

  void _handleLongPressMove(Offset localPosition) {
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

  /// Busca el nodo más cercano al punto indicado.
  ///
  /// La tolerancia se expresa en píxeles visuales y luego se transforma
  /// al espacio lógico según el zoom actual. Así los nodos continúan siendo
  /// fáciles de tocar aunque el usuario haya alejado mucho el mapa.
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

  /// Aumenta el zoom manteniendo aproximadamente fijo el centro visible.
  void zoomIn() {
    _zoomBy(_zoomStep);
  }

  /// Reduce el zoom manteniendo aproximadamente fijo el centro visible.
  void zoomOut() {
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

  /// Centra el viewport una única vez.
  ///
  /// Después de esta operación las actualizaciones BLE no modifican
  /// transformación, zoom ni desplazamiento elegidos por el usuario.
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

/// Controles explícitos de zoom.
///
/// Se mantienen separados del GestureDetector principal para que pulsar
/// +/- nunca pueda interpretarse como interacción con un nodo.
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
