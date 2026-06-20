import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/repositories/history_repository.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_history_stats.dart';

@GenerateNiceMocks([MockSpec<HistoryRepository>()])
import 'get_history_stats_test.mocks.dart';

/// T3.5: Tests para GetHistoryStats — caso de uso que delega el
/// cálculo de estadísticas al HistoryRepository.
///
/// S5.1: Retorna estadísticas agregadas desde el repositorio.
/// S5.2: Retorna cero en todas las stats cuando no hay datos.
void main() {
  late MockHistoryRepository mockRepo;
  late GetHistoryStats useCase;

  setUp(() {
    mockRepo = MockHistoryRepository();
    useCase = GetHistoryStats(mockRepo);
  });

  final testStats = HistoryStats(
    totalSessions: 5,
    uniqueNodes: 3,
    averageDuration: const Duration(minutes: 10),
    mostFrequentNodeName: 'Nodo Alpha',
  );

  group('T3.5: GetHistoryStats', () {
    test('retorna estadísticas cuando el repositorio retorna Right',
        () async {
      when(mockRepo.getStats()).thenAnswer((_) async => Right(testStats));

      final result = await useCase();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) => expect(stats, equals(testStats)),
      );
      verify(mockRepo.getStats()).called(1);
    });

    test('retorna estadísticas en cero cuando no hay datos', () async {
      const emptyStats = HistoryStats(
        totalSessions: 0,
        uniqueNodes: 0,
        averageDuration: Duration.zero,
      );
      when(mockRepo.getStats())
          .thenAnswer((_) async => const Right(emptyStats));

      final result = await useCase();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (stats) {
          expect(stats.totalSessions, equals(0));
          expect(stats.uniqueNodes, equals(0));
          expect(stats.averageDuration, equals(Duration.zero));
          expect(stats.mostFrequentNodeName, isNull);
        },
      );
    });

    test('retorna Left con Failure cuando el repositorio falla', () async {
      when(mockRepo.getStats()).thenAnswer(
          (_) async => Left(UnexpectedFailure('Stats error')));

      final result = await useCase();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<UnexpectedFailure>()),
        (_) => fail('Expected Left, got Right'),
      );
    });
  });
}
