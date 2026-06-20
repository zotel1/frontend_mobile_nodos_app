import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view_3d.dart';

// ─── Stub de WebViewPlatform para tests widget ──────────────────────
// Permite que WebViewWidget y WebViewController se instancien en tests
// sin una plataforma nativa real.

class _StubWebViewWidget extends PlatformWebViewWidget {
  _StubWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(key: Key('stub_webview'));
  }
}

class _StubWebViewController extends PlatformWebViewController {
  _StubWebViewController(super.params) : super.implementation();

  final List<String> loadedAssets = [];
  final List<JavaScriptChannelParams> channels = [];
  final List<String> executedJs = [];

  @override
  Future<void> loadFlutterAsset(String key) async {
    loadedAssets.add(key);
  }

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channels.add(params);
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    executedJs.add(javaScript);
  }
}

class _StubWebViewPlatform extends WebViewPlatform
    with MockPlatformInterfaceMixin {
  _StubWebViewController? _controller;

  _StubWebViewController get controller => _controller!;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    _controller = _StubWebViewController(params);
    return _controller!;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _StubWebViewWidget(params);
  }

  @override
  // ignore: override_on_non_overriding_member
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    throw UnimplementedError();
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    throw UnimplementedError();
  }
}

void main() {
  late _StubWebViewPlatform stubPlatform;

  setUp(() {
    stubPlatform = _StubWebViewPlatform();
    WebViewPlatform.instance = stubPlatform;
  });

  // ═══════════ T4.6: Serialización JSON ═══════════════════════════

  group('T4.6: layoutResultToJson', () {
    final testNodes = [
      const GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        name: 'Mi Dispositivo',
        suggestedName: 'Phone',
        connectionCount: 3,
        isSelf: true,
        connectable: true,
      ),
      const GraphNode(
        id: 2,
        x: 300.0,
        y: 400.0,
        proximity: ProximityLevel.medium,
        name: null,
        suggestedName: 'AirPods',
        connectionCount: 1,
        isSelf: false,
        connectable: true,
      ),
      const GraphNode(
        id: 3,
        x: 500.0,
        y: 600.0,
        proximity: ProximityLevel.far,
        name: null,
        suggestedName: null,
        connectionCount: 0,
        isSelf: false,
        connectable: false,
      ),
    ];

    final testEdges = [
      const GraphEdge(fromId: 1, toId: 2, thickness: 2.0),
      const GraphEdge(fromId: 2, toId: 3, thickness: 1.0),
    ];

    final layout = LayoutResult(
      nodes: testNodes,
      edges: testEdges,
      iterations: 100,
      converged: true,
    );

    test('convierte LayoutResult a estructura JSON con nodos y aristas', () {
      final json = layoutResultToJson(layout);

      expect(json, isA<Map<String, dynamic>>());
      expect(json.containsKey('nodes'), isTrue);
      expect(json.containsKey('edges'), isTrue);

      final nodes = json['nodes'] as List<dynamic>;
      expect(nodes.length, equals(3));

      // Nodo 0: self node con nombre asignado
      final node0 = nodes[0] as Map<String, dynamic>;
      expect(node0['id'], equals(1));
      expect(node0['x'], equals(100.0));
      expect(node0['y'], equals(200.0));
      expect(node0['z'], equals(0));
      expect(node0['radius'], equals(21.0));
      expect(node0['color'], equals('#4caf50'));
      expect(node0['label'], equals('Mi Dispositivo'));
      expect(node0['isSelf'], isTrue);

      // Nodo 1: nodo con suggestedName (name null)
      final node1 = nodes[1] as Map<String, dynamic>;
      expect(node1['id'], equals(2));
      expect(node1['radius'], equals(15.0));
      expect(node1['color'], equals('#ffc107'));
      expect(node1['label'], equals('AirPods'));
      expect(node1['isSelf'], isFalse);

      // Nodo 2: nodo desconocido
      final node2 = nodes[2] as Map<String, dynamic>;
      expect(node2['id'], equals(3));
      expect(node2['radius'], equals(12.0));
      expect(node2['color'], equals('#f44336'));
      expect(node2['label'], equals('Desconocido'));
      expect(node2['isSelf'], isFalse);
    });

    test('serializa aristas con fromId, toId, y thickness', () {
      final json = layoutResultToJson(layout);

      final edges = json['edges'] as List<dynamic>;
      expect(edges.length, equals(2));

      final edge0 = edges[0] as Map<String, dynamic>;
      expect(edge0['fromId'], equals(1));
      expect(edge0['toId'], equals(2));
      expect(edge0['thickness'], equals(2.0));

      final edge1 = edges[1] as Map<String, dynamic>;
      expect(edge1['fromId'], equals(2));
      expect(edge1['toId'], equals(3));
      expect(edge1['thickness'], equals(1.0));
    });

    test('maneja LayoutResult con 0 nodos y 0 aristas', () {
      final empty = LayoutResult(
        nodes: [],
        edges: [],
        iterations: 0,
        converged: false,
      );

      final json = layoutResultToJson(empty);
      expect(json['nodes'], isEmpty);
      expect(json['edges'], isEmpty);
    });

    test('usa z=0 para todos los nodos (preparacion PR5)', () {
      final json = layoutResultToJson(layout);
      final nodes = json['nodes'] as List<dynamic>;
      for (final node in nodes) {
        final n = node as Map<String, dynamic>;
        expect(n['z'], equals(0));
      }
    });

    // ─── T5.5: serializa z desde GraphNode.z (no hardcodeado) ─────
    // QUÉ: layoutResultToJson debe leer n.z en lugar de hardcodear 0.
    // POR QUÉ: R6.2–3 — el grafo 3D necesita coordenadas Z reales
    // calculadas por el algoritmo FR extendido (T5.2).

    test('T5.5: serializa z desde GraphNode.z en vez de hardcodear 0', () {
      final layoutWithZ = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1, x: 100.0, y: 200.0,
            proximity: ProximityLevel.close,
            z: 350.0,
          ),
          const GraphNode(
            id: 2, x: 300.0, y: 400.0,
            proximity: ProximityLevel.medium,
            z: 150.0,
          ),
        ],
        edges: [],
        iterations: 1,
        converged: true,
      );

      final json = layoutResultToJson(layoutWithZ);
      final nodes = json['nodes'] as List<dynamic>;
      final node0 = nodes[0] as Map<String, dynamic>;
      final node1 = nodes[1] as Map<String, dynamic>;

      expect(node0['z'], equals(350.0));
      expect(node1['z'], equals(150.0));
    });

    test('T5.5: z=0 para nodos sin z explícito (default)', () {
      final layoutNoZ = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1, x: 100.0, y: 200.0,
            proximity: ProximityLevel.close,
          ),
        ],
        edges: [],
        iterations: 1,
        converged: true,
      );

      final json = layoutResultToJson(layoutNoZ);
      final nodes = json['nodes'] as List<dynamic>;
      final node0 = nodes[0] as Map<String, dynamic>;
      expect(node0['z'], equals(0.0));
    });
  });

  // ═══════════ T4.5: Widget GraphView3D ═══════════════════════════

  group('T4.5: GraphView3D widget', () {
    testWidgets('crea WebViewWidget y configura controller con asset', (
      WidgetTester tester,
    ) async {
      final layout = LayoutResult(
        nodes: [const GraphNode(id: 1, x: 0, y: 0, proximity: ProximityLevel.medium)],
        edges: [],
        iterations: 1,
        converged: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GraphView3D(layout: layout),
        ),
      );

      // Verifica que el WebViewWidget existe en el árbol (vía stub)
      expect(find.byKey(const Key('stub_webview')), findsOneWidget);

      // Verifica que se solicitó cargar el asset correcto
      final controller = stubPlatform.controller;
      expect(controller.loadedAssets, contains('assets/three_graph/graph_3d.html'));
    });

    testWidgets('inyecta datos JSON via runJavaScript al recibir layout', (
      WidgetTester tester,
    ) async {
      final layout = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1,
            x: 10,
            y: 20,
            proximity: ProximityLevel.close,
          ),
        ],
        edges: [],
        iterations: 1,
        converged: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GraphView3D(layout: layout),
        ),
      );

      // Espera a que se complete la carga del asset y la inyección JS
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final controller = stubPlatform.controller;
      // Verifica que se ejecutó JavaScript con los datos
      final jsCalls = controller.executedJs
          .where((js) => js.contains('loadGraphData'))
          .toList();
      expect(jsCalls, isNotEmpty, reason: 'Debe inyectar datos via runJavaScript');
    });
  });

  // ═══════════ T4.7: JavaScriptChannel tap bridge ═════════════════

  group('T4.7: JavaScriptChannel onNodeTapped', () {
    testWidgets('configura canal onNodeTapped y dispara callback', (
      WidgetTester tester,
    ) async {
      int? tappedNodeId;

      final layout = LayoutResult(
        nodes: [const GraphNode(id: 42, x: 0, y: 0, proximity: ProximityLevel.medium)],
        edges: [],
        iterations: 1,
        converged: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GraphView3D(
            layout: layout,
            onNodeTapped: (nodeId) => tappedNodeId = nodeId,
          ),
        ),
      );

      final controller = stubPlatform.controller;

      // Verifica que el canal JavaScript fue registrado con nombre 'onNodeTapped'
      final onNodeTappedChannel = controller.channels
          .where((ch) => ch.name == 'onNodeTapped')
          .toList();
      expect(onNodeTappedChannel.length, equals(1),
          reason: 'Debe registrar el canal onNodeTapped');

      // Simula un mensaje JavaScript con un nodeId válido
      final channelParams = onNodeTappedChannel.first;
      channelParams.onMessageReceived(JavaScriptMessage(message: '42'));

      // Verifica que el callback Dart se disparó con el ID correcto
      expect(tappedNodeId, equals(42));
    });

    testWidgets('ignora mensajes JS con formato inválido', (
      WidgetTester tester,
    ) async {
      int? tappedNodeId;

      final layout = LayoutResult(
        nodes: [const GraphNode(id: 1, x: 0, y: 0, proximity: ProximityLevel.medium)],
        edges: [],
        iterations: 1,
        converged: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GraphView3D(
            layout: layout,
            onNodeTapped: (nodeId) => tappedNodeId = nodeId,
          ),
        ),
      );

      final controller = stubPlatform.controller;
      final channelParams = controller.channels
          .firstWhere((ch) => ch.name == 'onNodeTapped');

      // Mensaje no numérico → no debe disparar callback
      tappedNodeId = null;
      channelParams.onMessageReceived(JavaScriptMessage(message: 'not_a_number'));
      expect(tappedNodeId, isNull,
          reason: 'Mensaje no numérico no debe disparar callback');

      // Mensaje vacío → no debe disparar callback
      tappedNodeId = null;
      channelParams.onMessageReceived(JavaScriptMessage(message: ''));
      expect(tappedNodeId, isNull,
          reason: 'Mensaje vacío no debe disparar callback');
    });

    testWidgets('no lanza error si onNodeTapped es null', (
      WidgetTester tester,
    ) async {
      final layout = LayoutResult(
        nodes: [const GraphNode(id: 1, x: 0, y: 0, proximity: ProximityLevel.medium)],
        edges: [],
        iterations: 1,
        converged: true,
      );

      // Sin callback onNodeTapped → no debe lanzar excepción
      await tester.pumpWidget(
        MaterialApp(
          home: GraphView3D(layout: layout), // onNodeTapped = null
        ),
      );

      final controller = stubPlatform.controller;
      final channelParams = controller.channels
          .firstWhere((ch) => ch.name == 'onNodeTapped');

      // Esto no debe lanzar error
      expect(
        () => channelParams.onMessageReceived(JavaScriptMessage(message: '7')),
        returnsNormally,
      );
    });
  });
}
