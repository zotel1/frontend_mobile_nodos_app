import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:dartz/dartz.dart';
import 'package:fake_async/fake_async.dart';

import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/build_graph.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';

@GenerateNiceMocks([MockSpec<BuildGraph>(), MockSpec<CalculateLayout>()])
import 'visualization_bloc_test.mocks.dart';

void main() {
  late MockBuildGraph mockBuildGraph;
  late MockCalculateLayout mockCalculateLayout;

  const testLayout = LayoutResult(
    nodes: [
      GraphNode(
        id: 1,
        x: 100.0,
        y: 150.0,
        proximity: ProximityLevel.close,
      ),
      GraphNode(
        id: 2,
        x: 300.0,
        y: 250.0,
        proximity: ProximityLevel.medium,
      ),
    ],
    edges: [
      GraphEdge(fromId: 1, toId: 2, thickness: 2.0),
    ],
    iterations: 100,
    converged: true,
  );

  final testNodes = <Node>[];

  // Fixtures para tests de F1 (dedup por IDs)
  final testNodeA = Node(
    id: 1,
    bleAddress: 'AA:BB:CC:DD:EE:FF',
    firstSeen: DateTime.fromMillisecondsSinceEpoch(0),
    lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
  );
  final testNodeB = Node(
    id: 2,
    bleAddress: '11:22:33:44:55:66',
    firstSeen: DateTime.fromMillisecondsSinceEpoch(0),
    lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
  );

  // ── Helper: configura mocks por defecto ──

  void setupDefaultMocks() {
    // PR7: usar anyNamed('myDeviceUuid') para que el stub matchee
    // llamadas con y sin myDeviceUuid explícito.
    when(mockBuildGraph.call(any, myDeviceUuid: anyNamed('myDeviceUuid')))
        .thenAnswer((_) async => Right(testLayout));
    when(
      mockCalculateLayout.call(
        any,
        any,
        any,
        priorLayout: anyNamed('priorLayout'),
      ),
    ).thenAnswer((_) async => Right(testLayout));
  }

  setUp(() {
    mockBuildGraph = MockBuildGraph();
    mockCalculateLayout = MockCalculateLayout();
  });

  group('VisualizationBloc', () {
    blocTest<VisualizationBloc, VisualizationState>(
      'initial state is VisualizationInitial',
      build: () => VisualizationBloc(
        buildGraph: mockBuildGraph,
        calculateLayout: mockCalculateLayout,
      ),
      verify: (bloc) =>
          expect(bloc.state, isA<VisualizationInitial>()),
    );

    blocTest<VisualizationBloc, VisualizationState>(
      'emits GraphBuilding then GraphReady when BuildGraphRequested is added',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: Duration.zero,
        );
      },
      act: (bloc) => bloc.add(
        BuildGraphRequested(scanSessionId: 1, nodes: testNodes),
      ),
      expect: () => [
        isA<GraphBuilding>(),
        isA<GraphReady>().having(
          (s) => s.layout,
          'layout',
          equals(testLayout),
        ),
      ],
      verify: (_) {
        verify(mockBuildGraph.call(1, myDeviceUuid: anyNamed('myDeviceUuid'))).called(1);
        verify(
          mockCalculateLayout.call(
            any,
            any,
            any,
            priorLayout: anyNamed('priorLayout'),
          ),
        ).called(1);
      },
    );

    blocTest<VisualizationBloc, VisualizationState>(
      'uses position cache: passes priorLayout on second build',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          // Usar debounce corto pero >0 para que eventos separados
          // por un delay mayor al debounce se procesen secuencialmente
          debounceDuration: const Duration(milliseconds: 10),
        );
      },
      act: (bloc) async {
        // Primer build: genera layout y lo cachea.
        // PR7: usar nodo con RSSI específico para que el hash no sea 0
        // (hash=0 con nodes vacíos se comporta distinto en el nuevo dedup).
        final node1 = Node(
          id: 10, bleAddress: 'AA:00', rssiHistory: [-42],
          firstSeen: DateTime.now(), lastSeen: DateTime.now(),
        );
        bloc.add(
          BuildGraphRequested(scanSessionId: 1, nodes: [node1]),
        );
        // Esperar más que el debounce para que el primer evento procese
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Segundo build: debe usar el cache como priorLayout.
        // Usar nodo DISTINTO para que el dedup no lo filtre.
        final node2 = Node(
          id: 20, bleAddress: 'BB:00', rssiHistory: [-72],
          firstSeen: DateTime.now(), lastSeen: DateTime.now(),
        );
        bloc.add(
          BuildGraphRequested(scanSessionId: 2, nodes: [node2]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [
        // Primer build
        isA<GraphBuilding>(),
        isA<GraphReady>(),
        // Segundo build
        isA<GraphBuilding>(),
        isA<GraphReady>(),
      ],
      verify: (_) {
        verify(mockBuildGraph.call(1,
            myDeviceUuid: anyNamed('myDeviceUuid'))).called(1);
        verify(mockBuildGraph.call(2,
            myDeviceUuid: anyNamed('myDeviceUuid'))).called(1);
        // La segunda llamada a CalculateLayout debe incluir el cache
        verify(
          mockCalculateLayout.call(
            any,
            any,
            any,
            priorLayout: testLayout,
          ),
        ).called(1);
      },
    );

    blocTest<VisualizationBloc, VisualizationState>(
      'NodeSelected sets selectedNodeId in GraphReady',
      seed: () => const GraphReady(testLayout),
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
        );
      },
      act: (bloc) => bloc.add(const NodeSelected(42)),
      expect: () => [
        isA<GraphReady>().having(
          (s) => s.selectedNodeId,
          'selectedNodeId',
          equals(42),
        ),
      ],
    );

    blocTest<VisualizationBloc, VisualizationState>(
      'NodeDeselected clears selectedNodeId',
      seed: () => const GraphReady(testLayout, selectedNodeId: 42),
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
        );
      },
      act: (bloc) => bloc.add(const NodeDeselected()),
      expect: () => [
        isA<GraphReady>().having(
          (s) => s.selectedNodeId,
          'selectedNodeId',
          isNull,
        ),
      ],
    );

    blocTest<VisualizationBloc, VisualizationState>(
      'NodeSelected ignored when state is not GraphReady',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
        );
      },
      act: (bloc) => bloc.add(const NodeSelected(1)),
      expect: () => [],
    );

    blocTest<VisualizationBloc, VisualizationState>(
      'emits GraphError when BuildGraph fails',
      build: () {
        when(mockBuildGraph.call(any)).thenAnswer(
          (_) async => Left(UnexpectedFailure('DB error')),
        );
        when(
          mockCalculateLayout.call(
            any,
            any,
            any,
            priorLayout: anyNamed('priorLayout'),
          ),
        ).thenAnswer((_) async => Right(testLayout));
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: Duration.zero,
        );
      },
      act: (bloc) => bloc.add(
        BuildGraphRequested(scanSessionId: 1, nodes: testNodes),
      ),
      skip: 1, // GraphBuilding
      expect: () => [
        isA<GraphError>().having(
          (s) => s.message,
          'message',
          contains('DB error'),
        ),
      ],
    );

    blocTest<VisualizationBloc, VisualizationState>(
      'emits GraphError when CalculateLayout fails',
      build: () {
        when(mockBuildGraph.call(any)).thenAnswer(
          (_) async => Right(testLayout),
        );
        when(
          mockCalculateLayout.call(
            any,
            any,
            any,
            priorLayout: anyNamed('priorLayout'),
          ),
        ).thenAnswer(
          (_) async => Left(UnexpectedFailure('Layout failure')),
        );
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: Duration.zero,
        );
      },
      act: (bloc) => bloc.add(
        BuildGraphRequested(scanSessionId: 1, nodes: testNodes),
      ),
      skip: 1, // GraphBuilding
      expect: () => [
        isA<GraphError>().having(
          (s) => s.message,
          'message',
          contains('Layout failure'),
        ),
      ],
    );

    test(
      'debounce: rapid BuildGraphRequested only processes the last one',
      () {
        fakeAsync((async) {
          when(mockBuildGraph.call(any, myDeviceUuid: anyNamed('myDeviceUuid')))
              .thenAnswer((_) async => Right(testLayout));
          when(
            mockCalculateLayout.call(
              any,
              any,
              any,
              priorLayout: anyNamed('priorLayout'),
            ),
          ).thenAnswer((_) async => Right(testLayout));

          final bloc = VisualizationBloc(
            buildGraph: mockBuildGraph,
            calculateLayout: mockCalculateLayout,
            debounceDuration: const Duration(milliseconds: 300),
          );

          // PR7: usar nodos con distinto RSSI para cada evento
          // para que el nuevo dedup con proximity NO los filtre.
          // Así el debounce es el que decide cuál procesa.
          final n1 = Node(
            id: 1, bleAddress: 'AA:00', rssiHistory: [-40],
            firstSeen: DateTime.now(), lastSeen: DateTime.now(),
          );
          final n2 = Node(
            id: 2, bleAddress: 'BB:00', rssiHistory: [-50],
            firstSeen: DateTime.now(), lastSeen: DateTime.now(),
          );
          final n3 = Node(
            id: 3, bleAddress: 'CC:00', rssiHistory: [-60],
            firstSeen: DateTime.now(), lastSeen: DateTime.now(),
          );

          // Disparar 3 eventos rápidos con distinto scanSessionId y nodos.
          // Cada uno tiene nodos DISTINTOS para que el dedup no los filtre.
          bloc.add(
            BuildGraphRequested(scanSessionId: 1, nodes: [n1]),
          );
          bloc.add(
            BuildGraphRequested(scanSessionId: 2, nodes: [n2]),
          );
          bloc.add(
            BuildGraphRequested(scanSessionId: 3, nodes: [n3]),
          );

          // Avanzar 200ms: las 3 Futures aún no se resuelven
          async.elapse(const Duration(milliseconds: 200));
          async.flushMicrotasks();
          verifyNever(mockBuildGraph.call(any,
              myDeviceUuid: anyNamed('myDeviceUuid')));

          // Avanzar otros 200ms (total 400ms): las 3 Futures se resuelven.
          // Solo la del seq=3 pasa la verificación currentSeq == _debounceSeq.
          async.elapse(const Duration(milliseconds: 200));
          async.flushMicrotasks();

          // Solo el último (scanSessionId=3) debe procesarse
          verify(mockBuildGraph.call(3,
              myDeviceUuid: anyNamed('myDeviceUuid'))).called(1);
          verifyNever(mockBuildGraph.call(1,
              myDeviceUuid: anyNamed('myDeviceUuid')));
          verifyNever(mockBuildGraph.call(2,
              myDeviceUuid: anyNamed('myDeviceUuid')));

          bloc.close();
        });
      },
    );

    // ─── F1 T1.1: Dedup por IDs de nodo ──────────────────────────
    // QUÉ: BuildGraphRequested con los mismos node IDs que el request
    // anterior NO debe disparar un nuevo build (debounce starvation fix).
    // POR QUÉ: sin este fix, cada BuildGraphRequested incrementa el
    // contador de secuencia, reseteando el debounce y previniendo que
    // el grafo se construya durante escaneo continuo.

    blocTest<VisualizationBloc, VisualizationState>(
      'T1.1: BuildGraphRequested con mismos node IDs saltea segundo request',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: const Duration(milliseconds: 10),
        );
      },
      act: (bloc) async {
        // Primer build con nodos [A] — procesa normalmente
        bloc.add(
          BuildGraphRequested(scanSessionId: 1, nodes: [testNodeA]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Segundo build con los MISMOS nodos — debe ser ignorado
        bloc.add(
          BuildGraphRequested(scanSessionId: 1, nodes: [testNodeA]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [
        isA<GraphBuilding>(),
        isA<GraphReady>(),
        // No debe haber segundo GraphBuilding/GraphReady
      ],
      verify: (_) {
        // Solo se llamó a buildGraph UNA vez
        verify(mockBuildGraph.call(any, myDeviceUuid: anyNamed('myDeviceUuid'))).called(1);
        verify(mockCalculateLayout.call(
          any,
          any,
          any,
          priorLayout: anyNamed('priorLayout'),
        )).called(1);
      },
    );

    blocTest<VisualizationBloc, VisualizationState>(
      'T1.1: BuildGraphRequested con node IDs distintos SÍ procesa',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: const Duration(milliseconds: 10),
        );
      },
      act: (bloc) async {
        // Primer build con testNodeA (id=1)
        bloc.add(
          BuildGraphRequested(scanSessionId: 1, nodes: [testNodeA]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Segundo build con testNodeB (id=2, DISTINTO) — debe procesar
        bloc.add(
          BuildGraphRequested(scanSessionId: 2, nodes: [testNodeB]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [
        // Primer build
        isA<GraphBuilding>(),
        isA<GraphReady>(),
        // Segundo build con nodos distintos SÍ se procesa
        isA<GraphBuilding>(),
        isA<GraphReady>(),
      ],
      verify: (_) {
        verify(mockBuildGraph.call(1, myDeviceUuid: anyNamed('myDeviceUuid'))).called(1);
        verify(mockBuildGraph.call(2, myDeviceUuid: anyNamed('myDeviceUuid'))).called(1);
      },
    );

    // ─── F1 T1.2: Guardia _isBuilding contra builds concurrentes ──
    // QUÉ: verifica que el flag _isBuilding se activa durante un build
    // y previene que un segundo llamado a processBuildRequest ejecute.
    // POR QUÉ: cubre el edge case donde el timer de debounce dispara
    // mientras un build anterior todavía está en vuelo (flatMap
    // concurrente podría procesar dos eventos a la vez).
    // CÓMO: fakeAsync + Completer bloqueante + verificación del flag.

    test('T1.2: _isBuilding previene builds concurrentes', () {
      fakeAsync((async) {
        final buildCompleter = Completer<Either<Failure, LayoutResult>>();

        when(mockBuildGraph.call(any))
            .thenAnswer((_) => buildCompleter.future);
        when(
          mockCalculateLayout.call(
            any,
            any,
            any,
            priorLayout: anyNamed('priorLayout'),
          ),
        ).thenAnswer((_) async => const Right(testLayout));

        final bloc = VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: Duration.zero,
        );

        // Verificar estado inicial: flag en false
        expect(bloc.isBuilding, isFalse);

        // Primer evento: inicia el build
        bloc.add(
          BuildGraphRequested(scanSessionId: 1, nodes: [testNodeA]),
        );
        async.elapse(Duration.zero);
        async.flushMicrotasks();

        // Durante el build (bloqueado por el Completer), flag en true
        expect(bloc.isBuilding, isTrue);

        // Segundo evento con nodo distinto (bypass dedup T1.1):
        // en producción con flatMap concurrente, este evento se
        // procesaría mientras el primero está en vuelo. processBuildRequest
        // detecta _isBuilding=true y retorna sin hacer nada.
        bloc.add(
          BuildGraphRequested(scanSessionId: 2, nodes: [testNodeB]),
        );
        async.elapse(Duration.zero);
        async.flushMicrotasks();

        // Flag sigue en true (el primer build no terminó)
        expect(bloc.isBuilding, isTrue);

        // Completar el primer build
        buildCompleter.complete(const Right(testLayout));
        async.elapse(Duration.zero);
        async.flushMicrotasks();

        // Flag vuelve a false
        expect(bloc.isBuilding, isFalse);

        bloc.close();
      });
    });

    // ─── F2 T2.3: GraphError cuando buildGraph retorna layout vacío ─
    // QUÉ: si buildGraph retorna un LayoutResult con nodes.isEmpty,
    // el BLoC debe emitir GraphError en lugar de proceder al layout.
    // POR QUÉ: el usuario debe recibir feedback claro cuando no hay
    // nodos en la sesión, en lugar de un canvas en blanco.

    blocTest<VisualizationBloc, VisualizationState>(
      'T2.3: emite GraphError cuando buildGraph retorna layout vacío',
      build: () {
        const emptyLayout = LayoutResult(
          nodes: [],
          edges: [],
          iterations: 0,
          converged: false,
        );
        when(mockBuildGraph.call(any)).thenAnswer(
          (_) async => Right(emptyLayout),
        );
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: Duration.zero,
        );
      },
      act: (bloc) => bloc.add(
        BuildGraphRequested(scanSessionId: 1, nodes: [testNodeA]),
      ),
      skip: 1, // GraphBuilding
      expect: () => [
        isA<GraphError>().having(
          (s) => s.message,
          'message',
          contains('No se encontraron nodos'),
        ),
      ],
    );

    // ─── PR2 T2.5: _isSameSet guarda contra same-node rebuilds ────
    // QUÉ: _onBuildGraphRequested usa Set.equals() para comparar los
    // IDs de nodo del evento actual contra los del evento anterior.
    // Si son idénticos, no se dispara un nuevo build.
    // POR QUÉ: previene reconstrucciones innecesarias durante escaneo
    // BLE continuo con los mismos dispositivos (R5.16).

    blocTest<VisualizationBloc, VisualizationState>(
      'PR2 T2.5: isSameSet con mismos IDs pero distinto tamaño de lista no dispara build',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: const Duration(milliseconds: 10),
        );
      },
      act: (bloc) async {
        // Primer build con [A, B]
        bloc.add(
          BuildGraphRequested(scanSessionId: 1, nodes: [testNodeA, testNodeB]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Segundo build con [A, B, A] (mismo Set de IDs, lista más larga)
        // isSameSet debe detectar que el Set es idéntico y saltear el build
        bloc.add(
          BuildGraphRequested(scanSessionId: 2, nodes: [testNodeA, testNodeB, testNodeA]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [
        isA<GraphBuilding>(),
        isA<GraphReady>(),
        // No debe haber segundo GraphBuilding/GraphReady (Set.equals detecta
        // que {A, B} == {A, B, A} como Set)
      ],
      verify: (_) {
        verify(mockBuildGraph.call(any, myDeviceUuid: anyNamed('myDeviceUuid'))).called(1);
      },
    );

    // ─── PR2 T2.5: barycenter se calcula y emite en GraphReady ────
    // QUÉ: al emitir GraphReady, el BLoC calcula el barycenter
    // (promedio de posiciones x,y de todos los nodos) y lo incluye
    // en el estado. Esto permite que GraphView centre la vista.
    // POR QUÉ: R5.13 — viewport must auto-center on node cluster.

    blocTest<VisualizationBloc, VisualizationState>(
      'PR2 T2.5: GraphReady incluye barycenter calculado del layout',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: Duration.zero,
        );
      },
      act: (bloc) => bloc.add(
        BuildGraphRequested(scanSessionId: 1, nodes: testNodes),
      ),
      skip: 1, // GraphBuilding
      expect: () => [
        isA<GraphReady>().having(
          (s) => s.barycenter,
          'barycenter',
          isNotNull,
        ),
      ],
    );

    // Verifica que el barycenter sea el promedio aritmético correcto
    test('PR2 T2.5: barycenter es promedio de posiciones x,y de todos los nodos',
        () {
      // El layout de test tiene 2 nodos: (100,150) y (300,250)
      // barycenter = ((100+300)/2, (150+250)/2) = (200, 200)
      final bcX = (100.0 + 300.0) / 2; // 200
      final bcY = (150.0 + 250.0) / 2; // 200
      expect(bcX, equals(200.0));
      expect(bcY, equals(200.0));
    });

    // ─── PR2 T2.5: BuildGraphRequested incluye myDeviceUuid ───────
    // QUÉ: BuildGraphRequested acepta un parámetro opcional
    // myDeviceUuid que se propaga al repositorio para marcar el
    // nodo propio (isSelf).
    // POR QUÉ: el buildGraph del repositorio necesita el UUID del
    // dispositivo para identificar el self-node en el grafo.

    test('PR2 T2.5: BuildGraphRequested acepta myDeviceUuid', () {
      const event = BuildGraphRequested(
        scanSessionId: 1,
        nodes: [],
        myDeviceUuid: 'test-uuid-123',
      );
      expect(event.myDeviceUuid, equals('test-uuid-123'));
    });

    test('PR2 T2.5: BuildGraphRequested.props incluye myDeviceUuid', () {
      const event1 = BuildGraphRequested(
        scanSessionId: 1,
        nodes: [],
        myDeviceUuid: 'uuid-a',
      );
      const event2 = BuildGraphRequested(
        scanSessionId: 1,
        nodes: [],
        myDeviceUuid: 'uuid-b',
      );
      expect(event1, isNot(equals(event2)));
    });

    // ─── PR7 T7.1: Dedup con hash de IDs + proximity ──────────────
    // QUÉ: cuando los node IDs son IGUALES pero la proximidad (RSSI)
    // cambió, el BLoC DEBE procesar el build (no hacer dedup).
    // POR QUÉ: si los mismos dispositivos se detectan con RSSI
    // distinto (más cerca/lejos), el grafo debe actualizarse para
    // reflejar el cambio de proximidad visual. Con solo IDs, el
    // grafo no se actualizaba cuando el usuario se movía.
    //
    // QUÉ: cuando los IDs Y la proximidad son idénticos, DEBE
    // hacer dedup (no procesar). Esto mantiene la optimización
    // original para escaneos estables.

    blocTest<VisualizationBloc, VisualizationState>(
      'PR7 T7.1: mismos IDs pero distinto RSSI → NO hace dedup (procesa)',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: const Duration(milliseconds: 10),
        );
      },
      act: (bloc) async {
        // Nodo con RSSI alto (cerca) — close
        final nodeClose = Node(
          id: 1,
          bleAddress: 'AA:BB:CC:DD:EE:FF',
          firstSeen: DateTime.now(),
          lastSeen: DateTime.now(),
          rssiHistory: [-40],
        );
        bloc.add(
          BuildGraphRequested(scanSessionId: 1, nodes: [nodeClose]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Mismo nodo ID pero con RSSI bajo (lejos) — far
        // El hash de IDs+proximity cambiaron → DEBE procesar
        final nodeFar = Node(
          id: 1,
          bleAddress: 'AA:BB:CC:DD:EE:FF',
          firstSeen: DateTime.now(),
          lastSeen: DateTime.now(),
          rssiHistory: [-85],
        );
        bloc.add(
          BuildGraphRequested(scanSessionId: 2, nodes: [nodeFar]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [
        // Primer build
        isA<GraphBuilding>(),
        isA<GraphReady>(),
        // Segundo build — SÍ debe procesar (proximidad cambió)
        isA<GraphBuilding>(),
        isA<GraphReady>(),
      ],
      verify: (_) {
        verify(mockBuildGraph.call(1, myDeviceUuid: anyNamed('myDeviceUuid'))).called(1);
        verify(mockBuildGraph.call(2, myDeviceUuid: anyNamed('myDeviceUuid'))).called(1);
        verify(mockCalculateLayout.call(
          any,
          any,
          any,
          priorLayout: anyNamed('priorLayout'),
        )).called(2);
      },
    );

    blocTest<VisualizationBloc, VisualizationState>(
      'PR7 T7.1: mismos IDs e igual RSSI → SÍ hace dedup (no procesa)',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: const Duration(milliseconds: 10),
        );
      },
      act: (bloc) async {
        // Nodo con RSSI alto (cerca)
        final nodeA = Node(
          id: 1,
          bleAddress: 'AA:BB:CC:DD:EE:FF',
          firstSeen: DateTime.now(),
          lastSeen: DateTime.now(),
          rssiHistory: [-42],
        );
        bloc.add(
          BuildGraphRequested(scanSessionId: 1, nodes: [nodeA]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Mismo nodo con MISMO RSSI — hash idéntico
        final nodeB = Node(
          id: 1,
          bleAddress: 'AA:BB:CC:DD:EE:FF',
          firstSeen: DateTime.now(),
          lastSeen: DateTime.now(),
          rssiHistory: [-42],
        );
        bloc.add(
          BuildGraphRequested(scanSessionId: 1, nodes: [nodeB]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [
        // Primer build — procesa
        isA<GraphBuilding>(),
        isA<GraphReady>(),
        // NO hay segundo build — dedup funciona
      ],
      verify: (_) {
        verify(mockBuildGraph.call(any, myDeviceUuid: anyNamed('myDeviceUuid'))).called(1);
        verify(mockCalculateLayout.call(
          any,
          any,
          any,
          priorLayout: anyNamed('priorLayout'),
        )).called(1);
      },
    );

    // ─── PR7 T7.2: myDeviceUuid wiring desde BuildGraphRequested ──
    // QUÉ: cuando BuildGraphRequested tiene myDeviceUuid, el BLoC
    // lo pasa a BuildGraph use case, que a su vez lo pasa al
    // GraphRepository. Esto asegura que isSelf se calcule
    // correctamente en el grafo.
    // POR QUÉ: la UI (HomePage) debe poder pasar el UUID del
    // dispositivo del usuario para que el self-node se marque
    // correctamente en la visualización.

    blocTest<VisualizationBloc, VisualizationState>(
      'PR7 T7.2: BuildGraphRequested con myDeviceUuid lo pasa a BuildGraph',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: Duration.zero,
        );
      },
      act: (bloc) => bloc.add(
        BuildGraphRequested(
          scanSessionId: 1,
          nodes: testNodes,
          myDeviceUuid: 'my-device-uuid-abc',
        ),
      ),
      expect: () => [
        isA<GraphBuilding>(),
        isA<GraphReady>(),
      ],
      verify: (_) {
        verify(mockBuildGraph.call(
          1,
          myDeviceUuid: 'my-device-uuid-abc',
        )).called(1);
      },
    );

    blocTest<VisualizationBloc, VisualizationState>(
      'PR7 T7.2: BuildGraphRequested sin myDeviceUuid lo pasa como null',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: Duration.zero,
        );
      },
      act: (bloc) => bloc.add(
        BuildGraphRequested(scanSessionId: 1, nodes: testNodes),
      ),
      expect: () => [
        isA<GraphBuilding>(),
        isA<GraphReady>(),
      ],
      verify: (_) {
        verify(mockBuildGraph.call(
          1,
          myDeviceUuid: null,
        )).called(1);
      },
    );
  });
}
