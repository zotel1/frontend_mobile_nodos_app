import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/build_graph.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';

import 'visualization_bloc_test.mocks.dart';

class _FakeRemoteRelationRepository implements RemoteRelationRepository {
  @override
  Future<void> replaceSnapshot({
    required String reporterUuid,
    required List<NodosGraphConnection> connections,
  }) async {}
  @override
  Future<void> clearSnapshot(String reporterUuid) async {}
  @override
  Future<List<RemoteRelation>> getSnapshot(String reporterUuid) async => [];
  @override
  Stream<List<RemoteRelation>> watchAll() => const Stream.empty();
}

void main() {
  late MockBuildGraph mockBuildGraph;
  late MockCalculateLayout mockCalculateLayout;
  final remoteRelationRepository = _FakeRemoteRelationRepository();
  final testNodes = <Node>[];
  const testLayout = LayoutResult(
    nodes: [
      GraphNode(id: 1, x: 100, y: 150, proximity: ProximityLevel.close),
      GraphNode(id: 2, x: 300, y: 250, proximity: ProximityLevel.medium),
    ],
    edges: [GraphEdge(fromId: 1, toId: 2, thickness: 2)],
    iterations: 100,
    converged: true,
  );

  void setupDefaultMocks() {
    when(
      mockBuildGraph.call(any, myDeviceUuid: anyNamed('myDeviceUuid')),
    ).thenAnswer((_) async => Right(testLayout));
    when(
      mockCalculateLayout.call(
        any,
        any,
        any,
        depth: anyNamed('depth'),
        priorLayout: anyNamed('priorLayout'),
        seed: anyNamed('seed'),
        stabilize: anyNamed('stabilize'),
      ),
    ).thenAnswer((_) async => Right(testLayout));
  }

  setUp(() {
    mockBuildGraph = MockBuildGraph();
    mockCalculateLayout = MockCalculateLayout();
  });

  group('VisualizationBloc identity context', () {
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
          remoteRelationRepository: remoteRelationRepository,
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
      expect: () => [isA<GraphBuilding>(), isA<GraphReady>()],
      verify: (_) {
        verify(
          mockBuildGraph.call(1, myDeviceUuid: 'my-device-uuid-abc'),
        ).called(1);
      },
    );

    blocTest<VisualizationBloc, VisualizationState>(
      'PR7 T7.2: BuildGraphRequested sin myDeviceUuid lo pasa como null',
      build: () {
        setupDefaultMocks();
        return VisualizationBloc(
          buildGraph: mockBuildGraph,
          calculateLayout: mockCalculateLayout,
          remoteRelationRepository: remoteRelationRepository,
          debounceDuration: Duration.zero,
        );
      },
      act: (bloc) =>
          bloc.add(BuildGraphRequested(scanSessionId: 1, nodes: testNodes)),
      expect: () => [isA<GraphBuilding>(), isA<GraphReady>()],
      verify: (_) {
        verify(mockBuildGraph.call(1, myDeviceUuid: null)).called(1);
      },
    );
  });
}
