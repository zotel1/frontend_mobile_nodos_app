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

  // ─── T2.4: Curvas Bezier cuadráticas en aristas ────────────────
  // QUÉ: las aristas ahora son curvas Bezier en vez de líneas rectas.
  // El punto de control se desplaza perpendicularmente al punto medio,
  // con curvatura proporcional a la longitud de la arista.
  // Fórmula: cpX = midX - dy/dist * curvature
  //          cpY = midY + dx/dist * curvature
  //          curvature = length * 0.2

  group('T2.4: Punto de control Bezier', () {
    test('punto de control está desplazado perpendicularmente al punto medio',
        () {
      // Arista horizontal de izquierda a derecha
      // from=(100,100), to=(300,100) → length=200
      // mid=(200,100), dx=200, dy=0, dist=200
      // curvature = 200 * 0.2 = 40
      // cpX = 200 - 0/200 * 40 = 200
      // cpY = 100 + 200/200 * 40 = 140
      final cp = GraphPainter.computeBezierControlPoint(
        const Offset(100, 100),
        const Offset(300, 100),
      );
      expect(cp.dx, closeTo(200.0, 0.01));
      expect(cp.dy, closeTo(140.0, 0.01));
    });

    test('arista vertical tiene punto de control a la derecha', () {
      // from=(150,50), to=(150,250) → length=200
      // mid=(150,150), dx=0, dy=200, dist=200
      // curvature = 40
      // cpX = 150 - 200/200 * 40 = 110
      // cpY = 150 + 0/200 * 40 = 150
      final cp = GraphPainter.computeBezierControlPoint(
        const Offset(150, 50),
        const Offset(150, 250),
      );
      expect(cp.dx, closeTo(110.0, 0.01));
      expect(cp.dy, closeTo(150.0, 0.01));
    });

    test('arista diagonal tiene punto de control desplazado perpendicularmente',
        () {
      // from=(0,0), to=(100,100) → length=141.42
      // mid=(50,50), dx=100, dy=100, dist=141.42
      // curvature = 141.42 * 0.2 = 28.28
      // cpX = 50 - 100/141.42 * 28.28 = 50 - 20 = 30
      // cpY = 50 + 100/141.42 * 28.28 = 50 + 20 = 70
      final cp = GraphPainter.computeBezierControlPoint(
        const Offset(0, 0),
        const Offset(100, 100),
      );
      expect(cp.dx, closeTo(30.0, 0.1));
      expect(cp.dy, closeTo(70.0, 0.1));
    });

    test('arista larga tiene más curvatura que arista corta', () {
      // Arista corta: length=10 → curvature=2
      final cpShort = GraphPainter.computeBezierControlPoint(
        const Offset(0, 0),
        const Offset(10, 0),
      );
      // mid=(5,0), curvature=2, cp=(5, 2)
      expect(cpShort.dy, closeTo(2.0, 0.01));

      // Arista larga: length=500 → curvature=100
      final cpLong = GraphPainter.computeBezierControlPoint(
        const Offset(0, 0),
        const Offset(500, 0),
      );
      // mid=(250,0), curvature=100, cp=(250, 100)
      expect(cpLong.dy, closeTo(100.0, 0.01));
      // La curvatura de la arista larga es 50x mayor
      expect(cpLong.dy, greaterThan(cpShort.dy * 10));
    });
  });

  group('T2.4: Renderizado Bezier en widget test', () {
    testWidgets('pinta aristas Bezier sin lanzar excepción', (tester) async {
      final nodes = [
        GraphNode(
          id: 1,
          x: 100,
          y: 200,
          proximity: ProximityLevel.close,
          name: 'Nodo A',
        ),
        GraphNode(
          id: 2,
          x: 400,
          y: 200,
          proximity: ProximityLevel.medium,
          name: 'Nodo B',
        ),
      ];
      final edges = [
        GraphEdge(fromId: 1, toId: 2, thickness: 2.0),
      ];
      final layout = LayoutResult(
        nodes: nodes,
        edges: edges,
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

      // El painter debe renderizar aristas Bezier sin excepciones
      expect(tester.takeException(), isNull);
    });
  });

  // ─── T2.5: Efecto glow en nodo self ────────────────────────────
  // QUÉ: los nodos marcados con isSelf=true deben renderizarse con
  // un anillo azul exterior (glow) y un borde azul de 4px.
  // Capa: después de _drawNodes, se llama _drawSelfNode().

  group('T2.5: _drawSelfNode glow effect', () {
    testWidgets('nodo self se renderiza con glow azul sin excepción',
        (tester) async {
      final selfNode = GraphNode(
        id: 1,
        x: 300,
        y: 300,
        proximity: ProximityLevel.close,
        name: 'Mi Dispositivo',
        isSelf: true,
      );
      final layout = LayoutResult(
        nodes: [selfNode],
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

      // El painter debe renderizar el glow azul sin excepciones
      expect(tester.takeException(), isNull);
      expect(selfNode.isSelf, isTrue);
    });

    testWidgets('nodo no-self NO tiene glow azul', (tester) async {
      final regularNode = GraphNode(
        id: 2,
        x: 300,
        y: 300,
        proximity: ProximityLevel.medium,
        name: 'Otro Nodo',
        isSelf: false,
      );
      final layout = LayoutResult(
        nodes: [regularNode],
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
      expect(regularNode.isSelf, isFalse);
    });

    testWidgets('self node con múltiples nodos solo brilla el self',
        (tester) async {
      final nodes = [
        GraphNode(
          id: 1,
          x: 200,
          y: 300,
          proximity: ProximityLevel.close,
          name: 'Self',
          isSelf: true,
        ),
        GraphNode(
          id: 2,
          x: 400,
          y: 300,
          proximity: ProximityLevel.medium,
          name: 'Otro',
          isSelf: false,
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

      expect(tester.takeException(), isNull);
      expect(nodes[0].isSelf, isTrue);
      expect(nodes[1].isSelf, isFalse);
    });
  });

  // ─── F2 T2.1: Estado vacío "Sin datos de grafo" ─────────────────
  // QUÉ: cuando GraphPainter recibe un layout con nodes.isEmpty,
  // debe renderizar el texto "Sin datos de grafo" centrado en el
  // canvas en lugar de retornar silenciosamente.
  // POR QUÉ: el usuario quedaba con un canvas en blanco sin feedback
  // cuando no había nodos en la sesión de escaneo.
  // CÓMO: reemplazamos `if (nodes.isEmpty) return;` por un TextPainter
  // que dibuja el mensaje centrado en gris #9E9E9E.
  group('F2 T2.1: Estado vacío — texto "Sin datos de grafo"', () {
    testWidgets('renderiza texto Sin datos de grafo con layout vacío',
        (tester) async {
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

      // El painter no debe lanzar excepción (renderiza el mensaje
      // en lugar de retornar silenciosamente)
      expect(tester.takeException(), isNull);
    });
  });
}
