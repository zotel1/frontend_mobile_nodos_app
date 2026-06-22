import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/scan_session.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/session_node.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_scan_sessions.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_session_detail.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_history_stats.dart';

// ── Events ──

abstract class HistoryEvent extends Equatable {
  const HistoryEvent();

  @override
  List<Object?> get props => [];
}

/// Carga sesiones y estadísticas desde la base de datos.
class LoadHistory extends HistoryEvent {
  const LoadHistory();
}

/// Selecciona una sesión para ver su detalle de nodos detectados.
class SelectSession extends HistoryEvent {
  final int sessionId;

  const SelectSession({required this.sessionId});

  @override
  List<Object> get props => [sessionId];
}

/// Filtra sesiones por rango de fechas.
class FilterByDate extends HistoryEvent {
  final DateRange range;

  const FilterByDate(this.range);

  @override
  List<Object> get props => [range];
}

/// Filtra sesiones por nombre de nodo detectado.
class FilterByName extends HistoryEvent {
  final String query;

  const FilterByName({required this.query});

  @override
  List<Object> get props => [query];
}

// ── Date Range ──

/// Rangos de fecha para filtrar sesiones desde la UI.
enum DateRange { today, last7Days, last30Days, all }

// ── States ──

abstract class HistoryState extends Equatable {
  const HistoryState();

  @override
  List<Object?> get props => [];
}

class HistoryInitial extends HistoryState {
  const HistoryInitial();
}

class HistoryLoading extends HistoryState {
  const HistoryLoading();
}

class HistoryLoaded extends HistoryState {
  final List<ScanSession> sessions;
  final HistoryStats stats;
  final HistoryFilters filters;
  final List<SessionNode> detailNodes;
  final int? selectedSessionId;

  const HistoryLoaded({
    required this.sessions,
    required this.stats,
    required this.filters,
    this.detailNodes = const [],
    this.selectedSessionId,
  });

  @override
  List<Object?> get props => [
        sessions,
        stats,
        filters,
        detailNodes,
        selectedSessionId,
      ];
}

class HistoryError extends HistoryState {
  final String message;

  const HistoryError(this.message);

  @override
  List<Object> get props => [message];
}

// ── Filters ──

/// Filtros activos en la vista de historial.
class HistoryFilters extends Equatable {
  final DateRange dateRange;
  final String? nameQuery;

  const HistoryFilters({
    this.dateRange = DateRange.all,
    this.nameQuery,
  });

  HistoryFilters copyWith({DateRange? dateRange, String? nameQuery}) {
    return HistoryFilters(
      dateRange: dateRange ?? this.dateRange,
      nameQuery: nameQuery ?? this.nameQuery,
    );
  }

  @override
  List<Object?> get props => [dateRange, nameQuery];
}

// ── BLoC ──

/// BLoC que gestiona el historial de sesiones de escaneo y estadísticas.
///
/// Responsabilidades:
/// - Cargar sesiones de escaneo (LoadHistory) y estadísticas agregadas.
/// - Seleccionar una sesión para ver detalle de nodos (SelectSession).
/// - Aplicar filtros por fecha y nombre (FilterByDate, FilterByName).
///
/// Dependencias:
/// - [GetScanSessions]: consulta todas las sesiones ordenadas por fecha.
/// - [GetSessionDetail]: consulta nodos de una sesión con RSSI.
/// - [GetHistoryStats]: calcula estadísticas agregadas.
///
/// POR QUÉ: separa la lógica de presentación del historial de la UI.
/// Los filtros se aplican en el BLoC para mantener el estado coherente
/// y permitir que los widgets reaccionen a cambios de estado.
class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  final GetScanSessions getScanSessions;
  final GetSessionDetail getSessionDetail;
  final GetHistoryStats getHistoryStats;

  HistoryBloc({
    required this.getScanSessions,
    required this.getSessionDetail,
    required this.getHistoryStats,
  }) : super(const HistoryInitial()) {
    on<LoadHistory>(_onLoadHistory);
    on<SelectSession>(_onSelectSession);
    on<FilterByDate>(_onFilterByDate);
    on<FilterByName>(_onFilterByName);
  }

  Future<void> _onLoadHistory(
      LoadHistory event, Emitter<HistoryState> emit) async {
    emit(const HistoryLoading());

    // Cargar sesiones y estadísticas en paralelo (ambas son queries
    // independientes de solo lectura).
    final sessionsResult = await getScanSessions();
    final statsResult = await getHistoryStats();

    // Si cualquiera de las dos consultas falla, emitir error.
    if (sessionsResult.isLeft()) {
      sessionsResult.fold(
        (failure) => emit(HistoryError('Error al cargar sesiones: ${failure.message}')),
        (_) {},
      );
      return;
    }
    if (statsResult.isLeft()) {
      statsResult.fold(
        (failure) => emit(HistoryError('Error al cargar sesiones: ${failure.message}')),
        (_) {},
      );
      return;
    }

    // Ambas consultas exitosas
    final sessions = sessionsResult.getOrElse(() => <ScanSession>[]);
    final stats = statsResult.getOrElse(
      () => const HistoryStats(
        totalSessions: 0,
        uniqueNodes: 0,
        averageDuration: Duration.zero,
      ),
    );

    emit(HistoryLoaded(
      sessions: sessions,
      stats: stats,
      filters: const HistoryFilters(),
    ));
  }

  Future<void> _onSelectSession(
      SelectSession event, Emitter<HistoryState> emit) async {
    final currentState = state;
    if (currentState is! HistoryLoaded) return;

    // T-PR1-012: Guardar los datos del estado actual ANTES de emitir loading,
    // porque después de emitir loading, currentState ya no es HistoryLoaded
    // y no podemos llamar copyWith() sobre él.
    final previousSessions = currentState.sessions;
    final previousStats = currentState.stats;
    final previousFilters = currentState.filters;

    // Emitir loading para que la UI muestre spinner mientras carga el detalle.
    emit(const HistoryLoading());

    final result = await getSessionDetail(
      GetSessionDetailParams(sessionId: event.sessionId),
    );

    final detailNodes = result.fold(
      (_) => <SessionNode>[],
      (nodes) => nodes,
    );

    emit(HistoryLoaded(
      sessions: previousSessions,
      stats: previousStats,
      filters: previousFilters,
      detailNodes: detailNodes,
      selectedSessionId: event.sessionId,
    ));
  }

  void _onFilterByDate(FilterByDate event, Emitter<HistoryState> emit) {
    final currentState = state;
    if (currentState is! HistoryLoaded) return;

    emit(currentState.copyWith(
      filters: currentState.filters.copyWith(dateRange: event.range),
    ));
  }

  void _onFilterByName(FilterByName event, Emitter<HistoryState> emit) {
    final currentState = state;
    if (currentState is! HistoryLoaded) return;

    emit(currentState.copyWith(
      filters: currentState.filters.copyWith(nameQuery: event.query),
    ));
  }
}

// ── Extension on HistoryLoaded ──

extension _HistoryLoadedCopy on HistoryLoaded {
  HistoryLoaded copyWith({
    List<ScanSession>? sessions,
    HistoryStats? stats,
    HistoryFilters? filters,
    List<SessionNode>? detailNodes,
    int? selectedSessionId,
    bool clearDetail = false,
  }) {
    return HistoryLoaded(
      sessions: sessions ?? this.sessions,
      stats: stats ?? this.stats,
      filters: filters ?? this.filters,
      detailNodes: clearDetail ? [] : (detailNodes ?? this.detailNodes),
      selectedSessionId:
          clearDetail ? null : (selectedSessionId ?? this.selectedSessionId),
    );
  }
}
