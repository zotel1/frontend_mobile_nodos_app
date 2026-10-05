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
    testWidgets('muestra NodeTooltip cuando GraphReady tiene selectedNodeId', (
      tester,
    ) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      final nodes = List.generate(
        6,
        (i) => testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );

      when(mockNodeListBloc.state).thenReturn(NodeListLoaded(nodes));
      when(
        mockNodeListBloc.stream,
      ).thenAnswer((_) => Stream.value(NodeListLoaded(nodes)));
      when(mockBleBloc.state).thenReturn(bleScanningForNodes(nodes));
      when(
        mockBleBloc.stream,
      ).thenAnswer((_) => Stream.value(bleScanningForNodes(nodes)));
      when(
        mockVizBloc.state,
      ).thenReturn(GraphReady(testLayout, selectedNodeId: 1));
      when(mockVizBloc.stream).thenAnswer(
        (_) => Stream.value(GraphReady(testLayout, selectedNodeId: 1)),
      );

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

    testWidgets('NodeTooltip muestra contenido correcto para nodo conocido', (
      tester,
    ) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      final nodes = List.generate(
        6,
        (i) => testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
      );

      when(mockNodeListBloc.state).thenReturn(NodeListLoaded(nodes));
      when(
        mockNodeListBloc.stream,
      ).thenAnswer((_) => Stream.value(NodeListLoaded(nodes)));
      when(mockBleBloc.state).thenReturn(bleScanningForNodes(nodes));
      when(
        mockBleBloc.stream,
      ).thenAnswer((_) => Stream.value(bleScanningForNodes(nodes)));
      // Nodo 2 = Nodo Beta, proximity=medium → "Medio"
      when(
        mockVizBloc.state,
      ).thenReturn(GraphReady(testLayout, selectedNodeId: 2));
      when(mockVizBloc.stream).thenAnswer(
        (_) => Stream.value(GraphReady(testLayout, selectedNodeId: 2)),
      );

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
    testWidgets('dispatches LoadNodes on init via addPostFrameCallback', (
      tester,
    ) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockBleBloc = MockBleBloc();
      final mockVizBloc = MockVisualizationBloc();

      when(mockNodeListBloc.state).thenReturn(const NodeListInitial());
      when(
        mockNodeListBloc.stream,
      ).thenAnswer((_) => Stream.value(const NodeListInitial()));
      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(
        mockBleBloc.stream,
      ).thenAnswer((_) => Stream.value(const BleStopped()));
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
    testWidgets('shows "Buscando nodos cercanos..." in NodeListInitial state', (
      tester,
    ) async {
      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: const NodeListInitial(),
          visualizationState: const VisualizationInitial(),
        ),
      );

      expect(find.text('Buscando nodos cercanos...'), findsOneWidget);
    });

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // T2.4: Info bar superior — "X nodos detectados" + hora último escaneo
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    testWidgets(
      'T2.4: muestra "X nodos detectados" cuando hay nodos cargados',
      (tester) async {
        final nodes = [
          testNode(1, 'AA:BB:CC:DD:EE:01'),
          testNode(2, 'AA:BB:CC:DD:EE:02'),
          testNode(3, 'AA:BB:CC:DD:EE:03'),
        ];
        await tester.pumpWidget(
          pumpHomePage(
            nodeListState: NodeListLoaded(nodes),
            visualizationState: const VisualizationInitial(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verifica que el info bar muestra "3 nodos detectados"
        expect(find.textContaining('3 nodos detectados'), findsOneWidget);
      },
    );

    testWidgets(
      'T2.4: no muestra info bar cuando no hay nodos (NodeListEmpty)',
      (tester) async {
        await tester.pumpWidget(
          pumpHomePage(
            nodeListState: const NodeListEmpty(),
            visualizationState: const VisualizationInitial(),
          ),
        );

        expect(find.textContaining('nodos detectados'), findsNothing);
      },
    );

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // BUG-001 / T3.8
    //
    // Wire onEnlazar — al tocar "Enlazar" en el tooltip,
    // HomePage debe despachar ConnectToDevice usando:
    //
    //   User.localNodeId → ConnectToDevice.myNodeId
    //
    // y nunca:
    //
    //   User.id → ConnectToDevice.myNodeId
    //
    // User.id y localNodeId son deliberadamente distintos para que
    // una regresión no pueda pasar el test accidentalmente.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    testWidgets(
      'T3.8 BUG-001: al tocar Enlazar usa User.localNodeId como myNodeId',
      (tester) async {
        final mockNodeListBloc = MockNodeListBloc();
        final mockBleBloc = MockBleBloc();
        final mockVizBloc = MockVisualizationBloc();
        final mockConnectionBloc = MockBleConnectionBloc();
        final mockUserBloc = MockUserBloc();
        final mockSessionBloc = MockScanSessionBloc();

        // ─────────────────────────────────────────────────────
        // Usuario local
        //
        // id = 42           → ID de la fila users
        // localNodeId = 99  → Nodes.id del self-node
        // ─────────────────────────────────────────────────────

        final testUser = User(
          id: 42,
          uuid: 'test-uuid',
          name: 'Usuario',
          color: '#2196F3',
          deviceType: 'android',
          createdAt: DateTime(2026, 1, 1),
          localNodeId: 99,
        );

        final userLoaded = UserLoaded(testUser);

        when(mockUserBloc.state).thenReturn(userLoaded);

        when(
          mockUserBloc.stream,
        ).thenAnswer((_) => Stream<UserState>.value(userLoaded));

        // No es necesario para la conexión en sí, pero deja el mock
        // coherente con el contrato público del UserBloc.
        when(mockUserBloc.myDeviceUuid).thenReturn('test-uuid');

        // ─────────────────────────────────────────────────────
        // Nodos detectados
        //
        // GraphNode.id = 1 debe resolverse a la dirección BLE
        // AA:BB:CC:DD:EE:FF.
        // ─────────────────────────────────────────────────────

        final nodes = [
          Node(
            id: 1,
            bleAddress: 'AA:BB:CC:DD:EE:FF',
            name: 'Nodo Alpha',
            firstSeen: DateTime(2026, 1, 1),
            lastSeen: DateTime(2026, 6, 19),
            rssiHistory: const [-50],
            connectable: true,
          ),
          ...List.generate(
            4,
            (i) => testNode(i + 2, 'AA:BB:CC:DD:EE:0${i + 2}'),
          ),
        ];

        final nodeListLoaded = NodeListLoaded(nodes);

        when(mockNodeListBloc.state).thenReturn(nodeListLoaded);

        when(
          mockNodeListBloc.stream,
        ).thenAnswer((_) => Stream<NodeListState>.value(nodeListLoaded));

        // ─────────────────────────────────────────────────────
        // BLE
        // ─────────────────────────────────────────────────────

        when(mockBleBloc.state).thenReturn(bleScanningForNodes(nodes));

        when(
          mockBleBloc.stream,
        ).thenAnswer((_) => Stream<BleState>.value(bleScanningForNodes(nodes)));

        // ─────────────────────────────────────────────────────
        // Visualización
        //
        // selectedNodeId = 1 abre automáticamente el tooltip del
        // Nodo Alpha.
        // ─────────────────────────────────────────────────────

        final graphReady = GraphReady(testLayout, selectedNodeId: 1);

        when(mockVizBloc.state).thenReturn(graphReady);

        when(
          mockVizBloc.stream,
        ).thenAnswer((_) => Stream<VisualizationState>.value(graphReady));

        // ─────────────────────────────────────────────────────
        // Conexión
        // ─────────────────────────────────────────────────────

        when(mockConnectionBloc.state).thenReturn(const BleConnectionInitial());

        when(mockConnectionBloc.stream).thenAnswer(
          (_) => Stream<BleConnectionState>.value(const BleConnectionInitial()),
        );

        // ─────────────────────────────────────────────────────
        // Scan session
        // ─────────────────────────────────────────────────────

        when(mockSessionBloc.state).thenReturn(const SessionInitial());

        when(mockSessionBloc.stream).thenAnswer(
          (_) => Stream<ScanSessionState>.value(const SessionInitial()),
        );

        // ─────────────────────────────────────────────────────
        // Render
        // ─────────────────────────────────────────────────────

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
                BlocProvider<BleBloc>.value(value: mockBleBloc),
                BlocProvider<VisualizationBloc>.value(value: mockVizBloc),
                BlocProvider<BleConnectionBloc>.value(
                  value: mockConnectionBloc,
                ),
                BlocProvider<UserBloc>.value(value: mockUserBloc),
                BlocProvider<ScanSessionBloc>.value(value: mockSessionBloc),
              ],
              child: const HomePage(),
            ),
          ),
        );

        // Procesar initState, listeners y post-frame callbacks.
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 500));

        await tester.pump(const Duration(milliseconds: 500));

        // ─────────────────────────────────────────────────────
        // Tooltip
        // ─────────────────────────────────────────────────────

        expect(find.text('Nodo Alpha'), findsAtLeast(1));

        expect(find.text('Enlazar'), findsOneWidget);

        // ─────────────────────────────────────────────────────
        // Acción
        // ─────────────────────────────────────────────────────

        await tester.tap(find.text('Enlazar'));

        await tester.pump();

        // ─────────────────────────────────────────────────────
        // Assert principal de BUG-001
        //
        // remoteId = dispositivo remoto
        // myNodeId = Nodes.id local = 99
        // ─────────────────────────────────────────────────────

        verify(
          mockConnectionBloc.add(
            argThat(
              predicate(
                (event) =>
                    event is ConnectToDevice &&
                    event.remoteId == 'AA:BB:CC:DD:EE:FF' &&
                    event.myNodeId == 99,
              ),
            ),
          ),
        ).called(1);

        // Protección explícita contra la regresión original:
        //
        // Users.id = 42 nunca debe enviarse como myNodeId.
        verifyNever(
          mockConnectionBloc.add(
            argThat(
              predicate(
                (event) => event is ConnectToDevice && event.myNodeId == 42,
              ),
            ),
          ),
        );
      },
    );

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // T5.6: Toggle 2D/3D en toolbar del grafo
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // QUÉ: cuando el grafo está visible (5+ nodos), debe aparecer un
    // botón para alternar entre vista 2D (CustomPainter) y 3D (WebView).
    // POR QUÉ: R6.1 — el usuario debe poder elegir la vista del grafo.

    testWidgets('T5.6: muestra botón toggle 2D/3D en modo grafo (5+ nodos)', (
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

      // Verifica que el botón toggle existe en la UI cuando el grafo es visible.
      // Icono: view_in_ar (3D) o grid_view (2D)
      expect(
        find.byIcon(Icons.view_in_ar),
        findsOneWidget,
        reason: 'Debe mostrar el botón para cambiar a vista 3D',
      );
    });

    testWidgets('T5.6: no muestra toggle en modo lista (≤4 nodos)', (
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

      // En modo lista, el toggle no debe mostrarse
      expect(find.byIcon(Icons.view_in_ar), findsNothing);
      expect(find.byIcon(Icons.grid_view), findsNothing);
    });

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // T5.7: Wire toggle → cambia entre GraphView (2D) y GraphView3D (3D)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // QUÉ: al presionar el toggle, el widget del grafo cambia de
    // GraphView (2D CustomPainter) a GraphView3D (WebView Three.js).
    // POR QUÉ: R6.1 + S6.1 — transición entre 2D y 3D con mismos datos.

    testWidgets('T5.7: toggle cambia de 2D a 3D al presionar view_in_ar', (
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

      // Estado inicial: modo 2D → icono view_in_ar (para cambiar a 3D)
      expect(
        find.byIcon(Icons.view_in_ar),
        findsOneWidget,
        reason: 'Modo 2D: botón para ir a 3D',
      );

      // Tocar el toggle para cambiar a 3D
      await tester.tap(find.byIcon(Icons.view_in_ar));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Después del toggle: modo 3D → icono grid_view (para volver a 2D)
      expect(
        find.byIcon(Icons.grid_view),
        findsOneWidget,
        reason: 'Modo 3D: botón para volver a 2D',
      );

      // Tocar nuevamente para volver a 2D
      await tester.tap(find.byIcon(Icons.grid_view));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // De vuelta en modo 2D
      expect(
        find.byIcon(Icons.view_in_ar),
        findsOneWidget,
        reason: 'Vuelta a modo 2D después del segundo toggle',
      );
    });
  });
}
