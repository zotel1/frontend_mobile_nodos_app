import 'package:flutter/material.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Minimal WebView platform used by HomePage widget tests.
///
/// It implements the callbacks currently configured by GraphView3D without
/// requiring a native WebView platform during flutter_test execution.
class HomePageWebViewWidgetStub extends PlatformWebViewWidget {
  HomePageWebViewWidgetStub(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: Key('home_page_stub_webview'));
}

class HomePageWebViewControllerStub extends PlatformWebViewController {
  HomePageWebViewControllerStub(super.params) : super.implementation();

  @override
  Future<void> loadFlutterAsset(String key) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    covariant PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {}

  @override
  Future<void> clearCache() async {}
}

class HomePageNavigationDelegateStub extends PlatformNavigationDelegate {
  HomePageNavigationDelegateStub(super.params) : super.implementation();

  @override
  Future<void> setOnPageFinished(PageEventCallback? onPageFinished) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}
}

class HomePageWebViewPlatformStub extends WebViewPlatform
    with MockPlatformInterfaceMixin {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => HomePageWebViewControllerStub(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => HomePageWebViewWidgetStub(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => HomePageNavigationDelegateStub(params);

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => throw UnimplementedError();
}
