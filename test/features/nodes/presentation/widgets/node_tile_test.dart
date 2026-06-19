import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/widgets/node_tile.dart';

// QUÉ: Tests de renderizado de color para NodeTile.
// POR QUÉ: F14 — Node.color existe en la entidad pero nunca se usaba en la UI.
//   Verifica que el color personalizado del nodo se aplique al Card.

final _now = DateTime(2026, 6, 15, 10, 0);

/// Crea un Node con rssiHistory=[-40] (cercano, verde) para tener una
/// referencia de color de proximidad clara.
Node _testNode({
  String? name,
  String? color,
  String? suggestedName,
  String? deviceType,
  List<int> rssiHistory = const [-40],
}) {
  return Node(
    id: 1,
    bleAddress: 'AA:BB:CC:DD:EE:FF',
    name: name,
    color: color,
    firstSeen: _now,
    lastSeen: _now,
    rssiHistory: rssiHistory,
    suggestedName: suggestedName,
    deviceType: deviceType,
  );
}

/// Convierte un string hex como "#FF5722" a Color de Flutter.
Color _parseColor(String hex) =>
    Color(int.parse(hex.replaceFirst('#', '0xFF')));

void main() {
  group('NodeTile', () {
    // ─── F14: Node.color en la UI ──────────────────────────
    // QUÉ: Si el nodo tiene color personalizado, el Card debe
    //   usar ese color como fondo. Si no tiene, usa el color
    //   de proximidad como venía haciendo hasta ahora.

    testWidgets('usa node.color como fondo del Card cuando está presente',
        (tester) async {
      const customColor = '#FF5722'; // naranja
      final node = _testNode(name: 'Nodo Naranja', color: customColor);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NodeTile(node: node)),
      ));

      // El Card debe tener el color parseado de node.color.
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, _parseColor(customColor));
    });

    testWidgets(
        'usa color de proximidad como fondo cuando node.color es null',
        (tester) async {
      // Nodo cercano (RSSI=-40 → verde) sin color personalizado.
      final node = _testNode(name: 'Nodo Verde', rssiHistory: const [-40]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NodeTile(node: node)),
      ));

      final card = tester.widget<Card>(find.byType(Card));
      // El color debe ser el verde de proximidad (close → green con alpha 0.08).
      expect(card.color, Colors.green.withValues(alpha: 0.08));
    });

    testWidgets('nodo sin nombre y sin color usa proximidad + gris en texto',
        (tester) async {
      // Nodo lejano (RSSI=-86 → rojo) desconocido, sin color.
      final node = _testNode(rssiHistory: const [-86]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NodeTile(node: node)),
      ));

      // Verifica que el label es "Desconocido".
      expect(find.text('Desconocido'), findsOneWidget);

      // Verifica que el fondo usa rojo de proximidad (far → red con alpha 0.06).
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, Colors.red.withValues(alpha: 0.06));
    });

    // ─── T1.8: suggestedName en el título ─────────────────────
    // QUÉ: Cuando el nodo no tiene name pero sí suggestedName,
    // muestra el suggestedName en lugar de "Desconocido".
    // POR QUÉ: Phase 4 identity enrichment — los nombres de
    // advertisement BLE enriquecen la UI sin acción del usuario.

    testWidgets('muestra suggestedName cuando name es null', (tester) async {
      final node = _testNode(suggestedName: 'AirPods Pro');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NodeTile(node: node)),
      ));

      expect(find.text('AirPods Pro'), findsOneWidget);
      expect(find.text('Desconocido'), findsNothing);
    });

    testWidgets('prefiere name sobre suggestedName', (tester) async {
      final node = _testNode(
        name: 'Mis auris',
        suggestedName: 'AirPods Pro',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NodeTile(node: node)),
      ));

      expect(find.text('Mis auris'), findsOneWidget);
      expect(find.text('AirPods Pro'), findsNothing);
    });

    testWidgets('muestra Desconocido cuando ambos son null', (tester) async {
      final node = _testNode();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NodeTile(node: node)),
      ));

      expect(find.text('Desconocido'), findsOneWidget);
    });

    // ─── T1.9: badge de device type ───────────────────────────
    // QUÉ: Cuando el nodo tiene deviceType, se muestra un chip/badge
    // con el tipo de dispositivo debajo del nombre.
    // POR QUÉ: R3.5 — la UI debe mostrar el tipo clasificado del
    // dispositivo junto al nombre.

    testWidgets('muestra badge de device type cuando está presente',
        (tester) async {
      final node = _testNode(deviceType: 'Reloj/Fitness');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NodeTile(node: node)),
      ));

      expect(find.text('Reloj/Fitness'), findsOneWidget);
    });

    testWidgets('no muestra badge cuando deviceType es null', (tester) async {
      final node = _testNode();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NodeTile(node: node)),
      ));

      // Solo label y elementos estáticos visibles
      expect(find.text('Desconocido'), findsOneWidget);
      expect(find.byIcon(Icons.devices), findsNothing);
    });
  });
}
