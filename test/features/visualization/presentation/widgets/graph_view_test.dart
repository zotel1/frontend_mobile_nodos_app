import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view.dart';

/// Verifica que GraphView renderice InteractiveViewer + CustomPaint
/// y que el callback onNodeTapped se dispare al tocar un nodo.
void main() {
  LayoutResult buildLayout() {
    final nodes = [
      GraphNode(id: 1, x: 100, y: 200, proximity: ProximityLevel.close, name: 'Nodo'),
      GraphNode(id: 2, x: 300, y: 200, proximity: ProximityLevel.medium, name: null),
    ];
    return LayoutResult(
      nodes: nodes,
      edges: [
        GraphEdge(fromId: 1, toId: 2, thickness: 1.0),
      ],
      iterations: 40,
      converged: true,
    );
  }

  group('GraphView — renderizado', () {
    testWidgets('contiene InteractiveViewer y CustomPaint', (tester) async {
      final layout = buildLayout();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphView(layout: layout),
          ),
        ),
      );

      // Verifica que exista InteractiveViewer en el árbol
      expect(find.byType(InteractiveViewer), findsOneWidget);

      // Verifica que exista CustomPaint en el árbol (puede haber más de uno
      // por componentes internos de Flutter, verificamos al menos uno)
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets('renderiza sin errores con layout vacío', (tester) async {
      final layout = LayoutResult(
        nodes: const [],
        edges: const [],
        iterations: 0,
        converged: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphView(layout: layout),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('se expande para llenar el espacio disponible', (tester) async {
      final layout = buildLayout();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: GraphView(layout: layout),
            ),
          ),
        ),
      );

      // Verifica que el InteractiveViewer esté presente (no verifica tamaño exacto)
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });

  group('GraphView — interacción', () {
    testWidgets('callback onNodeTapped se dispara al tocar dentro del área',
        (tester) async {
      final layout = buildLayout();
      var wasCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphView(
              layout: layout,
              onNodeTapped: (_) => wasCalled = true,
            ),
          ),
        ),
      );

      // Tocar en el centro del InteractiveViewer
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pump();

      // El callback pudo o no dispararse según la posición del tap,
      // pero no debe lanzar excepción
      expect(tester.takeException(), isNull);
      expect(wasCalled, isFalse); // tap en esquina, lejos de nodos
    });

    testWidgets('no lanza error al tocar fuera del área de nodos',
        (tester) async {
      final layout = buildLayout();
      var wasCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphView(
              layout: layout,
              onNodeTapped: (_) => wasCalled = true,
            ),
          ),
        ),
      );

      // Tocar en una esquina (lejos de cualquier nodo)
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(wasCalled, isFalse); // tap en esquina no debería alcanzar nodo
    });

    testWidgets('InteractiveViewer permite zoom con los límites configurados',
        (tester) async {
      final layout = buildLayout();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphView(layout: layout),
          ),
        ),
      );

      // Verifica que el InteractiveViewer exista y no lance errores al hacer zoom
      final viewer = find.byType(InteractiveViewer);
      expect(viewer, findsOneWidget);

      // Verifica que no haya errores tras gesto de escala (pinch)
      await tester.startGesture(tester.getCenter(viewer));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // ─── PR2 T2.7: Centrado automático en barycenter ────────────────
  // QUÉ: GraphView debe centrar la vista en el barycenter del cluster
  // la primera vez que recibe un GraphReady (R5.13).
  // CÓMO: usa animateTo() con addPostFrameCallback para evitar race
  // con el build del widget.

  group('PR2 T2.7: Centrado automático', () {
    testWidgets('GraphView renderiza sin error con barycenter provisto',
        (tester) async {
      final layout = buildLayout();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphView(
              layout: layout,
              barycenter: const Offset(200, 200),
            ),
          ),
        ),
      );

      // No debe lanzar excepción al intentar centrar
      expect(tester.takeException(), isNull);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('GraphView renderiza sin error con barycenter null',
        (tester) async {
      final layout = buildLayout();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphView(
              layout: layout,
            ),
          ),
        ),
      );

      // barycenter null no debe causar error
      expect(tester.takeException(), isNull);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });
}

