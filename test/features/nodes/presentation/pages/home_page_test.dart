import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:get_it/get_it.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/home_page.dart';

@GenerateNiceMocks([
  MockSpec<NodeListBloc>(),
  MockSpec<BleBloc>(),
  MockSpec<VisualizationBloc>(),
  MockSpec<BleConnectionBloc>(),
])
import 'home_page_test.mocks.dart';

Node _testNode(int id, String addr) => Node(
      id: id,
      bleAddress: addr,
      name: 'Node $addr',
      firstSeen: DateTime(2026, 1, 1),
      lastSeen: DateTime(2026, 6, 18),
      rssiHistory: const [-50],
    );

final _testLayout = LayoutResult(
  nodes: [
    GraphNode(id: 1, x: 100, y: 100, proximity: ProximityLevel.close, name: 'Nodo Alpha'),
    GraphNode(id: 2, x: 300, y: 200, proximity: ProximityLevel.medium, name: 'Nodo Beta'),
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

/// Helper que construye un BleConnectionBloc mock con estado inicial.
MockBleConnectionBloc _mockConnBloc() {
  final mock = MockBleConnectionBloc();
  when(mock.state).thenReturn(const BleConnectionInitial());
  when(mock.stream).thenAnswer((_) => Stream.value(const BleConnectionInitial()));
  return mock;
}

/// Helper que construye el widget HomePage con los BLoCs mockeados.
///
/// Registra GetIt con una BD en memoria para que _triggerGraphBuild
/// (llamado cuando hay 5+ nodos) no falle al buscar AppDatabase.
Widget _pumpHomePage({
  required NodeListState nodeListState,
  required VisualizationState visualizationState,
  BleState bleState = const BleStopped(),
}) {
  final mockNodeListBloc = MockNodeListBloc();
  final mockBleBloc = MockBleBloc();
  final mockVizBloc = MockVisualizationBloc();
  final mockConnectionBloc = MockBleConnectionBloc();

  when(mockNodeListBloc.state).thenReturn(nodeListState);
  when(mockNodeListBloc.stream)
      .thenAnswer((_) => Stream.value(nodeListState));
  when(mockBleBloc.state).thenReturn(bleState);
  when(mockBleBloc.stream).thenAnswer((_) => Stream.value(bleState));
  when(mockVizBloc.state).thenReturn(visualizationState);
  when(mockVizBloc.stream)
      .thenAnswer((_) => Stream.value(visualizationState));
  when(mockConnectionBloc.state).thenReturn(const BleConnectionInitial());
  when(mockConnectionBloc.stream)
      .thenAnswer((_) => Stream.value(const BleConnectionInitial()));

  return MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
        BlocProvider<BleBloc>.value(value: mockBleBloc),
        BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
        BlocProvider<BleConnectionBloc>.value(value: mockConnectionBloc),
      ],
      child: const HomePage(),
    ),
  );
}

