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
        when(mockConnectionBloc.state).thenReturn(const BleConnectionInitial());
        when(mockConnectionBloc.stream).thenAnswer(
          (_) => Stream.fromIterable([
            const BleConnecting(remoteId: 'AA:BB:CC:DD:EE:FF'),
          ]),
        );

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
                BlocProvider<ScanSessionBloc>.value(value: mockSessionBloc()),
              ],
              child: const HomePage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verificar el SnackBar "Conectando..."
        expect(find.textContaining('Conectando'), findsOneWidget);
      },
    );

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // T3.7: Nuevos tests PR3 — Connection UX + Permissions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    testWidgets('T3.7: BluetoothOff despacha ClearNodes al NodeListBloc', (
      tester,
    ) async {
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

      // Emitir BluetoothOff y esperar procesamiento
      bleController.add(const BluetoothOff());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verificar que ClearNodes fue despachado
      verify(mockNodeListBloc.add(const ClearNodes())).called(1);

      bleController.close();
    });

    testWidgets('T3.7: muestra grafo con 1 solo nodo (umbral removido)', (
      tester,
    ) async {
      final nodes = [testNode(1, 'AA:BB:CC:DD:EE:01')];
      await tester.pumpWidget(
        pumpHomePage(
          nodeListState: NodeListLoaded(nodes),
          visualizationState: GraphReady(testLayout),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Con 1 nodo debe mostrarse el grafo (antes requería 5+).
      // Verificamos el comportamiento visible, no el mecanismo de transición.
      expect(find.byType(GraphView), findsOneWidget);
    });

    testWidgets(
      'T3.7: RemoteIdentityUnavailable abre bottom sheet de metadata',
      (tester) async {
        final mockNodeListBloc = MockNodeListBloc();
        final mockBleBloc = MockBleBloc();
        final mockVizBloc = MockVisualizationBloc();
        final mockConnectionBloc = MockBleConnectionBloc();

        final nodes = List.generate(
          3,
          (i) => testNode(i + 1, 'AA:BB:CC:DD:EE:0${i + 1}'),
        );

        when(mockNodeListBloc.state).thenReturn(NodeListLoaded(nodes));
        when(
          mockNodeListBloc.stream,
        ).thenAnswer((_) => Stream.value(NodeListLoaded(nodes)));
        when(mockBleBloc.state).thenReturn(const BleStopped());
        when(
          mockBleBloc.stream,
        ).thenAnswer((_) => Stream.value(const BleStopped()));
        when(mockVizBloc.state).thenReturn(const VisualizationInitial());
        when(
          mockVizBloc.stream,
        ).thenAnswer((_) => Stream.value(const VisualizationInitial()));
        when(mockConnectionBloc.state).thenReturn(
          const RemoteIdentityUnavailable(remoteId: 'AA:BB:CC:DD:EE:01'),
        );
        when(mockConnectionBloc.stream).thenAnswer(
          (_) => Stream.value(
            const RemoteIdentityUnavailable(remoteId: 'AA:BB:CC:DD:EE:01'),
          ),
        );

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
                BlocProvider<ScanSessionBloc>.value(value: mockSessionBloc()),
              ],
              child: const HomePage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // La metadata sheet debería abrirse — buscamos el botón Guardar
        expect(find.text('Guardar'), findsOneWidget);
        expect(find.text('Identificar nodo'), findsOneWidget);
      },
    );

    testWidgets(
      'T3.7: RemoteIdentityLoaded despacha UpdateNodeMetadata al NodeListBloc',
      (tester) async {
        final mockNodeListBloc = MockNodeListBloc();
        final mockBleBloc = MockBleBloc();
        final mockVizBloc = MockVisualizationBloc();
        final mockConnectionBloc = MockBleConnectionBloc();

        final nodes = [
          Node(
            id: 1,
            bleAddress: 'AA:BB:CC:DD:EE:01',
            name: null,
            firstSeen: DateTime(2026, 1, 1),
            lastSeen: DateTime(2026, 6, 20),
            rssiHistory: const [-50],
          ),
          testNode(2, 'AA:BB:CC:DD:EE:02'),
          testNode(3, 'AA:BB:CC:DD:EE:03'),
        ];

        when(mockNodeListBloc.state).thenReturn(NodeListLoaded(nodes));

        when(
          mockNodeListBloc.stream,
        ).thenAnswer((_) => Stream.value(NodeListLoaded(nodes)));

        when(mockBleBloc.state).thenReturn(const BleStopped());

        when(
          mockBleBloc.stream,
        ).thenAnswer((_) => Stream.value(const BleStopped()));

        when(mockVizBloc.state).thenReturn(const VisualizationInitial());

        when(
          mockVizBloc.stream,
        ).thenAnswer((_) => Stream.value(const VisualizationInitial()));

        when(mockConnectionBloc.state).thenReturn(
          const RemoteIdentityLoaded(
            remoteId: 'AA:BB:CC:DD:EE:01',
            uuid: '550e8400-e29b-41d4-a716-446655440001',
            name: 'Nodo Remoto',
            color: '#FF5722',
          ),
        );

        when(mockConnectionBloc.stream).thenAnswer(
          (_) => Stream.value(
            const RemoteIdentityLoaded(
              remoteId: 'AA:BB:CC:DD:EE:01',
              uuid: '550e8400-e29b-41d4-a716-446655440001',
              name: 'Nodo Remoto',
              color: '#FF5722',
            ),
          ),
        );

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
                BlocProvider<ScanSessionBloc>.value(value: mockSessionBloc()),
              ],
              child: const HomePage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Verificar que UpdateNodeIdentity fue despachado
        // con el nombre recibido desde la identidad remota.
        verify(
          mockNodeListBloc.add(
            argThat(
              predicate(
                (e) =>
                    e is UpdateNodeIdentity &&
                    e.nodeId == 1 &&
                    e.deviceUuid == '550e8400-e29b-41d4-a716-446655440001' &&
                    e.name == 'Nodo Remoto',
              ),
            ),
          ),
        ).called(1);

        // El color forma parte del mismo UpdateNodeIdentity.
      },
    );
  });
}
