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
    testWidgets('shows CircularProgressIndicator when loading', (tester) async {
      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: const NodeListLoading(),
          visualizationState: const VisualizationInitial(),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────────
    // Vista de grafo — umbral removido
    // ─────────────────────────────────────────────────────────────
    //
    // La Home ya no usa el antiguo umbral:
    //   1–4 nodos → lista
    //   5+ nodos  → grafo
    //
    // Cualquier NodeListLoaded con al menos un nodo activa el grafo.

    testWidgets('NodeListLoaded con nodos activa el modo grafo', (
      tester,
    ) async {
      final nodes = [
        testNode(1, 'AA:BB:CC:DD:EE:01'),
        testNode(2, 'AA:BB:CC:DD:EE:02'),
      ];

      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: NodeListLoaded(nodes),
          visualizationState: const VisualizationInitial(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // VisualizationInitial representa un grafo todavía no construido.
      // La Home debe estar en modo grafo y mostrar su estado de carga.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('GraphReady con 1 nodo renderiza GraphView', (tester) async {
      final nodes = [testNode(1, 'AA:BB:CC:DD:EE:01')];

      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: NodeListLoaded(nodes),
          visualizationState: GraphReady(testLayout),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(GraphView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('GraphReady con varios nodos renderiza GraphView', (
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

      expect(find.byType(GraphView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('3 nodos permanecen en modo grafo sin umbral de histéresis', (
      tester,
    ) async {
      final nodes = [
        testNode(1, 'AA:BB:CC:DD:EE:01'),
        testNode(2, 'AA:BB:CC:DD:EE:02'),
        testNode(3, 'AA:BB:CC:DD:EE:03'),
      ];

      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: NodeListLoaded(nodes),
          visualizationState: GraphReady(testLayout),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(GraphView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('shows empty state text when no nodes', (tester) async {
      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: const NodeListEmpty(),
          visualizationState: const VisualizationInitial(),
        ),
      );

      expect(find.text('No se encontraron nodos'), findsOneWidget);
    });

    testWidgets('shows error message when error state', (tester) async {
      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: const NodeListError('Something went wrong'),
          visualizationState: const VisualizationInitial(),
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('shows graph error message when VisualizationBloc fails', (
      tester,
    ) async {
      final nodes = List.generate(
        6,
        (i) => testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );
      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: NodeListLoaded(nodes),
          visualizationState: const GraphError('Error al construir grafo'),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Error al construir grafo'), findsOneWidget);
    });

    testWidgets('AppBar has title Nodos and settings icon', (tester) async {
      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: const NodeListLoaded([]),
          visualizationState: const VisualizationInitial(),
        ),
      );

      expect(find.text('Nodos'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    // T1.8: Auto-scan — StartScan se despacha automáticamente en initState
    // y StopScan en dispose. El FAB fue removido.
    // QUÉ: al construir HomePage, el BLoC de BLE recibe StartScan sin
    // interacción del usuario. Al destruir el widget, recibe StopScan.
    // POR QUÉ: el escaneo debe ser automático en la tab Home, sin
    // necesidad de que el usuario presione un botón cada vez.
    testWidgets('dispatches StartScan automatically on init (auto-scan)', (
      tester,
    ) async {
      final mockBleBloc = MockBleBloc();
      final mockNodeListBloc = MockNodeListBloc();
      final mockVizBloc = MockVisualizationBloc();

      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(
        mockBleBloc.stream,
      ).thenAnswer((_) => Stream.value(const BleStopped()));
      when(mockNodeListBloc.state).thenReturn(const NodeListInitial());
      when(
        mockNodeListBloc.stream,
      ).thenAnswer((_) => Stream.value(const NodeListInitial()));
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(
        mockVizBloc.stream,
      ).thenAnswer((_) => Stream.value(const VisualizationInitial()));

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
              BlocProvider<BleBloc>.value(value: mockBleBloc),
              BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
              BlocProvider<BleConnectionBloc>.value(value: mockConnBloc()),
              BlocProvider<ScanSessionBloc>.value(value: mockSessionBloc()),
            ],
            child: const HomePage(),
          ),
        ),
      );

      // addPostFrameCallback ejecuta StartScan en el primer frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(mockBleBloc.add(const StartScan())).called(1);
    });

    // T1.8: FAB removido — no debe existir FloatingActionButton en la UI.
    testWidgets('FAB is removed from HomePage (auto-scan replaces it)', (
      tester,
    ) async {
      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: const NodeListInitial(),
          visualizationState: const VisualizationInitial(),
        ),
      );

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('shows BluetoothOffBanner when Bluetooth is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: const NodeListLoaded([]),
          visualizationState: const VisualizationInitial(),
          bleState: const BluetoothOff(),
        ),
      );

      // Verify the BluetoothOffBanner text is shown.
      expect(find.textContaining('Bluetooth desactivado'), findsOneWidget);
    });

    testWidgets(
      'BlocListener<BleBloc> dispatches SyncBleDevices on BleScanning',
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
        when(
          mockNodeListBloc.stream,
        ).thenAnswer((_) => Stream.value(const NodeListLoaded([])));
        when(mockBleBloc.state).thenReturn(const BleStopped());
        when(mockBleBloc.stream).thenAnswer(
          (_) => Stream.fromIterable([
            BleScanning(devices: [testDevice]),
          ]),
        );
        when(mockVizBloc.state).thenReturn(const VisualizationInitial());
        when(
          mockVizBloc.stream,
        ).thenAnswer((_) => Stream.value(const VisualizationInitial()));

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
                BlocProvider<BleBloc>.value(value: mockBleBloc),
                BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
                BlocProvider<BleConnectionBloc>.value(value: mockConnBloc()),
                BlocProvider<ScanSessionBloc>.value(value: mockSessionBloc()),
              ],
              child: const HomePage(),
            ),
          ),
        );

        // Esperar que el BlocListener<BleBloc> procese el BleScanning.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verifica que SyncBleDevices fue despachado al NodeListBloc.
        verify(
          mockNodeListBloc.add(
            argThat(
              predicate((e) => e is SyncBleDevices && e.devices.length == 1),
            ),
          ),
        ).called(1);
      },
    );

    testWidgets('settings gear navigates to /settings using GoRouter', (
      tester,
    ) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
      when(
        mockNodeListBloc.stream,
      ).thenAnswer((_) => Stream.value(const NodeListLoaded([])));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(
        mockBleBloc.stream,
      ).thenAnswer((_) => Stream.value(const BleStopped()));
      when(mockVizBloc.state).thenReturn(const VisualizationInitial());
      when(
        mockVizBloc.stream,
      ).thenAnswer((_) => Stream.value(const VisualizationInitial()));

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
                BlocProvider<BleConnectionBloc>.value(value: mockConnBloc()),
                BlocProvider<ScanSessionBloc>.value(value: mockSessionBloc()),
              ],
              child: const HomePage(),
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('Settings Page'))),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));

      // El icono de settings debe estar presente.
      expect(find.byIcon(Icons.settings), findsOneWidget);

      // Tocar el engranaje y verificar que navega a /settings.
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // La página de settings debe mostrarse.
      expect(find.text('Settings Page'), findsOneWidget);
    });

    testWidgets(
      'muestra BluetoothOffDialog cuando BleBloc emite BluetoothOff',
      (tester) async {
        final bleController = StreamController<BleState>.broadcast();
        final mockNodeListBloc = MockNodeListBloc();
        final mockBleBloc = MockBleBloc();
        final mockVizBloc = MockVisualizationBloc();

        when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
        when(
          mockNodeListBloc.stream,
        ).thenAnswer((_) => Stream.value(const NodeListLoaded([])));
        when(mockBleBloc.state).thenReturn(const BleStopped());
        when(mockBleBloc.stream).thenAnswer((_) => bleController.stream);
        when(mockVizBloc.state).thenReturn(const VisualizationInitial());
        when(
          mockVizBloc.stream,
        ).thenAnswer((_) => Stream.value(const VisualizationInitial()));

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
                BlocProvider<BleBloc>.value(value: mockBleBloc),
                BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
                BlocProvider<BleConnectionBloc>.value(value: mockConnBloc()),
                BlocProvider<ScanSessionBloc>.value(value: mockSessionBloc()),
              ],
              child: const HomePage(),
            ),
          ),
        );

        // Emitir BluetoothOff desde el stream del BleBloc.
        bleController.add(const BluetoothOff());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verificar que el AlertDialog de BluetoothOffDialog aparece.
        expect(find.text('Bluetooth requerido'), findsOneWidget);
        expect(find.text('Ir a Configuración'), findsOneWidget);

        bleController.close();
      },
    );

    testWidgets(
      'no muestra segundo dialogo si BleBloc emite BluetoothOff dos veces',
      (tester) async {
        final bleController = StreamController<BleState>.broadcast();
        final mockNodeListBloc = MockNodeListBloc();
        final mockBleBloc = MockBleBloc();
        final mockVizBloc = MockVisualizationBloc();

        when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
        when(
          mockNodeListBloc.stream,
        ).thenAnswer((_) => Stream.value(const NodeListLoaded([])));
        when(mockBleBloc.state).thenReturn(const BleStopped());
        when(mockBleBloc.stream).thenAnswer((_) => bleController.stream);
        when(mockVizBloc.state).thenReturn(const VisualizationInitial());
        when(
          mockVizBloc.stream,
        ).thenAnswer((_) => Stream.value(const VisualizationInitial()));

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
                BlocProvider<BleBloc>.value(value: mockBleBloc),
                BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
                BlocProvider<BleConnectionBloc>.value(value: mockConnBloc()),
                BlocProvider<ScanSessionBloc>.value(value: mockSessionBloc()),
              ],
              child: const HomePage(),
            ),
          ),
        );

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
      },
    );

    testWidgets(
      'BluetoothOffDialog onGoToSettings y onCancel resetean el guard',
      (tester) async {
        final bleController = StreamController<BleState>.broadcast();
        final mockNodeListBloc = MockNodeListBloc();
        final mockBleBloc = MockBleBloc();
        final mockVizBloc = MockVisualizationBloc();

        when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
        when(
          mockNodeListBloc.stream,
        ).thenAnswer((_) => Stream.value(const NodeListLoaded([])));
        when(mockBleBloc.state).thenReturn(const BleStopped());
        when(mockBleBloc.stream).thenAnswer((_) => bleController.stream);
        when(mockVizBloc.state).thenReturn(const VisualizationInitial());
        when(
          mockVizBloc.stream,
        ).thenAnswer((_) => Stream.value(const VisualizationInitial()));

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
                BlocProvider<BleBloc>.value(value: mockBleBloc),
                BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
                BlocProvider<BleConnectionBloc>.value(value: mockConnBloc()),
                BlocProvider<ScanSessionBloc>.value(value: mockSessionBloc()),
              ],
              child: const HomePage(),
            ),
          ),
        );

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
      },
    );
  });
}
