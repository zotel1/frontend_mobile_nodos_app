import 'dart:math';
import 'package:flutter/material.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// CustomPainter que renderiza el grafo de nodos BLE en 6 capas.
///
/// Capas de pintado (en orden back-to-front):
/// 1. Aristas (edges) — curvas Bezier entre nodos co-detectados
/// 2. Anillos de proximidad — círculos concéntricos con alpha decreciente
/// 3. Nodos — círculos rellenos con color de proximidad y borde blanco
/// 3.5. Self node — glow azul para el nodo que representa al usuario
/// 4. Etiquetas — nombre o "Desconocido" debajo de cada nodo
/// 5. Selección — anillo azul sobre el nodo seleccionado
///
/// Recibe un LayoutResult como entrada y delega en el sistema de equality
/// de Equatable para shouldRepaint.
class GraphPainter extends CustomPainter {
  final LayoutResult layout;
  final int? selectedNodeId;

  GraphPainter({required this.layout, this.selectedNodeId});

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.nodes.isEmpty) return;

    // Construir mapa id → GraphNode para lookup de aristas.
    final nodeMap = <int, GraphNode>{};
    for (final node in layout.nodes) {
      if (node.id != null) {
        nodeMap[node.id!] = node;
      }
    }

    _drawEdges(canvas, nodeMap);
    _drawProximityRings(canvas);
    _drawNodes(canvas);
    _drawSelfNode(canvas);
    _drawLabels(canvas);
    _drawSelection(canvas, nodeMap);
  }

  /// Capa 1: Aristas entre nodos co-detectados.
  ///
  /// Dibuja curvas Bezier cuadráticas cuyo color interpola entre verde
  /// (RSSI fuerte) y rojo (RSSI débil) según el grosor de la arista.
  ///
  /// Cada arista se curva proporcionalmente a su longitud (LinkedIn Maps style).
  /// El punto de control se desplaza perpendicularmente al punto medio
  /// con curvatura = edge.length * 0.2.
  void _drawEdges(Canvas canvas, Map<int, GraphNode> nodeMap) {
    for (final edge in layout.edges) {
      final fromNode = nodeMap[edge.fromId];
      final toNode = nodeMap[edge.toId];
      if (fromNode == null || toNode == null) continue;

      // Color interpolado: grosor 1 → rojizo, grosor 3 → verdoso
      final t = (edge.thickness - 1.0) / 2.0; // 0..1
      final edgeColor = Color.lerp(
        const Color(0xFFF44336), // rojo (conexión débil)
        const Color(0xFF4CAF50), // verde (conexión fuerte)
        t.clamp(0.0, 1.0),
      )!;

      final paint = Paint()
        ..color = edgeColor
        ..strokeWidth = edge.thickness
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final from = Offset(fromNode.x, fromNode.y);
      final to = Offset(toNode.x, toNode.y);

      // Curva Bezier cuadrática: punto de control desplazado
      // perpendicularmente al punto medio de la arista (T2.4).
      final cp = computeBezierControlPoint(from, to);
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(cp.dx, cp.dy, to.dx, to.dy);
      canvas.drawPath(path, paint);
    }
  }

  /// Computa el punto de control para una arista Bezier cuadrática.
  ///
  /// El punto de control se desplaza perpendicularmente al punto medio
  /// de la arista, con curvatura = longitud de la arista * 0.2.
  /// Para aristas horizontales, el control point va hacia arriba; para
  /// verticales, hacia la izquierda — consistente vía la perpendicular.
  ///
  /// Fórmula:
  ///   cpX = midX - dy/dist * curvature
  ///   cpY = midY + dx/dist * curvature
  ///   curvature = edge.length * 0.2
  @visibleForTesting
  static Offset computeBezierControlPoint(Offset from, Offset to) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = sqrt(dx * dx + dy * dy);
    final midX = (from.dx + to.dx) / 2;
    final midY = (from.dy + to.dy) / 2;
    final curvature = dist * 0.2;

    if (dist == 0) return Offset(midX, midY);

    return Offset(
      midX - dy / dist * curvature,
      midY + dx / dist * curvature,
    );
  }

  /// Capa 2: Anillos de proximidad concéntricos alrededor de cada nodo.
  ///
  /// Dos círculos con radios ×1.5 y ×2 del radio del nodo, con alpha 0.15
  /// y 0.10 respectivamente. El color usa el color de proximidad del nodo.
  /// Si el nodo está seleccionado, la opacidad se duplica.
  void _drawProximityRings(Canvas canvas) {
    for (final node in layout.nodes) {
      final isSelected = node.id != null && node.id == selectedNodeId;
      final baseAlpha = isSelected ? 0.30 : 0.15;

      // Primer anillo (×1.5 radio)
      final ring1Paint = Paint()
        ..color = node.color.withAlpha((baseAlpha * 255).round())
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(node.x, node.y),
        node.radius * 1.5,
        ring1Paint,
      );

      // Segundo anillo (×2 radio)
      final ring2Paint = Paint()
        ..color = node.color.withAlpha(((baseAlpha * 0.66) * 255).round())
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(node.x, node.y),
        node.radius * 2,
        ring2Paint,
      );
    }
  }

  /// Capa 3: Nodos como círculos rellenos con borde blanco.
  ///
  /// Nodos conocidos (isKnown=true): relleno con color de proximidad
  /// y borde blanco sólido de 2px.
  ///
  /// Nodos desconocidos (isKnown=false): relleno gris (#9E9E9E) y
  /// borde blanco discontinuo (dashed) de 1.5px — distinción visual
  /// para que el usuario sepa qué dispositivos aún no identificó.
  void _drawNodes(Canvas canvas) {
    for (final node in layout.nodes) {
      final center = Offset(node.x, node.y);

      if (node.isKnown) {
        // Relleno con color de proximidad
        final fillPaint = Paint()
          ..color = node.color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, node.radius, fillPaint);

        // Borde blanco sólido de 2px
        final strokePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(center, node.radius, strokePaint);
      } else {
        // Relleno gris para nodo desconocido
        final fillPaint = Paint()
          ..color = const Color(0xFF9E9E9E)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, node.radius, fillPaint);

        // Borde blanco discontinuo (dashed) de 1.5px
        final strokePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        _drawDashedCircle(canvas, center, node.radius, strokePaint);
      }
    }
  }

  /// Capa 3.5: Efecto glow azul para el nodo propio (isSelf=true).
  ///
  /// Renderiza dos anillos adicionales alrededor del nodo self:
  /// - Anillo exterior (glow): círculo relleno, radius+10, azul alpha 80
  /// - Anillo interior (acento): borde azul sólido, radius+4, 4px stroke
  ///
  /// Se llama después de _drawNodes para que el glow quede detrás
  /// de las etiquetas pero sobre los nodos normales.
  void _drawSelfNode(Canvas canvas) {
    for (final node in layout.nodes) {
      if (!node.isSelf) continue;

      final center = Offset(node.x, node.y);

      // Anillo exterior de glow: relleno azul translúcido
      final glowPaint = Paint()
        ..color = const Color(0x500000FF) // azul con alpha ~0.31 (80/255)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, node.radius + 10, glowPaint);

      // Anillo interior de acento: borde azul sólido 4px
      final accentPaint = Paint()
        ..color = const Color(0xFF2196F3) // azul material
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;
      canvas.drawCircle(center, node.radius + 4, accentPaint);
    }
  }

  /// Dibuja un borde discontinuo (dashed) alrededor de una circunferencia.
  ///
  /// Flutter CustomPainter no soporta dash pattern nativo. Esta función
  /// computa manualmente segmentos dash-gap usando [PathMetrics] sobre
  /// un [Path] circular. Patrón: dash 4px, gap 3px.
  ///
  /// QUÉ problema resuelve: los nodos desconocidos necesitan un borde
  /// visualmente distinto del borde sólido de los nodos conocidos.
  void _drawDashedCircle(
      Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final dashEnd = min(distance + 4.0, metric.length);
        final extractPath = metric.extractPath(distance, dashEnd);
        canvas.drawPath(extractPath, paint);
        distance += 4.0 + 3.0; // dash + gap
      }
    }
  }

  /// Capa 4: Etiquetas de texto debajo de cada nodo.
  ///
  /// Muestra el nombre del nodo o "Desconocido" si no tiene nombre,
  /// en texto blanco de 12px centrado debajo del círculo.
  void _drawLabels(Canvas canvas) {
    for (final node in layout.nodes) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.0,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 120);

      // Centrar horizontalmente debajo del nodo (radio + 4px de separación)
      final offset = Offset(
        node.x - textPainter.width / 2,
        node.y + node.radius + 4,
      );
      textPainter.paint(canvas, offset);
    }
  }

  /// Capa 5: Anillo de selección azul sobre el nodo seleccionado.
  ///
  /// Si selectedNodeId coincide con algún nodo, dibuja un anillo
  /// exterior azul (cyan accent) de 3px de grosor.
  void _drawSelection(Canvas canvas, Map<int, GraphNode> nodeMap) {
    if (selectedNodeId == null) return;
    final selectedNode = nodeMap[selectedNodeId];
    if (selectedNode == null) return;

    final paint = Paint()
      ..color = const Color(0xFF2196F3) // azul material
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(
      Offset(selectedNode.x, selectedNode.y),
      selectedNode.radius + 4, // anillo exterior, ligeramente separado
      paint,
    );
  }

  @override
  bool shouldRepaint(GraphPainter oldDelegate) {
    // Compara LayoutResult por equality (Equatable) y selectedNodeId.
    // El costo de comparar las listas de nodos/aristas es menor que
    // el costo de repintar innecesariamente.
    return oldDelegate.layout != layout ||
        oldDelegate.selectedNodeId != selectedNodeId;
  }
}
