import 'dart:math';

import 'package:flutter/material.dart';

import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Renderizador 2D del grafo.
///
/// Mantiene la semántica visual del dominio:
///
/// - color propio del nodo mediante [GraphNode.displayColor];
/// - nodos conocidos y desconocidos diferenciados;
/// - self-node identificado mediante el color de perfil;
/// - aristas directas, transitivas y reportadas diferenciadas;
/// - selección mediante halo magenta;
/// - detalles visibles únicamente para el nodo solicitado.
///
/// El grafo permanece limpio por defecto.
/// Los nombres y distancias no se muestran permanentemente.
class GraphPainter extends CustomPainter {
  final LayoutResult layout;

  /// Nodo seleccionado mediante toque simple.
  ///
  /// Se utiliza para la selección visual asociada al menú de acciones.
  final int? selectedNodeId;

  /// Nodo cuyos detalles deben mostrarse.
  ///
  /// Es independiente de [selectedNodeId] y normalmente se modifica
  /// mediante doble toque.
  final int? detailsNodeId;

  GraphPainter({
    required this.layout,
    this.selectedNodeId,
    this.detailsNodeId,
  });

  static const Color _edgeColor = Color(0xFF7E8A9A);
  static const Color _transitiveEdgeColor = Color(0xFF667080);

  /// Una relación reportada se muestra diferenciada de una conexión
  /// directa local, pero continúa siendo una relación explícita.
  static const Color _reportedEdgeColor = Color(0xFF8A94A6);

  static const Color _nodeBorderColor = Color(0xFFE7ECF3);

  static const Color _unknownNodeColor = Color(0xFF6F7785);

  static const Color _selectionColor = Color(0xFFFF2D9A);

  static const Color _labelColor = Color(0xFFE9EDF5);
  static const Color _secondaryLabelColor = Color(0xFF9DA8B8);

  static const Color _detailsBackgroundColor = Color(0xE61A1F29);
  static const Color _detailsBorderColor = Color(0xFF596579);

