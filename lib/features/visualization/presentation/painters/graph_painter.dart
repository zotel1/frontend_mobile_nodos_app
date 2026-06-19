import 'package:flutter/material.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// CustomPainter que renderiza el grafo de nodos BLE en 5 capas.
///
/// Capas de pintado (en orden back-to-front):
/// 1. Aristas (edges) — líneas entre nodos co-detectados
/// 2. Anillos de proximidad — círculos concéntricos con alpha decreciente
/// 3. Nodos — círculos rellenos con color de proximidad y borde blanco
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
    _drawLabels(canvas);
    _drawSelection(canvas, nodeMap);
  }

  /// Capa 1: Aristas entre nodos co-detectados.
  ///
  /// Dibuja líneas cuyo color interpola entre verde (RSSI fuerte)
  /// y rojo (RSSI débil) según el grosor de la arista, que es proxy
  /// de la frecuencia de co-detección.
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

      canvas.drawLine(
        Offset(fromNode.x, fromNode.y),
        Offset(toNode.x, toNode.y),
        paint,
      );
    }
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
  /// Cada nodo se dibuja como un círculo relleno con el color derivado
  /// de su nivel de proximidad, seguido de un borde blanco de 2px.
  void _drawNodes(Canvas canvas) {
    for (final node in layout.nodes) {
      final center = Offset(node.x, node.y);

      // Relleno con color de proximidad
      final fillPaint = Paint()
        ..color = node.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, node.radius, fillPaint);

      // Borde blanco de 2px
      final strokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, node.radius, strokePaint);
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
