import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dartz/dartz.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/repositories/graph_repository.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/build_graph.dart';

@GenerateNiceMocks([MockSpec<GraphRepository>()])
import 'build_graph_test.mocks.dart';

void main() {
  late MockGraphRepository mockRepository;
  late BuildGraph useCase;

  final testLayout = LayoutResult(
    nodes: [
      GraphNode(id: 1, x: 100.0, y: 150.0, proximity: ProximityLevel.close),
      GraphNode(id: 2, x: 300.0, y: 250.0, proximity: ProximityLevel.medium),
    ],
    edges: [
      GraphEdge(fromId: 1, toId: 2, thickness: 2.0),
    ],
    iterations: 0,
    converged: false,
  );

  setUp(() {
    mockRepository = MockGraphRepository();
    useCase = BuildGraph(mockRepository);
  });

  group('BuildGraph', () {
    test('calls repository.buildGraph and returns Right(LayoutResult)', () async {
      // arrange
      when(mockRepository.buildGraph(42)).thenAnswer(
        (_) async => testLayout,
      );

      // act
      final result = await useCase(42);

      // assert
      expect(result, isA<Right<Failure, LayoutResult>>());
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (layout) {
          expect(layout.nodes.length, 2);
          expect(layout.edges.length, 1);
          expect(layout.iterations, 0);
          expect(layout.converged, false);
        },
      );
      verify(mockRepository.buildGraph(42)).called(1);
    });

    test('returns Left(UnexpectedFailure) when repository throws', () async {
      // arrange
      when(mockRepository.buildGraph(any)).thenThrow(
        Exception('DB error'),
      );

      // act
      final result = await useCase(1);

      // assert
      expect(result, isA<Left<Failure, LayoutResult>>());
      result.fold(
        (failure) {
          expect(failure, isA<UnexpectedFailure>());
          expect(failure.message, contains('DB error'));
        },
        (_) => fail('Expected Left, got Right'),
      );
    });

    test('returns empty LayoutResult when session has no nodes', () async {
      // arrange
      when(mockRepository.buildGraph(99)).thenAnswer(
        (_) async => const LayoutResult(
          nodes: [],
          edges: [],
          iterations: 0,
          converged: false,
        ),
      );

      // act
      final result = await useCase(99);

      // assert
      expect(result, isA<Right<Failure, LayoutResult>>());
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (layout) {
          expect(layout.nodes, isEmpty);
          expect(layout.edges, isEmpty);
        },
      );
      verify(mockRepository.buildGraph(99)).called(1);
    });
  });
}