  static const Color _selfFallbackColor = Color(0xFF42A5F5);

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.nodes.isEmpty) {
      _drawEmptyState(canvas, size);
      return;
    }

    final nodeMap = <int, GraphNode>{};

    for (final node in layout.nodes) {
      final id = node.id;

      if (id != null) {
        nodeMap[id] = node;
      }
    }

    // Orden back-to-front.
    _drawEdges(canvas, nodeMap);
    _drawProximityRings(canvas);
    _drawNodes(canvas);
    _drawSelfNode(canvas);
    _drawSelection(canvas, nodeMap);

    // Los detalles se dibujan al final para quedar por encima
    // del resto del grafo.
    _drawDetails(canvas, nodeMap);
  }

  // ─────────────────────────────────────────────────────────────
  // EDGES
  // ─────────────────────────────────────────────────────────────

  /// Dibuja las conexiones del grafo.
  ///
  /// - direct: conexión local continua.
  /// - transitive: inferencia local discontinua y tenue.
  /// - reported: relación explícita recibida mediante Graph Exchange,
  ///   continua pero visualmente más tenue que una conexión local.
  ///
  /// Las aristas terminan en el borde del nodo destino y reciben una
  /// pequeña punta de flecha para conservar visualmente la dirección
  /// `fromId → toId`.
  void _drawEdges(Canvas canvas, Map<int, GraphNode> nodeMap) {
    for (final edge in layout.edges) {
      final fromNode = nodeMap[edge.fromId];
      final toNode = nodeMap[edge.toId];

      if (fromNode == null || toNode == null) {
        continue;
      }

      if (fromNode.id == toNode.id) {
        continue;
      }

      final fromCenter = Offset(fromNode.x, fromNode.y);
      final toCenter = Offset(toNode.x, toNode.y);

      final distance = (toCenter - fromCenter).distance;

      if (distance <= 0.01) {
        continue;
      }

      final geometry = _calculateEdgeGeometry(
        fromCenter: fromCenter,
        toCenter: toCenter,
        fromRadius: fromNode.radius,
        toRadius: toNode.radius,
      );

      late final double strokeWidth;
      late final Color edgeColor;
      late final double arrowSize;

      switch (edge.edgeType) {
        case EdgeType.direct:
          strokeWidth = (1.25 + edge.thickness * 0.35)
              .clamp(1.4, 2.4)
              .toDouble();
          edgeColor = _edgeColor.withAlpha(165);
          arrowSize = 7.5;

        case EdgeType.transitive:
          strokeWidth = 1.15;
          edgeColor = _transitiveEdgeColor.withAlpha(105);
          arrowSize = 6.0;

        case EdgeType.reported:
          strokeWidth = (1.1 + edge.thickness * 0.25)
              .clamp(1.25, 1.9)
              .toDouble();
          edgeColor = _reportedEdgeColor.withAlpha(135);
          arrowSize = 6.8;
      }

      final paint = Paint()
        ..color = edgeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path()
        ..moveTo(geometry.start.dx, geometry.start.dy)
        ..quadraticBezierTo(
          geometry.control.dx,
          geometry.control.dy,
          geometry.end.dx,
          geometry.end.dy,
        );

      if (edge.edgeType == EdgeType.transitive) {
        _drawDashedPath(
          canvas,
          path,
          paint,
          dashWidth: 7,
          gapWidth: 7,
        );
      } else {
        canvas.drawPath(path, paint);
      }

      _drawArrowHead(
        canvas: canvas,
        tip: geometry.end,
        control: geometry.control,
        color: paint.color,
        size: arrowSize,
      );
    }
  }

  /// Calcula inicio, control y final de una arista.
  ///
  /// La línea no atraviesa visualmente el centro de los nodos:
  /// empieza y termina aproximadamente en sus circunferencias.
  _EdgeGeometry _calculateEdgeGeometry({
    required Offset fromCenter,
    required Offset toCenter,
    required double fromRadius,
    required double toRadius,
  }) {
    final vector = toCenter - fromCenter;
    final distance = vector.distance;

    if (distance <= 0.01) {
      return _EdgeGeometry(
        start: fromCenter,
        control: fromCenter,
        end: toCenter,
      );
    }

    final direction = vector / distance;

    final start = fromCenter + direction * (fromRadius + 2);

    final end = toCenter - direction * (toRadius + 7);

    final control = computeBezierControlPoint(start, end);

    return _EdgeGeometry(
      start: start,
      control: control,
      end: end,
    );
  }

  /// Calcula el punto de control de una Bezier cuadrática.
  @visibleForTesting
  static Offset computeBezierControlPoint(Offset from, Offset to) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;

    final distance = sqrt((dx * dx) + (dy * dy));

    final middle = Offset(
      (from.dx + to.dx) / 2,
      (from.dy + to.dy) / 2,
    );

    if (distance <= 0.01) {
      return middle;
    }

    final curvature = min(distance * 0.08, 45.0);

    return Offset(
      middle.dx - (dy / distance) * curvature,
      middle.dy + (dx / distance) * curvature,
    );
  }

  /// Punta de flecha orientada según la tangente final de la Bezier.
  void _drawArrowHead({
    required Canvas canvas,
    required Offset tip,
    required Offset control,
    required Color color,
    required double size,
  }) {
    final tangent = tip - control;

    if (tangent.distance <= 0.01) {
      return;
    }

    final angle = atan2(tangent.dy, tangent.dx);

    const spread = pi / 6;

    final left = Offset(
      tip.dx - size * cos(angle - spread),
      tip.dy - size * sin(angle - spread),
    );

    final right = Offset(
      tip.dx - size * cos(angle + spread),
      tip.dy - size * sin(angle + spread),
    );

    final arrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(arrowPath, arrowPaint);
  }

  // ─────────────────────────────────────────────────────────────
  // PROXIMITY
  // ─────────────────────────────────────────────────────────────

  /// Halo sutil relacionado con el color del nodo.
  void _drawProximityRings(Canvas canvas) {
    for (final node in layout.nodes) {
      if (node.isSelf) {
        continue;
      }

      final isSelected = node.id != null && node.id == selectedNodeId;

      final radius = node.radius + (isSelected ? 8.0 : 5.0);

      final paint = Paint()
        ..color = Color(node.displayColor).withAlpha(isSelected ? 45 : 24)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(node.x, node.y),
        radius,
        paint,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // NODES
  // ─────────────────────────────────────────────────────────────

  /// Renderiza los nodos como círculos simples.
  ///
  /// Conocidos:
  /// - color [GraphNode.displayColor];
  /// - borde claro.
  ///
  /// Desconocidos:
  /// - gris neutro;
  /// - borde discontinuo.
  void _drawNodes(Canvas canvas) {
    for (final node in layout.nodes) {
      final center = Offset(node.x, node.y);

      final radius = max(node.radius, 1.0);

      if (node.isKnown) {
        final fillPaint = Paint()
          ..color = Color(node.displayColor)
          ..style = PaintingStyle.fill;

        canvas.drawCircle(center, radius, fillPaint);

        final borderPaint = Paint()
          ..color = _nodeBorderColor.withAlpha(210)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

        canvas.drawCircle(center, radius, borderPaint);
      } else {
        final fillPaint = Paint()
          ..color = _unknownNodeColor
          ..style = PaintingStyle.fill;

        canvas.drawCircle(center, radius, fillPaint);

        final borderPaint = Paint()
          ..color = _nodeBorderColor.withAlpha(190)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;

        _drawDashedCircle(
          canvas,
          center,
          radius,
          borderPaint,
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SELF NODE
  // ─────────────────────────────────────────────────────────────

  /// Identifica visualmente el dispositivo local.
  ///
  /// El color del perfil se conserva como identidad del usuario.
  /// Este indicador es independiente del estado de selección.
  void _drawSelfNode(Canvas canvas) {
    for (final node in layout.nodes) {
      if (!node.isSelf) {
        continue;
      }

      final center = Offset(node.x, node.y);

      final selfColor = node.userColor != null
          ? Color(node.userColor!)
          : _selfFallbackColor;

      final glowPaint = Paint()
        ..color = selfColor.withAlpha(42)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        center,
        node.radius + 10,
        glowPaint,
      );

      final ringPaint = Paint()
        ..color = selfColor.withAlpha(235)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      canvas.drawCircle(
        center,
        node.radius + 5,
        ringPaint,
      );

      final markerPaint = Paint()
        ..color = selfColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(
          node.x,
          node.y - node.radius - 5,
        ),
        3.2,
        markerPaint,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SELECTION
  // ─────────────────────────────────────────────────────────────

  /// Selección independiente de la identidad del nodo.
  ///
  /// Un nodo seleccionado recibe un halo magenta.
  void _drawSelection(
    Canvas canvas,
    Map<int, GraphNode> nodeMap,
  ) {
    final id = selectedNodeId;

    if (id == null) {
      return;
    }

    final node = nodeMap[id];

    if (node == null) {
      return;
    }

    final center = Offset(node.x, node.y);

    final glowPaint = Paint()
      ..color = _selectionColor.withAlpha(48)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      node.radius + 14,
      glowPaint,
    );

    final ringPaint = Paint()
      ..color = _selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(
      center,
      node.radius + 8,
      ringPaint,
    );

    final outerPaint = Paint()
      ..color = _selectionColor.withAlpha(115)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(
      center,
      node.radius + 12,
      outerPaint,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // DETAILS
  // ─────────────────────────────────────────────────────────────

  /// Dibuja información únicamente para el nodo activado mediante
  /// doble toque.
  ///
  /// Si [detailsNodeId] es null, el grafo no muestra etiquetas.
  void _drawDetails(
    Canvas canvas,
    Map<int, GraphNode> nodeMap,
  ) {
    final id = detailsNodeId;

    if (id == null) {
      return;
    }

    final node = nodeMap[id];

    if (node == null) {
      return;
    }

    final namePainter = TextPainter(
      text: TextSpan(
        text: node.label,
        style: TextStyle(
          color: _labelColor,
          fontSize: node.isSelf ? 13.0 : 12.5,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 150);

    final estimatedDistance = node.estimatedDistance;

    TextPainter? distancePainter;

    if (estimatedDistance != null) {
      final distanceLabel = estimatedDistance >= 1.0
          ? '~${estimatedDistance.toStringAsFixed(1)}m'
          : '~${(estimatedDistance * 100).round()}cm';

      distancePainter = TextPainter(
        text: TextSpan(
          text: distanceLabel,
          style: const TextStyle(
            color: _secondaryLabelColor,
            fontSize: 10.5,
            fontWeight: FontWeight.w400,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 1,
      )..layout(maxWidth: 120);
    }

    const horizontalPadding = 10.0;
    const verticalPadding = 7.0;
    const lineSpacing = 3.0;

    final contentWidth = max(
      namePainter.width,
      distancePainter?.width ?? 0.0,
    );

    final contentHeight =
        namePainter.height +
        (distancePainter != null
            ? lineSpacing + distancePainter.height
            : 0.0);

    final boxWidth = contentWidth + horizontalPadding * 2;
    final boxHeight = contentHeight + verticalPadding * 2;

    final boxLeft = node.x - boxWidth / 2;
    final boxTop = node.y + node.radius + 11.0;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        boxLeft,
        boxTop,
        boxWidth,
        boxHeight,
      ),
      const Radius.circular(8),
    );

    final backgroundPaint = Paint()
      ..color = _detailsBackgroundColor
      ..style = PaintingStyle.fill;

    canvas.drawRRect(rect, backgroundPaint);

    final borderPaint = Paint()
      ..color = _detailsBorderColor.withAlpha(190)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(rect, borderPaint);

    var textY = boxTop + verticalPadding;

    namePainter.paint(
      canvas,
      Offset(
        node.x - namePainter.width / 2,
        textY,
      ),
    );

    if (distancePainter != null) {
      textY += namePainter.height + lineSpacing;

      distancePainter.paint(
        canvas,
        Offset(
          node.x - distancePainter.width / 2,
          textY,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DASH HELPERS
  // ─────────────────────────────────────────────────────────────

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    final path = Path()
      ..addOval(
        Rect.fromCircle(
          center: center,
          radius: radius,
        ),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;

      while (distance < metric.length) {
        final dashEnd = min(
          distance + 5.0,
          metric.length,
        );

        canvas.drawPath(
          metric.extractPath(distance, dashEnd),
          paint,
        );

        distance += 8.0;
      }
    }
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dashWidth = 7.0,
    double gapWidth = 7.0,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;

      while (distance < metric.length) {
        final dashEnd = min(
          distance + dashWidth,
          metric.length,
        );

        canvas.drawPath(
          metric.extractPath(distance, dashEnd),
          paint,
        );

        distance += dashWidth + gapWidth;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // EMPTY STATE
  // ─────────────────────────────────────────────────────────────

  void _drawEmptyState(
    Canvas canvas,
    Size size,
  ) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Sin datos de grafo',
        style: TextStyle(
          color: Color(0xFF7F8998),
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
    )..layout(
      maxWidth: max(
        size.width - 40,
        1,
      ),
    );

    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.detailsNodeId != detailsNodeId;
  }
}

/// Geometría precalculada de una conexión.
class _EdgeGeometry {
  final Offset start;
  final Offset control;
  final Offset end;

  const _EdgeGeometry({
    required this.start,
    required this.control,
    required this.end,
  });
}