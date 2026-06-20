import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/session_node.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/repositories/history_repository.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_session_detail.dart';

@GenerateNiceMocks([MockSpec<HistoryRepository>()])
import 'get_session_detail_test.mocks.dart';

/// T3.3: Tests para GetSessionDetail — caso de uso que delega la
/// consulta de nodos de sesión al HistoryRepository.
///
/// S4.3: Retorna lista de nodos con RSSI y proximidad desde el repo.
void main() {
  late MockHistoryRepository mockRepo;
  late GetSessionDetail useCase;

  setUp(() {
    mockRepo = MockHistoryRepository();
    useCase = GetSessionDetail(mockRepo);
  });

  final testNodes = [
    SessionNode(
      id: 1,
      sessionId: 1,
      nodeId: 10,
      rssi: -45,
      nodeName: 'Nodo Alpha',
      proximityLevel: 'close',
    ),
    SessionNode(
      id: 2,
      sessionId: 1,
      nodeId: 20,
      rssi: -75,
      nodeName: 'Nodo Beta',
      proximityLevel: 'medium',
    ),
  ];

  group('T3.3: GetSessionDetail', () {
    test('retorna lista de nodos cuando el repositorio retorna Right',
        () async {
      when(mockRepo.getSessionDetail(1))
          .thenAnswer((_) async => Right(testNodes));

      final result =
          await useCase(GetSessionDetailParams(sessionId: 1));

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) => expect(nodes, equals(testNodes)),
      );
      verify(mockRepo.getSessionDetail(1)).called(1);
    });

    test('retorna lista vacía cuando el repositorio retorna vacío',
        () async {
      when(mockRepo.getSessionDetail(any))
          .thenAnswer((_) async => const Right(<SessionNode>[]));

      final result =
          await useCase(GetSessionDetailParams(sessionId: 999));

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) => expect(nodes, isEmpty),
      );
    });

    test('retorna Left con Failure cuando el repositorio falla', () async {
      when(mockRepo.getSessionDetail(any)).thenAnswer(
          (_) async => Left(UnexpectedFailure('DB error')));

      final result =
          await useCase(GetSessionDetailParams(sessionId: 1));

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<UnexpectedFailure>()),
        (_) => fail('Expected Left, got Right'),
      );
    });
  });
}
