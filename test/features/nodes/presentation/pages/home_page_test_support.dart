import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/annotations.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:frontend_mobile_nodos_app/core/database/app_database.dart'
    hide User;
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/home_page.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/presentation/bloc/scan_session_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

@GenerateNiceMocks([
  MockSpec<NodeListBloc>(),
  MockSpec<BleBloc>(),
  MockSpec<VisualizationBloc>(),
  MockSpec<BleConnectionBloc>(),
  MockSpec<ScanSessionBloc>(),
  MockSpec<UserBloc>(),
])
import 'home_page_test_support.mocks.dart';
export 'home_page_test_support.mocks.dart';

export 'package:flutter/material.dart';
export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:flutter_test/flutter_test.dart';
export 'package:go_router/go_router.dart';
export 'package:mockito/mockito.dart';
export 'package:plugin_platform_interface/plugin_platform_interface.dart';
export 'package:get_it/get_it.dart';
export 'package:shared_preferences/shared_preferences.dart';
export 'package:frontend_mobile_nodos_app/core/database/app_database.dart'
    hide User;
export 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
export 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
export 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
export 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
export 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
export 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
export 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
export 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/home_page.dart';
export 'package:frontend_mobile_nodos_app/features/scan_session/presentation/bloc/scan_session_bloc.dart';
export 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
export 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view.dart';
export 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

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

Node testNode(int id, String addr) => Node(
  id: id,
  bleAddress: addr,
  name: 'Node $addr',
  firstSeen: DateTime(2026, 1, 1),
  lastSeen: DateTime(2026, 6, 18),
  rssiHistory: const [-50],
  connectable: true,
);

BleScanning bleScanningForNodes(Iterable<Node> nodes) => BleScanning(
  devices: nodes
      .where((node) => node.bleAddress != null)
      .map(
        (node) => BleDevice(
          deviceId: node.bleAddress!,
          rssi: node.rssiHistory.isNotEmpty ? node.rssiHistory.last : -60,
          distance: 2.0,
          proximity: ProximityLevel.close,
          timestamp: DateTime(2026, 1, 1),
        ),
      )
      .toList(),
);

final testLayout = LayoutResult(
  nodes: [
    GraphNode(
      id: 1,
      x: 100,
      y: 100,
      proximity: ProximityLevel.close,
      name: 'Nodo Alpha',
    ),
    GraphNode(
      id: 2,
      x: 300,
      y: 200,
      proximity: ProximityLevel.medium,
      name: 'Nodo Beta',
    ),
    GraphNode(id: 3, x: 500, y: 300, proximity: ProximityLevel.far),
    GraphNode(id: 4, x: 200, y: 500, proximity: ProximityLevel.close),
    GraphNode(id: 5, x: 400, y: 400, proximity: ProximityLevel.medium),
  ],
  edges: [
    GraphEdge(fromId: 1, toId: 2, thickness: 2),
    GraphEdge(fromId: 2, toId: 3, thickness: 1),
    GraphEdge(fromId: 3, toId: 4, thickness: 2),
  ],
  iterations: 100,
  converged: true,
);

MockBleConnectionBloc mockConnBloc() {
  final mock = MockBleConnectionBloc();
  when(mock.state).thenReturn(const BleConnectionInitial());
  when(
    mock.stream,
  ).thenAnswer((_) => Stream.value(const BleConnectionInitial()));
  return mock;
}

MockScanSessionBloc mockSessionBloc() {
  final mock = MockScanSessionBloc();
  when(mock.state).thenReturn(const SessionInitial());
  when(mock.stream).thenAnswer((_) => Stream.value(const SessionInitial()));
  return mock;
}

Widget pumpHomePage({
  required NodeListState nodeListState,
  required VisualizationState visualizationState,
  BleState? bleState,
}) {
  final mockNodeListBloc = MockNodeListBloc();
  final mockBleBloc = MockBleBloc();
  final mockVizBloc = MockVisualizationBloc();
  final mockConnectionBloc = MockBleConnectionBloc();
  final mockUserBloc = MockUserBloc();
  final testUser = User(
    id: 42,
    uuid: 'test-uuid',
    name: 'Usuario',
    color: '#2196F3',
    deviceType: 'android',
    createdAt: DateTime(2026, 1, 1),
    localNodeId: 99,
  );

  when(mockUserBloc.state).thenReturn(UserLoaded(testUser));
  when(
    mockUserBloc.stream,
  ).thenAnswer((_) => Stream.value(UserLoaded(testUser)));
  final mockSessionBloc = MockScanSessionBloc();
  final effectiveBleState =
      bleState ??
      (nodeListState is NodeListLoaded
          ? bleScanningForNodes(nodeListState.nodes)
          : const BleStopped());

  when(mockNodeListBloc.state).thenReturn(nodeListState);
  when(mockNodeListBloc.stream).thenAnswer((_) => Stream.value(nodeListState));
  when(mockBleBloc.state).thenReturn(effectiveBleState);
  when(mockBleBloc.stream).thenAnswer((_) => Stream.value(effectiveBleState));
  when(mockVizBloc.state).thenReturn(visualizationState);
  when(mockVizBloc.stream).thenAnswer((_) => Stream.value(visualizationState));
  when(mockConnectionBloc.state).thenReturn(const BleConnectionInitial());
  when(
    mockConnectionBloc.stream,
  ).thenAnswer((_) => Stream.value(const BleConnectionInitial()));
  when(mockSessionBloc.state).thenReturn(const SessionInitial());
  when(
    mockSessionBloc.stream,
  ).thenAnswer((_) => Stream.value(const SessionInitial()));

  return MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
        BlocProvider<BleBloc>.value(value: mockBleBloc),
        BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
        BlocProvider<BleConnectionBloc>.value(value: mockConnectionBloc),
        BlocProvider<UserBloc>.value(value: mockUserBloc),
        BlocProvider<ScanSessionBloc>.value(value: mockSessionBloc),
      ],
      child: const HomePage(),
    ),
  );
}

Future<AppDatabase> setUpHomePageDependencies() async {
  final testDb = AppDatabase.inMemory();
  if (!GetIt.instance.isRegistered<AppDatabase>()) {
    GetIt.instance.registerSingleton<AppDatabase>(testDb);
  }
  if (!GetIt.instance.isRegistered<SharedPreferences>()) {
    try {
      SharedPreferences.setMockInitialValues({'is3D': false});
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    GetIt.instance.registerSingleton<SharedPreferences>(prefs);
  } else {
    await GetIt.instance<SharedPreferences>().setBool('is3D', false);
  }
  WebViewPlatform.instance = HomePageWebViewPlatformStub();
  return testDb;
}

Future<void> tearDownHomePageDependencies(AppDatabase testDb) async {
  await testDb.close();
  if (GetIt.instance.isRegistered<AppDatabase>()) {
    GetIt.instance.unregister<AppDatabase>();
  }
}
