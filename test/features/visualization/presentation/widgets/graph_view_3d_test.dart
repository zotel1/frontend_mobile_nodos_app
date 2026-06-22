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

  /// Callback que simula onPageFinished desde el stub.
  void Function(String)? onPageFinished;

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

  Future<void> setNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) async {
    // Stub: no-op. El callback onPageFinished se conecta vía
    // createPlatformNavigationDelegate en _StubWebViewPlatform.
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    // Captura el delegate y extrae el callback onPageFinished
    if (handler is _StubNavigationDelegate) {
      onPageFinished = handler.onPageFinished;
    }
  }

  /// Dispara manualmente el callback onPageFinished desde el stub
  /// para simular que el WebView terminó de cargar.
  void simulatePageFinished(String url) {
    onPageFinished?.call(url);
  }
}

/// Stub de PlatformNavigationDelegate para tests de WebView.
///
/// Permite capturar y disparar manualmente callbacks de navegación
/// sin depender de un WebView real.
class _StubNavigationDelegate extends PlatformNavigationDelegate {
  _StubNavigationDelegate(super.params) : super.implementation();

  /// Callback onPageFinished capturado desde los params.
  void Function(String)? onPageFinished;

  @override
  Future<void> setOnPageFinished(PageEventCallback? onPageFinished) async {
    if (onPageFinished != null) {
      this.onPageFinished = onPageFinished;
    }
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
    final delegate = _StubNavigationDelegate(params);
    // Conectar el callback onPageFinished del delegate al controller
    if (_controller != null && delegate.onPageFinished != null) {
      _controller!.onPageFinished = delegate.onPageFinished;
    }
    return delegate;
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    throw UnimplementedError();
  }
}

// ─── Stub que lanza excepción para tests de estado error (T2.3) ──
// QUÉ: simula fallo en carga del WebView lanzando excepción en
// loadFlutterAsset.
// POR QUÉ: necesario para probar R8 — el widget debe mostrar
// "Error al cargar…" cuando el WebView falla.

class _FailingStubWebViewController extends _StubWebViewController {
  _FailingStubWebViewController(super.params);

  @override
  Future<void> loadFlutterAsset(String key) async {
    throw Exception('Simulated asset load failure');
  }
}

