import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/scan_session.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/repositories/history_repository.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_scan_sessions.dart';

@GenerateNiceMocks([MockSpec<HistoryRepository>()])
import 'get_scan_sessions_test.mocks.dart';

/// T3.2: Tests para GetScanSessions — caso de uso que delega la
/// consulta de sesiones al HistoryRepository.
///
/// S4.1: Retorna lista de sesiones desde el repositorio.
/// S4.2: Retorna Left con Failure cuando el repositorio falla.
void main() {
  late MockHistoryRepository mockRepo;
  late GetScanSessions useCase;

  setUp(() {
    mockRepo = MockHistoryRepository();
    useCase = GetScanSessions(mockRepo);
  });

  final testSessions = [
    ScanSession(
      id: 1,
      startedAt: DateTime(2026, 6, 19, 10, 0),
      endedAt: DateTime(2026, 6, 19, 10, 5),
      nodeCount: 2,
    ),
    ScanSession(
      id: 2,
      startedAt: DateTime(2026, 6, 18, 15, 0),
      endedAt: null,
      nodeCount: 1,
    ),
  ];

  group('T3.2: GetScanSessions', () {
    test('retorna lista de sesiones cuando el repositorio retorna Right',
        () async {
      when(mockRepo.getSessions())
          .thenAnswer((_) async => Right(testSessions));

      final result = await useCase();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (sessions) => expect(sessions, equals(testSessions)),
      );
      verify(mockRepo.getSessions()).called(1);
    });

    test('retorna lista vacía cuando el repositorio retorna lista vacía',
        () async {
      when(mockRepo.getSessions())
          .thenAnswer((_) async => const Right(<ScanSession>[]));

      final result = await useCase();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (sessions) => expect(sessions, isEmpty),
      );
    });

    test('retorna Left con Failure cuando el repositorio falla', () async {
      when(mockRepo.getSessions()).thenAnswer(
          (_) async => Left(UnexpectedFailure('DB error')));

      final result = await useCase();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<UnexpectedFailure>()),
        (_) => fail('Expected Left, got Right'),
      );
    });
  });
}
