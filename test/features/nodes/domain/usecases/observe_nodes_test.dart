import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';

@GenerateNiceMocks([MockSpec<NodeRepository>()])
import 'observe_nodes_test.mocks.dart';

void main() {
  late MockNodeRepository mockRepository;
  late ObserveNodes useCase;

  final now = DateTime(2026, 6, 18, 12, 0, 0);

  setUp(() {
    mockRepository = MockNodeRepository();
    useCase = ObserveNodes(mockRepository);
  });

  group('ObserveNodes', () {
    test('returns stream from repository.observeNodes()', () async {
      // arrange
      final testNodes = [
        Node(
          id: 1,
          bleAddress: 'AA:BB:CC:DD:EE:FF',
          name: 'Test',
          firstSeen: now,
          lastSeen: now,
        ),
      ];
      when(mockRepository.observeNodes()).thenAnswer(
        (_) => Stream.value(testNodes),
      );

      // act
      final stream = useCase();

      // assert
      final result = await stream.first;
      expect(result, equals(testNodes));
      verify(mockRepository.observeNodes()).called(1);
    });

    test('stream propagates repository errors', () {
      // arrange
      when(mockRepository.observeNodes()).thenAnswer(
        (_) => Stream.error(Exception('DB error')),
      );

      // act
      final stream = useCase();

      // assert
      expect(stream.first, throwsA(isA<Exception>()));
    });
  });
}
