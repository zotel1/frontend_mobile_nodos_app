import 'dart:async';

import 'home_page_test_support.dart';

void main() {
  late AppDatabase testDb;
  provideDummy<BleConnectionState>(const BleConnectionInitial());

  setUp(() async {
    testDb = await setUpHomePageDependencies();
  });

  tearDown(() => tearDownHomePageDependencies(testDb));

  group('HomePage', () {
    testWidgets('T3.7: toggle is3D persiste a través de SharedPreferences', (
      tester,
    ) async {
      final nodes = List.generate(
        6,
        (i) => testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );
      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: NodeListLoaded(nodes),
          visualizationState: GraphReady(testLayout),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Estado inicial: 2D → icono view_in_ar
      expect(find.byIcon(Icons.view_in_ar), findsOneWidget);

      // Cambiar a 3D
      await tester.tap(find.byIcon(Icons.view_in_ar));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verificar que se guardó en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is3D'), isTrue);
    });

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // PR2 T2.4: Stack+Offstage preserva ambos widgets (R9)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // QUÉ: al usar Stack+Offstage en lugar de if/else condicional,
    // ambos GraphView (2D) y GraphView3D (3D) deben estar siempre
    // en el árbol de widgets, sin destruirse al togglear.
    // POR QUÉ: R9, R10 — el WebView 3D no debe recargarse en cada
    // toggle; ambos widgets deben coexistir para que la transición
    // sea instantánea y sin pantalla en blanco (B2).

    testWidgets('T2.4: Stack+Offstage mantiene ambos widgets al togglear 2D/3D', (
      tester,
    ) async {
      final nodes = List.generate(
        6,
        (i) => testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );
      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: NodeListLoaded(nodes),
          visualizationState: GraphReady(testLayout),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verificar que estamos en modo grafo (prerrequisito)
      expect(
        find.byIcon(Icons.view_in_ar),
        findsOneWidget,
        reason: 'Debe estar en modo grafo (2D) con 6 nodos',
      );

      // R9: Stack+Offstage — ambos widgets deben coexistir en el árbol.
      // La app tiene ≥2 Offstage: uno para GraphView 2D y otro para
      // GraphView3D (AnimatedCrossFade puede agregar uno adicional).
      // Verificamos que hay al menos 2 y que la cantidad se mantiene
      // después del toggle (prueba que no se destruyen/recrean).
      final offstageBefore = find.byType(Offstage);
      final offstageCountBefore = tester.widgetList(offstageBefore).length;
      expect(
        offstageCountBefore,
        greaterThanOrEqualTo(2),
        reason: 'Debe haber al menos 2 Offstage: uno para 2D, uno para 3D',
      );

      // Toggle a 3D
      await tester.tap(find.byIcon(Icons.view_in_ar));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Después del toggle: el conteo de Offstage no cambia (R9 — sin destruir)
      final offstageAfter = find.byType(Offstage);
      final offstageCountAfter = tester.widgetList(offstageAfter).length;
      expect(
        offstageCountAfter,
        equals(offstageCountBefore),
        reason: 'Conteo de Offstage debe mantenerse después del toggle (R9)',
      );

      // Toggle de vuelta a 2D
      await tester.tap(find.byIcon(Icons.grid_view));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Después de múltiples toggles: estructura se mantiene (R10)
      final offstageFinal = find.byType(Offstage);
      final offstageCountFinal = tester.widgetList(offstageFinal).length;
      expect(
        offstageCountFinal,
        equals(offstageCountBefore),
        reason:
            'Conteo de Offstage debe mantenerse después de múltiples toggles (R10)',
      );
    });
  });
}
