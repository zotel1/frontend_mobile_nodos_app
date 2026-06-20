import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/domain/repositories/scan_session_repository.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/presentation/bloc/scan_session_bloc.dart';

@GenerateNiceMocks([MockSpec<ScanSessionRepository>()])
import 'scan_session_bloc_test.mocks.dart';

/// Tests para ScanSessionBloc — ciclo de vida de sesiones de escaneo BLE.
///
/// QUÉ: verifica que el BLoC maneje correctamente StartSession,
/// EndSession, y AddNodesToSession, emitiendo los estados correctos.
///
/// POR QUÉ: el BLoC es el orquestador del ciclo de vida de sesiones.
/// Cada evento debe producir los estados esperados sin errores.
void main() {
  late MockScanSessionRepository mockRepository;

  setUp(() {
    mockRepository = MockScanSessionRepository();
  });

  group('ScanSessionBloc', () {
    blocTest<ScanSessionBloc, ScanSessionState>(
      'estado inicial es SessionInitial',
      build: () => ScanSessionBloc(repository: mockRepository),
      verify: (bloc) => expect(bloc.state, isA<SessionInitial>()),
    );

    blocTest<ScanSessionBloc, ScanSessionState>(
      'StartSession crea sesión y emite SessionActive',
      build: () {
        when(mockRepository.startSession()).thenAnswer((_) async => 42);
        return ScanSessionBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const StartSession()),
      expect: () => [
        isA<SessionActive>()
            .having((s) => s.sessionId, 'sessionId', equals(42))
            .having((s) => s.nodeCount, 'nodeCount', equals(0)),
      ],
      verify: (_) {
        verify(mockRepository.startSession()).called(1);
      },
    );

    blocTest<ScanSessionBloc, ScanSessionState>(
      'EndSession cierra sesión y emite SessionEnded',
      build: () {
        when(mockRepository.endSession(any)).thenAnswer((_) async {});
        return ScanSessionBloc(repository: mockRepository);
      },
      seed: () => const SessionActive(sessionId: 42, nodeCount: 5),
      act: (bloc) => bloc.add(const EndSession(42)),
      expect: () => [
        isA<SessionEnded>(),
      ],
      verify: (_) {
        verify(mockRepository.endSession(42)).called(1);
      },
    );

    blocTest<ScanSessionBloc, ScanSessionState>(
      'AddNodesToSession registra nodos y actualiza nodeCount',
      build: () {
        when(mockRepository.addNodesToSession(any, any))
            .thenAnswer((_) async {});
        return ScanSessionBloc(repository: mockRepository);
      },
      seed: () => const SessionActive(sessionId: 42, nodeCount: 3),
      act: (bloc) => bloc.add(const AddNodesToSession(42, [10, 20, 30])),
      expect: () => [
        isA<SessionActive>()
            .having((s) => s.sessionId, 'sessionId', equals(42))
            .having((s) => s.nodeCount, 'nodeCount', equals(6)),
      ],
      verify: (_) {
        verify(mockRepository.addNodesToSession(42, [10, 20, 30])).called(1);
      },
    );

    blocTest<ScanSessionBloc, ScanSessionState>(
      'StartSession emite SessionError cuando el repositorio falla',
      build: () {
        when(mockRepository.startSession())
            .thenThrow(Exception('DB error'));
        return ScanSessionBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const StartSession()),
      expect: () => [
        isA<SessionError>().having(
          (s) => s.message,
          'message',
          contains('DB error'),
        ),
      ],
    );

    blocTest<ScanSessionBloc, ScanSessionState>(
      'EndSession emite SessionError cuando el repositorio falla',
      build: () {
        when(mockRepository.endSession(any))
            .thenThrow(Exception('Close error'));
        return ScanSessionBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const EndSession(1)),
      expect: () => [
        isA<SessionError>().having(
          (s) => s.message,
          'message',
          contains('Close error'),
        ),
      ],
    );

    blocTest<ScanSessionBloc, ScanSessionState>(
      'AddNodesToSession emite SessionError cuando el repositorio falla',
      build: () {
        when(mockRepository.addNodesToSession(any, any))
            .thenThrow(Exception('Add error'));
        return ScanSessionBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const AddNodesToSession(1, [1, 2])),
      expect: () => [
        isA<SessionError>().having(
          (s) => s.message,
          'message',
          contains('Add error'),
        ),
      ],
    );

    blocTest<ScanSessionBloc, ScanSessionState>(
      'AddNodesToSession sobre SessionInitial emite SessionError',
      build: () {
        when(mockRepository.addNodesToSession(any, any))
            .thenAnswer((_) async {});
        return ScanSessionBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const AddNodesToSession(1, [5])),
      // nodeCount no se actualiza porque no hay SessionActive previo
      expect: () => [],
    );
  });
}
