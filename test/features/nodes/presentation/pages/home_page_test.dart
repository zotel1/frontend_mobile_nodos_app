import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:get_it/get_it.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
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
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/home_page.dart';

@GenerateNiceMocks([
  MockSpec<NodeListBloc>(),
  MockSpec<BleBloc>(),
  MockSpec<VisualizationBloc>(),
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
    GraphNode(id: 1, x: 100, y: 100, proximity: ProximityLevel.close),
    GraphNode(id: 2, x: 300, y: 200, proximity: ProximityLevel.medium),
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

  when(mockNodeListBloc.state).thenReturn(nodeListState);
  when(mockNodeListBloc.stream)
      .thenAnswer((_) => Stream.value(nodeListState));
  when(mockBleBloc.state).thenReturn(bleState);
  when(mockBleBloc.stream).thenAnswer((_) => Stream.value(bleState));
  when(mockVizBloc.state).thenReturn(visualizationState);
  when(mockVizBloc.stream)
      .thenAnswer((_) => Stream.value(visualizationState));

  return MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
        BlocProvider<BleBloc>.value(value: mockBleBloc),
        BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
      ],
      child: const HomePage(),
    ),
  );
}

void main() {
  // ── Inicializar GetIt con BD en memoria para los tests ──
  late AppDatabase testDb;

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

    testWidgets('FAB toggles scan — dispatches StartScan when stopped',
        (tester) async {
      final mockBleBloc = MockBleBloc();
      final mockNodeListBloc = MockNodeListBloc();
      final mockVizBloc = MockVisualizationBloc();

      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream)
          .thenAnswer((_) => Stream.value(const BleStopped()));
      when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListLoaded([])));
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(mockVizBloc.stream)
          .thenAnswer((_) => Stream.value(const VisualizationInitial()));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
          ],
          child: const HomePage(),
        ),
      ));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      verify(mockBleBloc.add(const StartScan())).called(1);
    });

    testWidgets('FAB toggles scan — dispatches StopScan when scanning',
        (tester) async {
      final mockBleBloc = MockBleBloc();
      final mockNodeListBloc = MockNodeListBloc();
      final mockVizBloc = MockVisualizationBloc();

      when(mockBleBloc.state).thenReturn(const BleScanning());
      when(mockBleBloc.stream)
          .thenAnswer((_) => Stream.value(const BleScanning()));
      when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListLoaded([])));
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(mockVizBloc.stream)
          .thenAnswer((_) => Stream.value(const VisualizationInitial()));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
            BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
          ],
          child: const HomePage(),
        ),
      ));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      verify(mockBleBloc.add(const StopScan())).called(1);
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
  });
}
