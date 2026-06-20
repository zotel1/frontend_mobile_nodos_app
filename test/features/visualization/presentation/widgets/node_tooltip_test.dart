import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/node_tooltip.dart';

/// Verifica que el botón "Enlazar" aparezca en el NodeTooltip y que
/// el callback onEnlazar se ejecute al presionarlo.
///
/// T3.6: El NodeTooltip debe mostrar un ElevatedButton con icono Icons.link
/// y texto "Enlazar". El callback onEnlazar se dispara al presionarlo.
void main() {
  final testNode = GraphNode(
    id: 1,
    x: 100,
    y: 200,
    proximity: ProximityLevel.close,
    name: 'Nodo Alpha',
    connectionCount: 3,
  );

  testWidgets('T3.6: muestra botón "Enlazar" en el tooltip', (tester) async {
    int enlazarCallCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              // Insertar overlay después del build
              WidgetsBinding.instance.addPostFrameCallback((_) {
                NodeTooltip.show(
                  context: context,
                  node: testNode,
                  globalPosition: const Offset(150, 150),
                  onDismiss: () {},
                  onEnlazar: () {
                    enlazarCallCount++;
                  },
                );
              });
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    // Esperar que el overlay se inserte y renderice
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verificar que el botón Enlazar está presente
    expect(find.text('Enlazar'), findsOneWidget);
    expect(find.byIcon(Icons.link), findsOneWidget);

    // Presionar el botón
    await tester.tap(find.text('Enlazar'));
    await tester.pump();

    // Verificar que el callback se llamó
    expect(enlazarCallCount, equals(1));
  });

  testWidgets('T3.10: botón Enlazar deshabilitado cuando connectable=false',
      (tester) async {
    final nonConnectableNode = GraphNode(
      id: 99,
      x: 100,
      y: 200,
      proximity: ProximityLevel.close,
      name: 'No Conectable',
      connectable: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                NodeTooltip.show(
                  context: context,
                  node: nonConnectableNode,
                  globalPosition: const Offset(150, 150),
                  onDismiss: () {},
                  onEnlazar: () {},
                );
              });
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // El texto "Enlazar" debe estar presente
    expect(find.text('Enlazar'), findsOneWidget);

    // El botón debe estar deshabilitado
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Enlazar'),
    );
    expect(button.onPressed, isNull);

    // Tooltip informativo visible
    expect(find.text('Dispositivo no conectable'), findsOneWidget);
  });
}