class _FailingStubWebViewPlatform extends WebViewPlatform
    with MockPlatformInterfaceMixin {
  _FailingStubWebViewController? _controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    _controller = _FailingStubWebViewController(params);
    return _controller!;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _StubWebViewWidget(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _StubNavigationDelegate(params);
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

      // PR2: Primero muestra estado de carga (R6)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Simular que la página terminó de cargar para salir del estado loading
      final controller = stubPlatform.controller;
      controller.simulatePageFinished('about:blank');
      await tester.pump();

      // Ahora el WebViewWidget debe ser visible
      expect(find.byKey(const Key('stub_webview')), findsOneWidget);

      // Verifica que se solicitó cargar el asset correcto
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

      // PR2: Antes de onPageFinished, los datos NO deben inyectarse.
      // Verifica que runJavaScript NO tiene llamadas a loadGraphData
      // porque _injectData() almacena en _pendingData.
      final controller = stubPlatform.controller;
      final jsCallsBeforePageLoad = controller.executedJs
          .where((js) => js.contains('loadGraphData'))
          .toList();
      expect(jsCallsBeforePageLoad, isEmpty,
          reason: 'No debe inyectar datos antes de onPageFinished');

      // Simula que la página terminó de cargar
      controller.simulatePageFinished('about:blank');

      // Después de onPageFinished, runJavaScript debe tener la inyección
      final jsCalls = controller.executedJs
          .where((js) => js.contains('loadGraphData'))
          .toList();
      expect(jsCalls, isNotEmpty,
          reason: 'Debe inyectar datos después de onPageFinished');
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

  // ═══════════ PR2: onPageFinished + onConsoleLog ═════════════════

  group('PR2: onPageFinished y onConsoleLog', () {
    testWidgets('configura canal onConsoleLog para logs de JS', (
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

      final controller = stubPlatform.controller;
      final consoleChannel = controller.channels
          .where((ch) => ch.name == 'onConsoleLog')
          .toList();
      expect(consoleChannel.length, equals(1),
          reason: 'Debe registrar el canal onConsoleLog para logs de JS');
    });

    testWidgets('onPageFinished dispara la inyección de datos pendientes', (
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

      final controller = stubPlatform.controller;

      // Verifica que los datos se inyectan SOLO después de onPageFinished
      final beforeCalls = controller.executedJs
          .where((js) => js.contains('loadGraphData'))
          .toList();
      expect(beforeCalls, isEmpty,
          reason: 'Sin onPageFinished, _pendingData guarda pero no inyecta');

      // Dispara onPageFinished
      controller.simulatePageFinished('about:blank');

      final afterCalls = controller.executedJs
          .where((js) => js.contains('loadGraphData'))
          .toList();
      expect(afterCalls, isNotEmpty,
          reason: 'Después de onPageFinished debe inyectar los datos');
      expect(afterCalls.first, contains('"nodes"'),
          reason: 'El JSON inyectado debe contener nodos');
    });
  });

  // ═══════════ PR2: Estados loading / empty / error ═══════════════

  group('PR2: estados de carga, vacío y error (R6, R7, R8)', () {
    // ─── T2.1: Estado loading (R6) ──────────────────────────────────
    // QUÉ: al crear el widget, _isLoading = true → debe mostrar
    // CircularProgressIndicator con texto "Cargando…".
    // POR QUÉ: R6 — el usuario debe ver feedback visual mientras
    // el WebView inicializa (pantalla en blanco anterior causaba B2).

    testWidgets('T2.1: muestra CircularProgressIndicator al iniciar carga',
        (WidgetTester tester) async {
      final layout = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1,
            x: 0,
            y: 0,
            proximity: ProximityLevel.medium,
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

      // _isLoading = true en initState → debe mostrar indicador de carga
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'Debe mostrar CircularProgressIndicator mientras carga');
      expect(find.textContaining('Cargando'), findsOneWidget,
          reason: 'Debe mostrar texto "Cargando…" mientras el WebView inicializa');
    });

    // ─── T2.2: Estado vacío (R7) ───────────────────────────────────
    // QUÉ: cuando layout.nodes.isEmpty y la página ya cargó, debe
    // mostrar texto "No hay nodos…".
    // POR QUÉ: R7 — el usuario debe saber que no hay nodos
    // disponibles para visualizar en 3D.

    testWidgets('T2.2: muestra texto vacío cuando nodeCount == 0',
        (WidgetTester tester) async {
      final emptyLayout = LayoutResult(
        nodes: [],
        edges: [],
        iterations: 0,
        converged: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GraphView3D(layout: emptyLayout),
        ),
      );

      // Simula que el WebView terminó de cargar para salir del estado loading
      stubPlatform.controller.simulatePageFinished('about:blank');
      await tester.pump();

      // layout.nodes.isEmpty → debe mostrar texto de vacío
      expect(find.textContaining('No hay nodos'), findsOneWidget,
          reason: 'Debe mostrar mensaje de estado vacío cuando no hay nodos');
    });

    // ─── T2.3: Estado error (R8) ───────────────────────────────────
    // QUÉ: cuando el WebView falla al cargar el asset, debe mostrar
    // texto "Error al cargar…".
    // POR QUÉ: R8 — el usuario debe saber que ocurrió un error sin
    // ver pantalla en blanco ni perder la vista 2D.

    testWidgets('T2.3: muestra error cuando falla la carga del WebView',
        (WidgetTester tester) async {
      // Usa un stub que lanza excepción en loadFlutterAsset
      final errorPlatform = _FailingStubWebViewPlatform();
      WebViewPlatform.instance = errorPlatform;

      final layout = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1,
            x: 0,
            y: 0,
            proximity: ProximityLevel.medium,
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
      // Permitir que _loadContent falle y setState se procese
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // _hasError = true → debe mostrar texto de error (R8)
      expect(find.textContaining('Error al cargar'), findsOneWidget,
          reason: 'Debe mostrar mensaje de error cuando falla la carga del WebView');
    });
  });
}
