import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/scan_session.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/session_node.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_scan_sessions.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_session_detail.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/bloc/history_bloc.dart';

@GenerateNiceMocks([
  MockSpec<GetScanSessions>(),
  MockSpec<GetSessionDetail>(),
  MockSpec<GetHistoryStats>(),
])
import 'history_bloc_test.mocks.dart';

/// T3.1: Tests para HistoryBloc — orquesta carga de sesiones, detalle,
/// filtros por fecha y nombre, y estadísticas.
///
/// Estados: HistoryInitial, HistoryLoading, HistoryLoaded, HistoryError.
/// Eventos: LoadHistory, SelectSession, FilterByDate, FilterByName.
void main() {
  late MockGetScanSessions mockGetSessions;
  late MockGetSessionDetail mockGetDetail;
  late MockGetHistoryStats mockGetStats;

  final now = DateTime(2026, 6, 19, 10, 0);
  final testSessions = [
    ScanSession(
      id: 1,
      startedAt: now,
      endedAt: now.add(const Duration(minutes: 5)),
      nodeCount: 2,
    ),
    ScanSession(
      id: 2,
      startedAt: now.subtract(const Duration(hours: 1)),
      endedAt: null,
      nodeCount: 1,
    ),
  ];

  final testStats = HistoryStats(
    totalSessions: 5,
    uniqueNodes: 3,
    averageDuration: const Duration(minutes: 10),
    mostFrequentNodeName: 'Nodo Alpha',
  );

  setUp(() {
    mockGetSessions = MockGetScanSessions();
    mockGetDetail = MockGetSessionDetail();
    mockGetStats = MockGetHistoryStats();
  });

  HistoryBloc buildBloc() => HistoryBloc(
        getScanSessions: mockGetSessions,
        getSessionDetail: mockGetDetail,
        getHistoryStats: mockGetStats,
      );

  group('T3.1: HistoryBloc estados iniciales', () {
    test('estado inicial es HistoryInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, const HistoryInitial());
    });
  });

  group('T3.1: LoadHistory', () {
    blocTest<HistoryBloc, HistoryState>(
      'emite [HistoryLoading, HistoryLoaded] al cargar datos exitosamente',
      build: () {
        when(mockGetSessions.call())
            .thenAnswer((_) async => Right(testSessions));
        when(mockGetStats.call())
            .thenAnswer((_) async => Right(testStats));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const LoadHistory()),
      expect: () => [
        const HistoryLoading(),
        HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
        ),
      ],
    );

    blocTest<HistoryBloc, HistoryState>(
      'emite [HistoryLoading, HistoryError] si getScanSessions falla',
      build: () {
        when(mockGetSessions.call()).thenAnswer(
            (_) async => Left(UnexpectedFailure('DB error')));
        when(mockGetStats.call())
            .thenAnswer((_) async => Right(testStats));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const LoadHistory()),
      expect: () => [
        const HistoryLoading(),
        const HistoryError('Error al cargar sesiones: DB error'),
      ],
    );

    blocTest<HistoryBloc, HistoryState>(
      'emite [HistoryLoading, HistoryError] si getHistoryStats falla',
      build: () {
        when(mockGetSessions.call())
            .thenAnswer((_) async => Right(testSessions));
        when(mockGetStats.call()).thenAnswer(
            (_) async => Left(UnexpectedFailure('Stats error')));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const LoadHistory()),
      expect: () => [
        const HistoryLoading(),
        const HistoryError('Error al cargar sesiones: Stats error'),
      ],
    );
  });

  group('T3.1: SelectSession', () {
    blocTest<HistoryBloc, HistoryState>(
      'emite HistoryLoaded con detailNodes al seleccionar sesión',
      build: () {
        when(mockGetSessions.call())
            .thenAnswer((_) async => Right(testSessions));
        when(mockGetStats.call())
            .thenAnswer((_) async => Right(testStats));
        // Mockear getSessionDetail para que retorne datos vacíos
        when(mockGetDetail.call(any))
            .thenAnswer((_) async => const Right(<SessionNode>[]));
        return buildBloc();
      },
      seed: () => HistoryLoaded(
        sessions: testSessions,
        stats: testStats,
        filters: const HistoryFilters(),
      ),
      act: (bloc) => bloc.add(const SelectSession(sessionId: 1)),
      // T-PR1-012 actualizó _onSelectSession para emitir HistoryLoading primero.
      // El test ahora espera ambas emisiones.
      expect: () => [
        isA<HistoryLoading>(),
        HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
          detailNodes: [],
          selectedSessionId: 1,
        ),
      ],
    );

    // ─── T-PR1-011 RED: SelectSession emite loading ────────────
    // QUÉ: verifica que SelectSession emite HistoryLoading antes de
    // HistoryLoaded, para que la UI muestre un indicador de progreso
    // mientras se carga el detalle de la sesión.
    // POR QUÉ: actualmente _onSelectSession no emite loading. Si el
    // detalle tarda en cargar (muchos nodos en sesión), la UI no
    // muestra feedback y el usuario cree que la app está trabada.
    // En RED: el test falla porque HistoryLoading no está en la secuencia.

    blocTest<HistoryBloc, HistoryState>(
      'T-PR1-011 RED: SelectSession emite HistoryLoading antes del resultado cargado',
      build: () {
        // Forzar un delay en getSessionDetail para simular carga lenta
        when(mockGetDetail.call(any)).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return const Right(<SessionNode>[]);
        });
        return buildBloc();
      },
      seed: () => HistoryLoaded(
        sessions: testSessions,
        stats: testStats,
        filters: const HistoryFilters(),
      ),
      act: (bloc) => bloc.add(const SelectSession(sessionId: 1)),
      // wait asegura que el Future.delayed(50ms) en el mock se resuelva
      // y el BLoC emita HistoryLoaded después de HistoryLoading.
      wait: const Duration(milliseconds: 200),
      expect: () => [
        isA<HistoryLoading>(),
        isA<HistoryLoaded>().having(
          (s) => s.selectedSessionId,
          'selectedSessionId',
          1,
        ),
      ],
    );
  });

  group('T3.7: FilterByDate', () {
    blocTest<HistoryBloc, HistoryState>(
      'emite HistoryLoaded con filtro de fecha aplicado',
      build: () {
        when(mockGetSessions.call())
            .thenAnswer((_) async => Right(testSessions));
        when(mockGetStats.call())
            .thenAnswer((_) async => Right(testStats));
        when(mockGetDetail.call(any))
            .thenAnswer((_) async => const Right(<SessionNode>[]));
        return buildBloc();
      },
      seed: () => HistoryLoaded(
        sessions: testSessions,
        stats: testStats,
        filters: const HistoryFilters(),
      ),
      act: (bloc) => bloc.add(const FilterByDate(DateRange.today)),
      expect: () => [
        HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(dateRange: DateRange.today),
        ),
      ],
    );

    blocTest<HistoryBloc, HistoryState>(
      'filtro last7Days actualiza la fecha en HistoryFilters',
      build: () {
        when(mockGetSessions.call())
            .thenAnswer((_) async => Right(testSessions));
        when(mockGetStats.call())
            .thenAnswer((_) async => Right(testStats));
        when(mockGetDetail.call(any))
            .thenAnswer((_) async => const Right(<SessionNode>[]));
        return buildBloc();
      },
      seed: () => HistoryLoaded(
        sessions: testSessions,
        stats: testStats,
        filters: const HistoryFilters(),
      ),
      act: (bloc) => bloc.add(const FilterByDate(DateRange.last7Days)),
      expect: () => [
        HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(dateRange: DateRange.last7Days),
        ),
      ],
    );
  });

  group('T3.8: FilterByName', () {
    blocTest<HistoryBloc, HistoryState>(
      'emite HistoryLoaded con nameQuery aplicado',
      build: () {
        when(mockGetSessions.call())
            .thenAnswer((_) async => Right(testSessions));
        when(mockGetStats.call())
            .thenAnswer((_) async => Right(testStats));
        when(mockGetDetail.call(any))
            .thenAnswer((_) async => const Right(<SessionNode>[]));
        return buildBloc();
      },
      seed: () => HistoryLoaded(
        sessions: testSessions,
        stats: testStats,
        filters: const HistoryFilters(),
      ),
      act: (bloc) => bloc.add(const FilterByName(query: 'Nodo A')),
      expect: () => [
        HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(nameQuery: 'Nodo A'),
        ),
      ],
    );

    blocTest<HistoryBloc, HistoryState>(
      'nameQuery vacío limpia el filtro de nombre',
      build: () {
        when(mockGetSessions.call())
            .thenAnswer((_) async => Right(testSessions));
        when(mockGetStats.call())
            .thenAnswer((_) async => Right(testStats));
        when(mockGetDetail.call(any))
            .thenAnswer((_) async => const Right(<SessionNode>[]));
        return buildBloc();
      },
      seed: () => HistoryLoaded(
        sessions: testSessions,
        stats: testStats,
        filters: const HistoryFilters(nameQuery: 'prev'),
      ),
      act: (bloc) => bloc.add(const FilterByName(query: '')),
      expect: () => [
        HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(nameQuery: ''),
        ),
      ],
    );
  });
}
