import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/bloc/history_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/pages/stats_tab.dart';

@GenerateNiceMocks([MockSpec<HistoryBloc>()])
import 'stats_tab_test.mocks.dart';

/// T3.6: Widget tests para StatsTab — tarjetas con totales de sesiones,
/// nodos únicos, duración promedio y nodo más frecuente.
///
/// S5.1: 10 sesiones con 5 nodos únicos → cards muestran valores correctos.
/// S5.2: 0 sesiones → cards muestran cero con mensaje apropiado.
void main() {
  late MockHistoryBloc mockBloc;

  final testStats = HistoryStats(
    totalSessions: 10,
    uniqueNodes: 5,
    averageDuration: const Duration(minutes: 8),
    mostFrequentNodeName: 'Nodo Alpha',
  );

  setUp(() {
    mockBloc = MockHistoryBloc();
  });

  Widget buildTab() {
    return MaterialApp(
      home: Scaffold(
        body: BlocProvider<HistoryBloc>.value(
          value: mockBloc,
          child: const StatsTab(),
        ),
      ),
    );
  }

  group('T3.6: StatsTab', () {
    testWidgets('muestra tarjeta de Total sesiones con el número',
        (tester) async {
      when(mockBloc.state).thenReturn(
        HistoryLoaded(
          sessions: const [],
          stats: testStats,
          filters: const HistoryFilters(),
        ),
      );
      when(mockBloc.stream).thenAnswer(
        (_) => Stream.value(HistoryLoaded(
          sessions: const [],
          stats: testStats,
          filters: const HistoryFilters(),
        )),
      );

      await tester.pumpWidget(buildTab());
      await tester.pump();

      // Verifica que se muestran los textos de las tarjetas
      expect(find.text('Total sesiones'), findsOneWidget);
      expect(find.text('10'), findsOneWidget); // totalSessions
    });

    testWidgets('muestra Nodos únicos con el número de nodos distintos',
        (tester) async {
      when(mockBloc.state).thenReturn(
        HistoryLoaded(
          sessions: const [],
          stats: testStats,
          filters: const HistoryFilters(),
        ),
      );
      when(mockBloc.stream).thenAnswer(
        (_) => Stream.value(HistoryLoaded(
          sessions: const [],
          stats: testStats,
          filters: const HistoryFilters(),
        )),
      );

      await tester.pumpWidget(buildTab());
      await tester.pump();

      expect(find.text('Nodos únicos'), findsOneWidget);
      expect(find.text('5'), findsOneWidget); // uniqueNodes
    });

    testWidgets('muestra Duración promedio formateada en minutos',
        (tester) async {
      when(mockBloc.state).thenReturn(
        HistoryLoaded(
          sessions: const [],
          stats: testStats,
          filters: const HistoryFilters(),
        ),
      );
      when(mockBloc.stream).thenAnswer(
        (_) => Stream.value(HistoryLoaded(
          sessions: const [],
          stats: testStats,
          filters: const HistoryFilters(),
        )),
      );

      await tester.pumpWidget(buildTab());
      await tester.pump();

      expect(find.text('Duración promedio'), findsOneWidget);
      expect(find.text('8 min'), findsOneWidget);
    });

    testWidgets('muestra Nodo más frecuente con su nombre', (tester) async {
      when(mockBloc.state).thenReturn(
        HistoryLoaded(
          sessions: const [],
          stats: testStats,
          filters: const HistoryFilters(),
        ),
      );
      when(mockBloc.stream).thenAnswer(
        (_) => Stream.value(HistoryLoaded(
          sessions: const [],
          stats: testStats,
          filters: const HistoryFilters(),
        )),
      );

      await tester.pumpWidget(buildTab());
      await tester.pump();

      expect(find.text('Nodo más frecuente'), findsOneWidget);
      expect(find.text('Nodo Alpha'), findsOneWidget);
    });

    // ── S5.2: cero sesiones ──
    testWidgets('muestra cero y "Desconocido" cuando no hay datos',
        (tester) async {
      when(mockBloc.state).thenReturn(
        const HistoryLoaded(
          sessions: [],
          stats: HistoryStats(
            totalSessions: 0,
            uniqueNodes: 0,
            averageDuration: Duration.zero,
            mostFrequentNodeName: null,
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
            mostFrequentNodeName: null,
          ),
          filters: HistoryFilters(),
        )),
      );

      await tester.pumpWidget(buildTab());
      await tester.pump();

      expect(find.text('0'), findsWidgets); // total + únicos = 0
      expect(find.text('Desconocido'), findsOneWidget);
    });
  });
}
