import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/scan_session.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/bloc/history_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/pages/history_tab.dart';

@GenerateNiceMocks([MockSpec<HistoryBloc>()])
import 'history_tab_test.mocks.dart';

/// T3.4: Widget tests para HistoryTab — lista de sesiones con tarjetas
/// que muestran fecha, duración y conteo de nodos.
///
/// T3.7: Date filter chips — Hoy, 7 días, 30 días, Todo.
/// T3.8: Name search filter — TextField de búsqueda.
void main() {
  late MockHistoryBloc mockBloc;

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
    totalSessions: 2,
    uniqueNodes: 3,
    averageDuration: const Duration(minutes: 5),
    mostFrequentNodeName: 'Node X',
  );

  setUp(() {
    mockBloc = MockHistoryBloc();
  });

  Widget buildTab() {
    return MaterialApp(
      home: Scaffold(
        body: BlocProvider<HistoryBloc>.value(
          value: mockBloc,
          child: const HistoryTab(),
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T3.4: History tab UI — sesiones
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('T3.4: HistoryTab lista de sesiones', () {
    testWidgets('muestra sesiones con fecha, duración y conteo de nodos',
        (tester) async {
      when(mockBloc.state).thenReturn(
        HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
        ),
      );
      when(mockBloc.stream).thenAnswer(
        (_) => Stream.value(HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
        )),
      );

      await tester.pumpWidget(buildTab());
      await tester.pump();

      // Verifica que se muestran las fechas de las sesiones
      // Formato: "dd/MM/yy HH:mm" o similar
      expect(find.textContaining('19/06'), findsWidgets);

      // Verifica el conteo de nodos: "2 nodos" y "1 nodo"
      expect(find.text('2 nodos'), findsOneWidget);
      expect(find.text('1 nodo'), findsOneWidget);
    });

    testWidgets('muestra estado vacío cuando no hay sesiones', (tester) async {
      when(mockBloc.state).thenReturn(
        const HistoryLoaded(
          sessions: [],
          stats: HistoryStats(
            totalSessions: 0,
            uniqueNodes: 0,
            averageDuration: Duration.zero,
          ),
          filters: HistoryFilters(),
        ),
      );
      when(mockBloc.stream).thenAnswer(
        (_) => Stream.value(const HistoryLoaded(
          sessions: [],
          stats: HistoryStats(
            totalSessions: 0,
            uniqueNodes: 0,
            averageDuration: Duration.zero,
          ),
          filters: HistoryFilters(),
        )),
      );

      await tester.pumpWidget(buildTab());
      await tester.pump();

      expect(find.text('Sin sesiones'), findsOneWidget);
    });

    testWidgets('muestra indicador de carga en HistoryLoading', (tester) async {
      when(mockBloc.state).thenReturn(const HistoryLoading());
      when(mockBloc.stream)
          .thenAnswer((_) => Stream.value(const HistoryLoading()));

      await tester.pumpWidget(buildTab());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T3.7: Date filter chips
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('T3.7: Date filter chips', () {
    testWidgets('muestra chips de filtro: Hoy, 7 días, 30 días, Todo',
        (tester) async {
      when(mockBloc.state).thenReturn(
        HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
        ),
      );
      when(mockBloc.stream).thenAnswer(
        (_) => Stream.value(HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
        )),
      );

      await tester.pumpWidget(buildTab());
      await tester.pump();

      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('7 días'), findsOneWidget);
      expect(find.text('30 días'), findsOneWidget);
      expect(find.text('Todo'), findsOneWidget);
    });

    testWidgets('tap en chip "Hoy" despacha FilterByDate(DateRange.today)',
        (tester) async {
      when(mockBloc.state).thenReturn(
        HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
        ),
      );
      when(mockBloc.stream).thenAnswer(
        (_) => Stream.value(HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
        )),
      );

      await tester.pumpWidget(buildTab());
      await tester.pump();

      await tester.tap(find.text('Hoy'));
      await tester.pump();

      verify(mockBloc.add(const FilterByDate(DateRange.today))).called(1);
    });
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T3.8: Name search filter
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('T3.8: Name search filter', () {
    testWidgets('muestra campo de búsqueda por nombre', (tester) async {
      when(mockBloc.state).thenReturn(
        HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
        ),
      );
      when(mockBloc.stream).thenAnswer(
        (_) => Stream.value(HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
        )),
      );

      await tester.pumpWidget(buildTab());
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('escribir en TextField despacha FilterByName', (tester) async {
      when(mockBloc.state).thenReturn(
        HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
        ),
      );
      when(mockBloc.stream).thenAnswer(
        (_) => Stream.value(HistoryLoaded(
          sessions: testSessions,
          stats: testStats,
          filters: const HistoryFilters(),
        )),
      );

      await tester.pumpWidget(buildTab());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Nodo A');
      await tester.pump();

      verify(mockBloc.add(const FilterByName(query: 'Nodo A'))).called(1);
    });
  });
}
