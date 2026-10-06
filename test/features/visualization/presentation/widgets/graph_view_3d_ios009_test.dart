import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view_3d.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

class _StubWebViewWidget extends PlatformWebViewWidget {
  _StubWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox(key: Key('stub_webview'));
}

class _StubController extends PlatformWebViewController {
  _StubController(super.params) : super.implementation();

  final List<String> executedJs = [];
  final List<JavaScriptChannelParams> channels = [];
  JavaScriptMode? javaScriptMode;
  PageEventCallback? onPageFinished;
  WebResourceErrorCallback? onWebResourceError;

  @override
  Future<void> loadFlutterAsset(String key) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channels.add(params);
  }

  @override
  Future<void> removeJavaScriptChannel(String channelName) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {
    executedJs.add(javaScript);
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {
    javaScriptMode = mode;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    final delegate = handler as _StubNavigationDelegate;
    onPageFinished = delegate.onPageFinished;
    onWebResourceError = delegate.onWebResourceError;
  }

  void pageFinished() => onPageFinished?.call('asset://graph_3d.html');
  void resourceError(WebResourceError error) => onWebResourceError?.call(error);
}

class _StubNavigationDelegate extends PlatformNavigationDelegate {
  _StubNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? onPageFinished;
  WebResourceErrorCallback? onWebResourceError;

  @override
  Future<void> setOnPageFinished(PageEventCallback? callback) async {
    onPageFinished = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    onWebResourceError = callback;
  }
}

class _StubPlatform extends WebViewPlatform with MockPlatformInterfaceMixin {
  _StubController? _controller;
  _StubController get controller => _controller!;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _controller = _StubController(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _StubWebViewWidget(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _StubNavigationDelegate(params);

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => throw UnimplementedError();
}

LayoutResult _layout({String name = 'Node'}) => LayoutResult(
      nodes: [
        GraphNode(
          id: 1,
          x: 0,
          y: 0,
          proximity: ProximityLevel.close,
          name: name,
        ),
      ],
      edges: [],
      iterations: 1,
      converged: true,
    );

void main() {
  late _StubPlatform platform;

  setUp(() {
    platform = _StubPlatform();
    WebViewPlatform.instance = platform;
  });

  test('HTML and Three.js are local and offline-capable', () {
    final html = File('assets/three_graph/graph_3d.html').readAsStringSync();

    expect(html, contains('window.loadGraphData'));
    expect(html, contains('onNodeTapped'));
    expect(html, contains('THREE'));
    expect(html, contains('touch-action:none'));
    expect(RegExp(r'<script[^>]+src=', caseSensitive: false).hasMatch(html), isFalse);
    expect(
      RegExp(r'''<(?:script|link|img)[^>]+(?:src|href)=["']https?://''', caseSensitive: false)
          .hasMatch(html),
      isFalse,
    );
  });

  testWidgets('configura JavaScript y channels antes del documento',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: GraphView3D(layout: _layout())));

    expect(platform.controller.javaScriptMode, JavaScriptMode.unrestricted);
    expect(platform.controller.channels.map((channel) => channel.name),
        containsAll(<String>['onNodeTapped', 'onConsoleLog']));
  });

  testWidgets('serializa UTF-8 y comillas con jsonEncode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GraphView3D(layout: _layout(name: 'Nódulo "principal"'))),
    );
    platform.controller.pageFinished();

    final js = platform.controller.executedJs.single;
    expect(js, contains('Nódulo'));
    expect(js, contains(r'\"principal\"'));
  });

  testWidgets('reload reinyecta snapshot y selección', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GraphView3D(layout: _layout(), selectedNodeId: 1)),
    );
    platform.controller.pageFinished();
    final initialCount = platform.controller.executedJs.length;

    platform.controller.pageFinished();

    expect(platform.controller.executedJs.length, greaterThan(initialCount));
    expect(platform.controller.executedJs.last, contains('"selectedNodeId":1'));
  });

  testWidgets('secondary resource error no destruye la vista', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GraphView3D(layout: _layout())));
    platform.controller.pageFinished();
    platform.controller.resourceError(
      const WebResourceError(
        errorCode: -2,
        description: 'secondary resource failed',
        isForMainFrame: false,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('stub_webview')), findsOneWidget);
    expect(find.textContaining('Error al cargar'), findsNothing);
  });

}
