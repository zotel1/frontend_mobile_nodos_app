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
        verify(mockBuildGraph.call(1)).called(1);
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
        // Primer build: genera layout y lo cachea
        bloc.add(
          BuildGraphRequested(scanSessionId: 1, nodes: testNodes),
        );
        // Esperar más que el debounce para que el primer evento procese
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Segundo build: debe usar el cache como priorLayout
        bloc.add(
          BuildGraphRequested(scanSessionId: 2, nodes: testNodes),
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
        verify(mockBuildGraph.call(1)).called(1);
        verify(mockBuildGraph.call(2)).called(1);
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
          ).thenAnswer((_) async => Right(testLayout));

          final bloc = VisualizationBloc(
            buildGraph: mockBuildGraph,
            calculateLayout: mockCalculateLayout,
            debounceDuration: const Duration(milliseconds: 300),
          );

          // Disparar 3 eventos rápidos con distinto scanSessionId.
          // Cada uno incrementa _debounceSeq (1, 2, 3) y programa
          // Future.delayed(300ms).
          bloc.add(
            BuildGraphRequested(scanSessionId: 1, nodes: testNodes),
          );
          bloc.add(
            BuildGraphRequested(scanSessionId: 2, nodes: testNodes),
          );
          bloc.add(
            BuildGraphRequested(scanSessionId: 3, nodes: testNodes),
          );

          // Avanzar 200ms: las 3 Futures aún no se resuelven
          async.elapse(const Duration(milliseconds: 200));
          async.flushMicrotasks();
          verifyNever(mockBuildGraph.call(any));

          // Avanzar otros 200ms (total 400ms): las 3 Futures se resuelven.
          // Solo la del seq=3 pasa la verificación currentSeq == _debounceSeq.
          async.elapse(const Duration(milliseconds: 200));
          async.flushMicrotasks();

          // Solo el último (scanSessionId=3) debe procesarse
          verify(mockBuildGraph.call(3)).called(1);
          verifyNever(mockBuildGraph.call(1));
          verifyNever(mockBuildGraph.call(2));

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
        verify(mockBuildGraph.call(any)).called(1);
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
        verify(mockBuildGraph.call(1)).called(1);
        verify(mockBuildGraph.call(2)).called(1);
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

    // ─── T-PR1-011 RED: RetryGraphBuild ──────────────────────────
    // QUÉ: verifica que al despachar RetryGraphBuild cuando el estado
    // es GraphError, el BLoC redispare BuildGraphRequested con los
    // mismos parámetros (sessionId y nodos) que causaron el error.
    // POR QUÉ: actualmente no existe RetryGraphBuild. Cuando el grafo
    // falla, el usuario ve "Error al construir grafo" sin opción de
    // reintentar. La UI necesita un evento de reintento que rearme
    // la construcción del grafo con los parámetros originales.

    blocTest<VisualizationBloc, VisualizationState>(
      'T-PR1-011: RetryGraphBuild desde GraphError redispra BuildGraphRequested',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          debounceDuration: Duration.zero,
        );
      },
      seed: () => const GraphError('Error previo'),
      act: (bloc) => bloc.add(RetryGraphBuild(
        lastSessionId: 42,
        lastNodes: [testNodeA],
      )),
      // wait: el build es asíncrono, damos tiempo para que complete
      wait: const Duration(seconds: 1),
      expect: () => [
        isA<GraphBuilding>(),
        isA<GraphReady>().having(
          (s) => s.layout,
          'layout',
          equals(testLayout),
        ),
      ],
      verify: (_) {
        verify(mockBuildGraph.call(42)).called(1);
      },
    );
  });
}