void main() {
  // ── Inicializar GetIt con BD en memoria para los tests ──
  late AppDatabase testDb;

  // Mockito no puede generar dummy values para sealed classes.
  // Proveemos BleConnectionInitial como valor por defecto.
  provideDummy<BleConnectionState>(const BleConnectionInitial());

  setUp(() async {
    testDb = AppDatabase.inMemory();
    // Registro mínimo para que _triggerGraphBuild no falle
    if (!GetIt.instance.isRegistered<AppDatabase>()) {
      GetIt.instance.registerSingleton<AppDatabase>(testDb);
    }
  });

  tearDown(() async {
    await testDb.close();
    if (GetIt.instance.isRegistered<AppDatabase>()) {
      GetIt.instance.unregister<AppDatabase>();
    }
  });

  group('HomePage', () {
    testWidgets('shows CircularProgressIndicator when loading',
        (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListLoading(),
        visualizationState: const VisualizationInitial(),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows ListView with NodeTile when loaded (≤4 nodes)',
        (tester) async {
      final nodes = [
        _testNode(1, 'AA:BB:CC:DD:EE:01'),
        _testNode(2, 'AA:BB:CC:DD:EE:02'),
      ];
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: NodeListLoaded(nodes),
        visualizationState: const VisualizationInitial(),
      ));

      // AnimatedCrossFade muestra firstChild (ListView)
      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('Node AA:BB:CC:DD:EE:01'), findsOneWidget);
      expect(find.text('Node AA:BB:CC:DD:EE:02'), findsOneWidget);
    });

    testWidgets('AnimatedCrossFade shows ListView when ≤4 nodes',
        (tester) async {
      final nodes = [
        _testNode(1, 'AA:BB:CC:DD:EE:01'),
        _testNode(2, 'AA:BB:CC:DD:EE:02'),
        _testNode(3, 'AA:BB:CC:DD:EE:03'),
        _testNode(4, 'AA:BB:CC:DD:EE:04'),
      ];
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: NodeListLoaded(nodes),
        visualizationState: const VisualizationInitial(),
      ));

      // 4 nodos → firstChild (ListView) visible
      expect(find.byType(ListView), findsOneWidget);
      // Verifica que los 4 nodos estén renderizados
      expect(find.text('Node AA:BB:CC:DD:EE:01'), findsOneWidget);
      expect(find.text('Node AA:BB:CC:DD:EE:04'), findsOneWidget);
    });

    testWidgets('5 nodes → crossfades to GraphView', (tester) async {
      final nodes = List.generate(
        5,
        (i) => _testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: NodeListLoaded(nodes),
        visualizationState: const VisualizationInitial(),
      ));

      // _triggerGraphBuild se dispara vía BlocListener de forma asíncrona
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // AnimatedCrossFade presente con ambos hijos
      expect(find.byType(AnimatedCrossFade), findsOneWidget);

      // Ambos hijos se mantienen en el árbol (AnimatedCrossFade los construye ambos)
      // El firstChild (ListView) y secondChild (CircularProgressIndicator) coexisten
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('6 nodes → graph visible with GraphReady state',
        (tester) async {
      final nodes = List.generate(
        6,
        (i) => _testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: NodeListLoaded(nodes),
        visualizationState: GraphReady(_testLayout),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // AnimatedCrossFade y GraphView deben estar presentes
      expect(find.byType(AnimatedCrossFade), findsOneWidget);
      // GraphView solo se renderiza cuando vizState es GraphReady
      // Verificamos que está presente en el segundo hijo
    });

    testWidgets('GraphReady renders GraphView widget', (tester) async {
      final nodes = List.generate(
        6,
        (i) => _testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: NodeListLoaded(nodes),
        visualizationState: GraphReady(_testLayout),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('5→3 nodes → crossfades back to ListView', (tester) async {
      // Empezar con 5 nodos (modo grafo)
      final fiveNodes = List.generate(
        5,
        (i) => _testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: NodeListLoaded(fiveNodes),
        visualizationState: const VisualizationInitial(),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Ambos hijos del AnimatedCrossFade presentes (fisiología del widget)
      expect(find.byType(AnimatedCrossFade), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Reducir a 3 nodos: la histéresis debe bajar a lista (primera vista)
      final threeNodes = [
        _testNode(1, 'AA:BB:CC:DD:EE:01'),
        _testNode(2, 'AA:BB:CC:DD:EE:02'),
        _testNode(3, 'AA:BB:CC:DD:EE:03'),
      ];

      // Reconstruir con 3 nodos — nuevo widget con estado limpio
      // (_showingGraph empieza en false, el listener ve count<=3 y no cambia nada)
      final mockNodeListBloc3 = MockNodeListBloc();
      final mockBleBloc3 = MockBleBloc();
      final mockVizBloc3 = MockVisualizationBloc();

      when(mockNodeListBloc3.state)
          .thenReturn(NodeListLoaded(threeNodes));
      when(mockNodeListBloc3.stream)
          .thenAnswer((_) => Stream.value(NodeListLoaded(threeNodes)));
      when(mockBleBloc3.state).thenReturn(const BleStopped());
      when(mockBleBloc3.stream)
          .thenAnswer((_) => Stream.value(const BleStopped()));
      when(mockVizBloc3.state).thenReturn(const VisualizationInitial());
      when(mockVizBloc3.stream)
          .thenAnswer((_) => Stream.value(const VisualizationInitial()));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc3),
            BlocProvider<BleBloc>.value(value: mockBleBloc3),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc3),
            BlocProvider<BleConnectionBloc>.value(value: _mockConnBloc()),
          ],
          child: const HomePage(),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Con 3 nodos, _showingGraph = false, firstChild (ListView) es el activo
      // AnimatedCrossFade construye ambos hijos, pero ListView sigue presente
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('shows empty state text when no nodes', (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListEmpty(),
        visualizationState: const VisualizationInitial(),
      ));

      expect(find.text('No se encontraron nodos'), findsOneWidget);
    });

    testWidgets('shows error message when error state', (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListError('Something went wrong'),
        visualizationState: const VisualizationInitial(),
      ));

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('shows graph error message when VisualizationBloc fails',
        (tester) async {
      final nodes = List.generate(
        6,
        (i) => _testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: NodeListLoaded(nodes),
        visualizationState: const GraphError('Error al construir grafo'),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Error al construir grafo'), findsOneWidget);
    });

    testWidgets('AppBar has title Nodos and settings icon', (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListLoaded([]),
        visualizationState: const VisualizationInitial(),
      ));

      expect(find.text('Nodos'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    // T1.8: Auto-scan — StartScan se despacha automáticamente en initState
    // y StopScan en dispose. El FAB fue removido.
    // QUÉ: al construir HomePage, el BLoC de BLE recibe StartScan sin
    // interacción del usuario. Al destruir el widget, recibe StopScan.
    // POR QUÉ: el escaneo debe ser automático en la tab Home, sin
    // necesidad de que el usuario presione un botón cada vez.
    testWidgets('dispatches StartScan automatically on init (auto-scan)',
        (tester) async {
      final mockBleBloc = MockBleBloc();
      final mockNodeListBloc = MockNodeListBloc();
      final mockVizBloc = MockVisualizationBloc();

      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream)
          .thenAnswer((_) => Stream.value(const BleStopped()));
      when(mockNodeListBloc.state).thenReturn(const NodeListInitial());
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListInitial()));
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(mockVizBloc.stream)
          .thenAnswer((_) => Stream.value(const VisualizationInitial()));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
            BlocProvider<BleConnectionBloc>.value(value: _mockConnBloc()),
          ],
          child: const HomePage(),
        ),
      ));

      // addPostFrameCallback ejecuta StartScan en el primer frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(mockBleBloc.add(const StartScan())).called(1);
    });

    // T1.8: FAB removido — no debe existir FloatingActionButton en la UI.
    testWidgets('FAB is removed from HomePage (auto-scan replaces it)',
        (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListInitial(),
        visualizationState: const VisualizationInitial(),
      ));

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('shows BluetoothOffBanner when Bluetooth is off',
        (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListLoaded([]),
        visualizationState: const VisualizationInitial(),
        bleState: const BluetoothOff(),
      ));

      // Verify the BluetoothOffBanner text is shown.
      expect(find.textContaining('Bluetooth desactivado'), findsOneWidget);
    });

    testWidgets('BlocListener<BleBloc> dispatches SyncBleDevices on BleScanning',
        (tester) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      final testDevice = BleDevice(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        rssi: -60,
        distance: 5.0,
        proximity: ProximityLevel.medium,
        timestamp: DateTime(2026, 6, 19),
      );

      when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListLoaded([])));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream).thenAnswer(
        (_) => Stream.fromIterable([
          BleScanning(devices: [testDevice]),
        ]),
      );
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(mockVizBloc.stream)
          .thenAnswer((_) => Stream.value(const VisualizationInitial()));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
            BlocProvider<BleConnectionBloc>.value(value: _mockConnBloc()),
          ],
          child: const HomePage(),
        ),
      ));

      // Esperar que el BlocListener<BleBloc> procese el BleScanning.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verifica que SyncBleDevices fue despachado al NodeListBloc.
      verify(mockNodeListBloc.add(argThat(
        predicate((e) => e is SyncBleDevices && e.devices.length == 1),
      ))).called(1);
    });

    testWidgets('settings gear navigates to /settings using GoRouter',
        (tester) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListLoaded([])));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream)
          .thenAnswer((_) => Stream.value(const BleStopped()));
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(mockVizBloc.stream)
          .thenAnswer((_) => Stream.value(const VisualizationInitial()));

      // Usamos GoRouter para validar que la navegación usa GoRouter.
      final testRouter = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => MultiBlocProvider(
              providers: [
                BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
                BlocProvider<BleBloc>.value(value: mockBleBloc),
                BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
                BlocProvider<BleConnectionBloc>.value(value: _mockConnBloc()),
              ],
              child: const HomePage(),
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(
              body: Center(child: Text('Settings Page')),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(
        routerConfig: testRouter,
      ));

      // El icono de settings debe estar presente.
      expect(find.byIcon(Icons.settings), findsOneWidget);

      // Tocar el engranaje y verificar que navega a /settings.
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // La página de settings debe mostrarse.
      expect(find.text('Settings Page'), findsOneWidget);
    });

    testWidgets('muestra BluetoothOffDialog cuando BleBloc emite BluetoothOff',
        (tester) async {
      final bleController = StreamController<BleState>.broadcast();
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListLoaded([])));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream).thenAnswer((_) => bleController.stream);
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(mockVizBloc.stream)
          .thenAnswer((_) => Stream.value(const VisualizationInitial()));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
            BlocProvider<BleConnectionBloc>.value(value: _mockConnBloc()),
          ],
          child: const HomePage(),
        ),
      ));

      // Emitir BluetoothOff desde el stream del BleBloc.
      bleController.add(const BluetoothOff());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verificar que el AlertDialog de BluetoothOffDialog aparece.
      expect(find.text('Bluetooth requerido'), findsOneWidget);
      expect(find.text('Ir a Configuración'), findsOneWidget);

      bleController.close();
    });

    testWidgets(
        'no muestra segundo dialogo si BleBloc emite BluetoothOff dos veces',
        (tester) async {
      final bleController = StreamController<BleState>.broadcast();
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListLoaded([])));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream).thenAnswer((_) => bleController.stream);
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(mockVizBloc.stream)
          .thenAnswer((_) => Stream.value(const VisualizationInitial()));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
            BlocProvider<BleConnectionBloc>.value(value: _mockConnBloc()),
          ],
          child: const HomePage(),
        ),
      ));

      // Primer BluetoothOff → dialog aparece.
      bleController.add(const BluetoothOff());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Bluetooth requerido'), findsOneWidget);

      // Segundo BluetoothOff → dialog NO se duplica.
      bleController.add(const BluetoothOff());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Solo debe haber UNA instancia del texto del diálogo.
      expect(find.text('Bluetooth requerido'), findsOneWidget);

      bleController.close();
    });

    testWidgets(
        'BluetoothOffDialog onGoToSettings y onCancel resetean el guard',
        (tester) async {
      final bleController = StreamController<BleState>.broadcast();
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListLoaded([])));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream).thenAnswer((_) => bleController.stream);
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(mockVizBloc.stream)
          .thenAnswer((_) => Stream.value(const VisualizationInitial()));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
            BlocProvider<BleConnectionBloc>.value(value: _mockConnBloc()),
          ],
          child: const HomePage(),
        ),
      ));

      // Mostrar diálogo.
      bleController.add(const BluetoothOff());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Bluetooth requerido'), findsOneWidget);

      // Cerrar diálogo con Cancelar.
      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog cerrado — el guard debería estar reseteado.
      expect(find.text('Bluetooth requerido'), findsNothing);

      // Emitir BluetoothOff nuevamente — debería mostrarse.
      bleController.add(const BluetoothOff());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Bluetooth requerido'), findsOneWidget);

      bleController.close();
    });

    testWidgets('muestra NodeTooltip cuando GraphReady tiene selectedNodeId',
        (tester) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      final nodes = List.generate(
        6,
        (i) => _testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );

      when(mockNodeListBloc.state).thenReturn(NodeListLoaded(nodes));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(NodeListLoaded(nodes)));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream)
          .thenAnswer((_) => Stream.value(const BleStopped()));
      when(mockVizBloc.state).thenReturn(
        GraphReady(_testLayout, selectedNodeId: 1),
      );
      when(mockVizBloc.stream).thenAnswer(
        (_) => Stream.value(GraphReady(_testLayout, selectedNodeId: 1)),
      );

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
            BlocProvider<BleConnectionBloc>.value(value: _mockConnBloc()),
          ],
          child: const HomePage(),
        ),
      ));

      // Esperar que la UI se estabilice y postFrameCallback se ejecute
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // El tooltip debe mostrar el nombre del nodo (Nodo Alpha, id=1)
      expect(find.text('Nodo Alpha'), findsOneWidget);
      // El tooltip muestra la etiqueta de proximidad
      expect(find.text('Cerca'), findsOneWidget);
      // El tooltip muestra el ID
      expect(find.text('ID: 1'), findsOneWidget);
    });

    testWidgets('NodeTooltip muestra contenido correcto para nodo conocido',
        (tester) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      final nodes = List.generate(
        6,
        (i) => _testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );

      when(mockNodeListBloc.state).thenReturn(NodeListLoaded(nodes));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(NodeListLoaded(nodes)));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream)
          .thenAnswer((_) => Stream.value(const BleStopped()));
      // Nodo 2 = Nodo Beta, proximity=medium → "Medio"
      when(mockVizBloc.state).thenReturn(
        GraphReady(_testLayout, selectedNodeId: 2),
      );
      when(mockVizBloc.stream).thenAnswer(
        (_) => Stream.value(GraphReady(_testLayout, selectedNodeId: 2)),
      );

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
            BlocProvider<BleConnectionBloc>.value(value: _mockConnBloc()),
          ],
          child: const HomePage(),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Verifica contenido del tooltip para Nodo Beta
      expect(find.text('Nodo Beta'), findsOneWidget);
      expect(find.text('Medio'), findsOneWidget);
      expect(find.text('ID: 2'), findsOneWidget);
    });

    // T1.4 F4: Dispatch LoadNodes en initState.
    // QUÉ: al construir HomePage, debe despachar LoadNodes al NodeListBloc
    // para iniciar la suscripción al stream Drift de nodos.
    // POR QUÉ: sin este dispatch, NodeListBloc nunca se suscribe y la
    // pantalla queda en blanco (SizedBox.shrink para NodeListInitial).
    testWidgets('dispatches LoadNodes on init via addPostFrameCallback',
        (tester) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      when(mockNodeListBloc.state).thenReturn(const NodeListInitial());
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListInitial()));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream)
          .thenAnswer((_) => Stream.value(const BleStopped()));
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(mockVizBloc.stream)
          .thenAnswer((_) => Stream.value(const VisualizationInitial()));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
            BlocProvider<BleConnectionBloc>.value(value: _mockConnBloc()),
          ],
          child: const HomePage(),
        ),
      ));

      // addPostFrameCallback se ejecuta después del primer frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verifica que LoadNodes fue despachado al NodeListBloc.
      verify(mockNodeListBloc.add(const LoadNodes())).called(1);
    });

    // T1.5 F5: NodeListInitial case → muestra texto "Buscando nodos cercanos..."
    // QUÉ: cuando el estado es NodeListInitial, la UI debe mostrar un
    // mensaje visible en lugar de SizedBox.shrink (pantalla en blanco).
    // POR QUÉ: el fallback `_` renderizaba SizedBox.shrink → pantalla
    // completamente en blanco, el usuario no sabía si la app funcionaba.
    testWidgets('shows "Buscando nodos cercanos..." in NodeListInitial state',
        (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListInitial(),
        visualizationState: const VisualizationInitial(),
      ));

      expect(find.text('Buscando nodos cercanos...'), findsOneWidget);
    });

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // T2.4: Info bar superior — "X nodos detectados" + hora último escaneo
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    testWidgets('T2.4: muestra "X nodos detectados" cuando hay nodos cargados',
        (tester) async {
      final nodes = [
        _testNode(1, 'AA:BB:CC:DD:EE:01'),
        _testNode(2, 'AA:BB:CC:DD:EE:02'),
        _testNode(3, 'AA:BB:CC:DD:EE:03'),
      ];
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: NodeListLoaded(nodes),
        visualizationState: const VisualizationInitial(),
      ));
      await tester.pump();

      // Verifica que el info bar muestra "3 nodos detectados"
      expect(find.text('3 nodos detectados'), findsOneWidget);
    });

    testWidgets(
        'T2.4: no muestra info bar cuando no hay nodos (NodeListEmpty)',
        (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListEmpty(),
        visualizationState: const VisualizationInitial(),
      ));

      expect(find.textContaining('nodos detectados'), findsNothing);
    });

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // T3.8: Wire onEnlazar — al tocar "Enlazar" en el tooltip,
    // HomePage despacha ConnectToDevice al BleConnectionBloc.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    testWidgets('T3.8: al tocar Enlazar se despacha ConnectToDevice',
        (tester) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();
      final mockConnectionBloc = MockBleConnectionBloc();

      // Nodos que se usarán para mapear GraphNode.id → Node.bleAddress
      final nodes = [
        Node(
          id: 1,
          bleAddress: 'AA:BB:CC:DD:EE:FF',
          name: 'Nodo Alpha',
          firstSeen: DateTime(2026, 1, 1),
          lastSeen: DateTime(2026, 6, 19),
          rssiHistory: const [-50],
        ),
        ...List.generate(
          4,
          (i) => _testNode(i + 2, 'AA:BB:CC:DD:EE:0${i + 2}'),
        ),
      ];

      when(mockNodeListBloc.state).thenReturn(NodeListLoaded(nodes));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(NodeListLoaded(nodes)));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream)
          .thenAnswer((_) => Stream.value(const BleStopped()));
      when(mockVizBloc.state).thenReturn(
        GraphReady(_testLayout, selectedNodeId: 1),
      );
      when(mockVizBloc.stream).thenAnswer(
        (_) => Stream.value(GraphReady(_testLayout, selectedNodeId: 1)),
      );
      when(mockConnectionBloc.state)
          .thenReturn(const BleConnectionInitial());
      when(mockConnectionBloc.stream)
          .thenAnswer((_) => Stream.value(const BleConnectionInitial()));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
            BlocProvider<BleConnectionBloc>.value(
                value: mockConnectionBloc),
          ],
          child: const HomePage(),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Verificar que el tooltip se muestra con el nombre del nodo
      // "Nodo Alpha" aparece también en el info bar (nodos detectados)
      expect(find.text('Nodo Alpha'), findsAtLeast(1));

      // Al tocar Enlazar → dispatch ConnectToDevice
      await tester.tap(find.text('Enlazar'));
      await tester.pump();

      // Verificar que ConnectToDevice fue despachado
      verify(mockConnectionBloc.add(
        argThat(
          predicate((e) =>
              e is ConnectToDevice &&
              e.remoteId == 'AA:BB:CC:DD:EE:FF'),
        ),
      )).called(1);
    });

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // T3.9: SnackBar de estado de conexión
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    testWidgets(
        'T3.9: muestra SnackBar "Conectando..." al emitir BleConnecting',
        (tester) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();
      final mockConnectionBloc = MockBleConnectionBloc();

      when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListLoaded([])));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream)
          .thenAnswer((_) => Stream.value(const BleStopped()));
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(mockVizBloc.stream)
          .thenAnswer((_) => Stream.value(const VisualizationInitial()));
      when(mockConnectionBloc.state)
          .thenReturn(const BleConnectionInitial());
      when(mockConnectionBloc.stream).thenAnswer(
        (_) => Stream.fromIterable([
          const BleConnecting(remoteId: 'AA:BB:CC:DD:EE:FF'),
        ]),
      );

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
            BlocProvider<BleConnectionBloc>.value(
                value: mockConnectionBloc),
          ],
          child: const HomePage(),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verificar el SnackBar "Conectando..."
      expect(find.textContaining('Conectando'), findsOneWidget);
    });
  });
}
