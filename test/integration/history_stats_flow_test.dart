import 'package:drift/drift.dart' hide Column;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/history/data/datasources/history_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/history/data/repositories/history_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_scan_sessions.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_session_detail.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/bloc/history_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/data/datasources/scan_session_drift_datasource.dart';

void main() {
  test(
    'scan session → persistence → HistoryBloc exposes sessions, detail and stats',
    () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final now = DateTime(2026, 6, 19, 10);
      final nodeId = await db
          .into(db.nodes)
          .insert(
            NodesCompanion(
              name: const Value('Nodo histórico'),
              bleAddress: const Value('history-flow-node'),
              firstSeen: Value(now),
              lastSeen: Value(now),
            ),
          );
      final scanRepo = ScanSessionRepositoryImpl(db);
      final sessionId = await scanRepo.startSession();
      await scanRepo.addNodesToSession(
        sessionId,
        [nodeId],
        rssiByNode: {nodeId: -62},
      );
      await scanRepo.endSession(sessionId);

      final historyRepo = HistoryRepositoryImpl(HistoryDriftDataSource(db));
      final bloc = HistoryBloc(
        getScanSessions: GetScanSessions(historyRepo),
        getSessionDetail: GetSessionDetail(historyRepo),
        getHistoryStats: GetHistoryStats(historyRepo),
      );
      addTearDown(bloc.close);
      bloc.add(const LoadHistory());
      final state = await bloc.stream.firstWhere(
        (state) => state is HistoryLoaded,
      );
      final loaded = state as HistoryLoaded;

      expect(loaded.sessions.single.id, sessionId);
      expect(loaded.sessions.single.nodeCount, 1);
      expect(loaded.stats.totalSessions, 1);

      bloc.add(SelectSession(sessionId: sessionId));
      final detailState =
          await bloc.stream.firstWhere(
                (state) =>
                    state is HistoryLoaded &&
                    state.selectedSessionId == sessionId,
              )
              as HistoryLoaded;
      expect(detailState.detailNodes.single.rssi, -62);
      expect(detailState.detailNodes.single.proximityLevel, 'close');
    },
  );
}
