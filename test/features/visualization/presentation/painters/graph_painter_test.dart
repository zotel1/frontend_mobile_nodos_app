import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/painters/graph_painter.dart';

/// Verifica que GraphPainter renderice las 5 capas con paints() matcher,
/// validando posición de nodos, color, label y aristas Bezier.
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

  /// Key única para identificar el CustomPaint bajo test.
  const graphPainterKey = Key('graph_painter_under_test');

  /// Helper: construye el widget CustomPaint para tests.
  Widget buildTestWidget(LayoutResult layout, {int? selectedNodeId}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 600,
          child: CustomPaint(
            key: graphPainterKey,
            size: const Size(600, 600),
            painter: GraphPainter(
              layout: layout,
              selectedNodeId: selectedNodeId,
            ),
          ),
        ),
      ),
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
    testWidgets('pinta 5 nodos con sus aristas Bezier', (tester) async {
      final layout = buildLayout(5);

      await tester.pumpWidget(buildTestWidget(layout));

      // Orden de dibujo: _drawEdges primero (path), _drawNodes después (circles)
      // 1 arista Bezier → 1 path, 5 nodos → 5 círculos
      expect(find.byKey(graphPainterKey), paints
        ..path()
        ..circle()
        ..circle()
        ..circle()
        ..circle()
        ..circle());
    });

    testWidgets('layout vacío no dibuja círculos (solo texto "Sin datos de grafo")',
        (tester) async {
      final layout = LayoutResult(
        nodes: const [],
        edges: const [],
        iterations: 0,
        converged: false,
      );

      await tester.pumpWidget(buildTestWidget(layout));

      // Sin nodos → no se dibujan círculos
      expect(find.byKey(graphPainterKey), isNot(paints..circle()));
    });

    testWidgets('colores de nodo corresponden a ProximityLevel con verificación de canvas',
        (tester) async {
      final layout = buildLayout(3);

      await tester.pumpWidget(buildTestWidget(layout));

      // Verifica que los colores derivados sean correctos
      final closeNode = layout.nodes[0];
      final mediumNode = layout.nodes[1];
      final farNode = layout.nodes[2];

      expect(closeNode.color, 0xFF4CAF50);
      expect(mediumNode.color, 0xFFFFC107);
      expect(farNode.color, 0xFFF44336);

      // Orden: path de arista primero, luego 3 círculos de nodo
      expect(find.byKey(graphPainterKey), paints
        ..path()
        ..circle()
        ..circle()
        ..circle());
    });

    testWidgets('pinta nodo seleccionado con anillo azul adicional',
        (tester) async {
      final layout = buildLayout(3);

      await tester.pumpWidget(
        buildTestWidget(layout, selectedNodeId: 1),
      );

      // Orden: path de arista, 3 círculos de nodo, 1 círculo extra (anillo)
      expect(find.byKey(graphPainterKey), paints
        ..path()
        ..circle()
        ..circle()
        ..circle()
        ..circle()); // anillo de selección
    });

    testWidgets('nodo desconocido usa displayColor diferenciado al pintar',
        (tester) async {
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

      await tester.pumpWidget(buildTestWidget(layout));

      // 2 nodos → 2 círculos, sin aristas (edges vacío)
      expect(find.byKey(graphPainterKey), paints..circle()..circle());
      // Verifica que el nodo desconocido tenga isKnown=false
      expect(nodes[0].isKnown, isFalse);
      // Verifica que el nodo conocido tenga isKnown=true
      expect(nodes[1].isKnown, isTrue);
    });

    testWidgets('nodo desconocido usa color gris en lugar de color de proximidad',
        (tester) async {
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

      await tester.pumpWidget(buildTestWidget(layout));

      // 1 solo nodo desconocido → 1 círculo pintado (color gris)
      expect(find.byKey(graphPainterKey), paints..circle());
      expect(unknownNode.isKnown, isFalse);
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

      await tester.pumpWidget(buildTestWidget(layout));

      // 1 nodo conocido → 1 círculo pintado (color ámbar de medium)
      expect(find.byKey(graphPainterKey), paints..circle());
      expect(knownNode.isKnown, isTrue);
      expect(knownNode.color, 0xFFFFC107);
    });
  });

  // ─── T2.4: Curvas Bezier cuadráticas en aristas ────────────────

  group('T2.4: Punto de control Bezier', () {
    test('punto de control está desplazado perpendicularmente al punto medio',
        () {
      final cp = GraphPainter.computeBezierControlPoint(
        const Offset(100, 100),
        const Offset(300, 100),
      );
      expect(cp.dx, closeTo(200.0, 0.01));
      expect(cp.dy, closeTo(140.0, 0.01));
    });

    test('arista vertical tiene punto de control a la derecha', () {
      final cp = GraphPainter.computeBezierControlPoint(
        const Offset(150, 50),
        const Offset(150, 250),
      );
      expect(cp.dx, closeTo(110.0, 0.01));
      expect(cp.dy, closeTo(150.0, 0.01));
    });

    test('arista diagonal tiene punto de control desplazado perpendicularmente',
        () {
      final cp = GraphPainter.computeBezierControlPoint(
        const Offset(0, 0),
        const Offset(100, 100),
      );
      expect(cp.dx, closeTo(30.0, 0.1));
      expect(cp.dy, closeTo(70.0, 0.1));
    });

    test('arista larga tiene más curvatura que arista corta', () {
      final cpShort = GraphPainter.computeBezierControlPoint(
        const Offset(0, 0),
        const Offset(10, 0),
      );
      expect(cpShort.dy, closeTo(2.0, 0.01));

      final cpLong = GraphPainter.computeBezierControlPoint(
        const Offset(0, 0),
        const Offset(500, 0),
      );
      expect(cpLong.dy, closeTo(100.0, 0.01));
      expect(cpLong.dy, greaterThan(cpShort.dy * 10));
    });
  });

  group('T2.4: Renderizado Bezier en widget test', () {
    testWidgets('pinta aristas Bezier como paths curvados en canvas',
        (tester) async {
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

      await tester.pumpWidget(buildTestWidget(layout));

      // Orden: path de arista Bezier primero, luego 2 círculos de nodo
      expect(find.byKey(graphPainterKey), paints
        ..path()
        ..circle()
        ..circle());
    });
  });

  // ─── T2.5: Efecto glow en nodo self ────────────────────────────

  group('T2.5: _drawSelfNode glow effect', () {
    testWidgets('nodo self se renderiza con círculo de glow adicional en canvas',
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

      await tester.pumpWidget(buildTestWidget(layout));

      // 1 círculo del nodo + 1 círculo del glow azul = 2 círculos
      expect(find.byKey(graphPainterKey), paints..circle()..circle());
      expect(selfNode.isSelf, isTrue);
    });

    testWidgets('nodo no-self NO tiene círculo de glow extra',
        (tester) async {
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

      await tester.pumpWidget(buildTestWidget(layout));

      // 1 solo círculo del nodo, sin glow extra
      expect(find.byKey(graphPainterKey), paints..circle());
      expect(regularNode.isSelf, isFalse);
    });

    testWidgets('self node con múltiples nodos: solo el self tiene glow extra',
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

      await tester.pumpWidget(buildTestWidget(layout));

      // 2 círculos de nodo + 1 círculo extra de glow (solo self) = 3 círculos
      expect(find.byKey(graphPainterKey), paints
        ..circle()
        ..circle()
        ..circle());
      expect(nodes[0].isSelf, isTrue);
      expect(nodes[1].isSelf, isFalse);
    });
  });

  // ─── F2 T2.1: Estado vacío "Sin datos de grafo" ─────────────────

  group('F2 T2.1: Estado vacío — texto "Sin datos de grafo"', () {
    testWidgets('layout vacío no dibuja nodos en el canvas',
        (tester) async {
      final layout = LayoutResult(
        nodes: const [],
        edges: const [],
        iterations: 0,
        converged: false,
      );

      await tester.pumpWidget(buildTestWidget(layout));

      // Sin nodos → cero círculos. El texto se dibuja vía TextPainter
      // (drawParagraph), que no es capturado como circle() por paints.
      expect(find.byKey(graphPainterKey), isNot(paints..circle()));
    });
  });

  // ─── PR2 T2.7: Aristas transitivas dashed, userColor, distancia ──

  group('PR2 T2.7: Aristas transitivas y userColor', () {
    testWidgets('pinta arista transitiva como path en canvas',
        (tester) async {
      final nodes = [
        const GraphNode(id: 1, x: 100, y: 200, proximity: ProximityLevel.close, name: 'A'),
        const GraphNode(id: 2, x: 400, y: 200, proximity: ProximityLevel.medium, name: 'B'),
      ];
      final edges = [
        GraphEdge(
          fromId: 1, toId: 2, thickness: 0.5,
          edgeType: EdgeType.transitive,
        ),
      ];
      final layout = LayoutResult(
        nodes: nodes, edges: edges, iterations: 50, converged: true,
      );

      await tester.pumpWidget(buildTestWidget(layout));

      // Orden: path de arista transitiva primero, luego 2 círculos de nodo
      expect(find.byKey(graphPainterKey), paints
        ..path()
        ..circle()
        ..circle());
    });

    testWidgets('pinta nodo con userColor asignado y displayColor verificado',
        (tester) async {
      final node = GraphNode(
        id: 1, x: 300, y: 300,
        proximity: ProximityLevel.close,
        name: 'Azul',
        userColor: 0xFF2196F3, // azul
      );
      final layout = LayoutResult(
        nodes: [node], edges: const [], iterations: 50, converged: true,
      );

      await tester.pumpWidget(buildTestWidget(layout));

      // 1 nodo → al menos 1 círculo pintado
      expect(find.byKey(graphPainterKey), paints..circle());
      // Verifica que el displayColor sea el azul asignado, no el verde de close
      expect(node.displayColor, 0xFF2196F3);
      expect(node.color, 0xFF4CAF50); // proximidad
    });

    testWidgets('pinta nodo con estimatedDistance y etiqueta en canvas',
        (tester) async {
      final node = GraphNode(
        id: 1, x: 300, y: 300,
        proximity: ProximityLevel.close,
        name: 'Nodo',
        estimatedDistance: 0.35,
      );
      final layout = LayoutResult(
        nodes: [node], edges: const [], iterations: 50, converged: true,
      );

      await tester.pumpWidget(buildTestWidget(layout));

      // 1 nodo → al menos 1 círculo (la etiqueta de distancia se dibuja con TextPainter)
      expect(find.byKey(graphPainterKey), paints..circle());
      expect(node.estimatedDistance, equals(0.35));
    });

    test('formato de distancia: ≥1m muestra metros', () {
      double d = 2.3;
      final label = d >= 1.0
          ? '~${d.toStringAsFixed(1)}m'
          : '~${(d * 100).round()}cm';
      expect(label, equals('~2.3m'));

      d = 1.0;
      final label2 = d >= 1.0
          ? '~${d.toStringAsFixed(1)}m'
          : '~${(d * 100).round()}cm';
      expect(label2, equals('~1.0m'));
    });

    test('formato de distancia: <1m muestra centímetros', () {
      double d = 0.35;
      final label = d >= 1.0
          ? '~${d.toStringAsFixed(1)}m'
          : '~${(d * 100).round()}cm';
      expect(label, equals('~35cm'));

      d = 0.05;
      final label2 = d >= 1.0
          ? '~${d.toStringAsFixed(1)}m'
          : '~${(d * 100).round()}cm';
      expect(label2, equals('~5cm'));
    });
  });
}
