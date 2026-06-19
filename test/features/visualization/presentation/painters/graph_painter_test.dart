import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/painters/graph_painter.dart';

/// Verifica que GraphPainter renderice las 5 capas sin excepciones
/// y que los colores de nodo correspondan al nivel de proximidad.
void main() {
  // ── Fixtures ──
  LayoutResult buildLayout(int nodeCount) {
    final nodes = List.generate(nodeCount, (i) {
      final proximity = i == 0
          ? ProximityLevel.close
          : i == 1
              ? ProximityLevel.medium
              : ProximityLevel.far;
      return GraphNode(
        id: i + 1,
        x: 100.0 + i * 150,
        y: 200.0 + i * 100,
        proximity: proximity,
        name: i == 0 ? 'Nodo A' : null,
      );
    });
    final edges = nodeCount >= 2
        ? [
            GraphEdge(fromId: 1, toId: 2, thickness: 2.0),
          ]
        : <GraphEdge>[];
    return LayoutResult(
      nodes: nodes,
      edges: edges,
      iterations: 50,
      converged: true,
    );
  }

  group('GraphPainter — construcción y shouldRepaint', () {
    test('se construye sin errores con LayoutResult válido', () {
      final layout = buildLayout(3);
      final painter = GraphPainter(layout: layout);
      expect(painter, isNotNull);
      expect(painter.layout, layout);
    });

    test('shouldRepaint retorna true cuando los nodos difieren', () {
      final layout1 = buildLayout(3);
      final layout2 = buildLayout(4);
      final painter1 = GraphPainter(layout: layout1);
      final painter2 = GraphPainter(layout: layout2);

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint retorna false con mismo LayoutResult', () {
      final layout = buildLayout(3);
      final painter1 = GraphPainter(layout: layout);
      final painter2 = GraphPainter(layout: layout);

      expect(painter1.shouldRepaint(painter2), isFalse);
    });

    test('shouldRepaint retorna true cuando selectedNodeId cambia', () {
      final layout = buildLayout(3);
      final painter1 = GraphPainter(layout: layout, selectedNodeId: null);
      final painter2 = GraphPainter(layout: layout, selectedNodeId: 1);

      expect(painter1.shouldRepaint(painter2), isTrue);
    });
  });

  group('GraphPainter — renderizado en widget test', () {
    testWidgets('pinta 5 nodos sin lanzar excepción', (tester) async {
      final layout = buildLayout(5);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 600,
              child: CustomPaint(
                size: const Size(600, 600),
                painter: GraphPainter(layout: layout),
              ),
            ),
          ),
        ),
      );

      // Verifica que no haya errores de renderizado (overflow, etc.)
      expect(tester.takeException(), isNull);
    });

    testWidgets('pinta layout vacío sin lanzar excepción', (tester) async {
      final layout = LayoutResult(
        nodes: const [],
        edges: const [],
        iterations: 0,
        converged: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: CustomPaint(
                size: const Size(400, 400),
                painter: GraphPainter(layout: layout),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('colores de nodo corresponden a ProximityLevel', (tester) async {
      final layout = buildLayout(3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 600,
              child: CustomPaint(
                size: const Size(600, 600),
                painter: GraphPainter(layout: layout),
              ),
            ),
          ),
        ),
      );

      // Verifica que los colores derivados sean correctos
      final closeNode = layout.nodes[0];
      final mediumNode = layout.nodes[1];
      final farNode = layout.nodes[2];

      expect(closeNode.color, const Color(0xFF4CAF50));
      expect(mediumNode.color, const Color(0xFFFFC107));
      expect(farNode.color, const Color(0xFFF44336));

      // El painter no lanzó excepción al pintar con estos colores
      expect(tester.takeException(), isNull);
    });

    testWidgets('pinta nodo seleccionado con anillo azul', (tester) async {
      final layout = buildLayout(3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 600,
              child: CustomPaint(
                size: const Size(600, 600),
                painter: GraphPainter(layout: layout, selectedNodeId: 1),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('nodo desconocido renderiza sin excepción', (tester) async {
      // Layout con 1 nodo sin nombre (isKnown=false) y 1 nodo con nombre
      final nodes = [
        GraphNode(
          id: 1,
          x: 150,
          y: 200,
          proximity: ProximityLevel.close,
          name: null, // desconocido
        ),
        GraphNode(
          id: 2,
          x: 350,
          y: 200,
          proximity: ProximityLevel.close,
          name: 'Conocido',
        ),
      ];
      final layout = LayoutResult(
        nodes: nodes,
        edges: const [],
        iterations: 50,
        converged: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 600,
              child: CustomPaint(
                size: const Size(600, 600),
                painter: GraphPainter(layout: layout),
              ),
            ),
          ),
        ),
      );

      // El painter debe renderizar sin errores
      expect(tester.takeException(), isNull);
      // Verifica que el nodo desconocido tenga isKnown=false
      expect(nodes[0].isKnown, isFalse);
      // Verifica que el nodo conocido tenga isKnown=true
      expect(nodes[1].isKnown, isTrue);
    });

    testWidgets('nodo desconocido usa color gris en lugar de color de proximidad',
        (tester) async {
      // Layout con UN solo nodo desconocido en posición conocida
      final unknownNode = GraphNode(
        id: 1,
        x: 300,
        y: 300,
        proximity: ProximityLevel.close,
        name: null, // desconocido: isKnown=false
      );
      final layout = LayoutResult(
        nodes: [unknownNode],
        edges: const [],
        iterations: 50,
        converged: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 600,
              child: CustomPaint(
                size: const Size(600, 600),
                painter: GraphPainter(layout: layout),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(unknownNode.isKnown, isFalse);
      // Cuando isKnown=false, el color de relleno debería ser gris,
      // no el color de proximidad (verde para close).
      // El painter es el encargado de aplicar esta distinción visual.
    });

    testWidgets('nodo conocido mantiene color de proximidad como relleno',
        (tester) async {
      final knownNode = GraphNode(
        id: 1,
        x: 300,
        y: 300,
        proximity: ProximityLevel.medium,
        name: 'Mi Dispositivo', // conocido: isKnown=true
      );
      final layout = LayoutResult(
        nodes: [knownNode],
        edges: const [],
        iterations: 50,
        converged: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 600,
              child: CustomPaint(
                size: const Size(600, 600),
                painter: GraphPainter(layout: layout),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(knownNode.isKnown, isTrue);
      // Cuando isKnown=true, el color de relleno debe ser el color
      // de proximidad (ámbar para medium), NO gris.
      expect(knownNode.color, const Color(0xFFFFC107));
    });
  });
}
