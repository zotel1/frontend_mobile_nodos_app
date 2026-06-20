import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/domain/repositories/scan_session_repository.dart';

// ── Eventos ──────────────────────────────────────────────────────

/// Eventos para el [ScanSessionBloc].
///
/// QUÉ: cada evento representa una intención del sistema sobre el
/// ciclo de vida de una sesión de escaneo BLE.
abstract class ScanSessionEvent extends Equatable {
  const ScanSessionEvent();

  @override
  List<Object?> get props => [];
}

/// Inicia una nueva sesión de escaneo.
///
/// Se despacha cuando [BleBloc] comienza a escanear (StartScan).
/// Crea una fila en scan_sessions con startedAt = now().
class StartSession extends ScanSessionEvent {
  const StartSession();
}

/// Finaliza la sesión de escaneo activa.
///
/// Se despacha cuando el escaneo se detiene (StopScan, BT off,
/// cambio de tab). Establece endedAt = now() en la sesión.
class EndSession extends ScanSessionEvent {
  final int sessionId;

  const EndSession(this.sessionId);

  @override
  List<Object> get props => [sessionId];
}

/// Registra nodos detectados en la sesión activa.
///
/// Se despacha cuando [NodeListBloc] emite [NodeListLoaded] con
/// nuevos nodos. Asocia los nodeIds a la sesión en scan_session_nodes.
class AddNodesToSession extends ScanSessionEvent {
  final int sessionId;
  final List<int> nodeIds;

  const AddNodesToSession(this.sessionId, this.nodeIds);

  @override
  List<Object> get props => [sessionId, nodeIds];
}

// ── Estados ──────────────────────────────────────────────────────

/// Estados del [ScanSessionBloc].
///
/// QUÉ: representan el ciclo de vida de una sesión de escaneo
/// desde la creación hasta el cierre o error.
abstract class ScanSessionState extends Equatable {
  const ScanSessionState();

  @override
  List<Object?> get props => [];
}

/// Estado inicial: no hay sesión activa.
class SessionInitial extends ScanSessionState {
  const SessionInitial();
}

/// Hay una sesión de escaneo activa con nodos siendo detectados.
class SessionActive extends ScanSessionState {
  final int sessionId;
  final int nodeCount;

  const SessionActive({required this.sessionId, required this.nodeCount});

  @override
  List<Object> get props => [sessionId, nodeCount];
}

/// La sesión de escaneo fue finalizada correctamente.
class SessionEnded extends ScanSessionState {
  const SessionEnded();
}

/// Ocurrió un error al gestionar la sesión.
class SessionError extends ScanSessionState {
  final String message;

  const SessionError(this.message);

  @override
  List<Object> get props => [message];
}

// ── BLoC ─────────────────────────────────────────────────────────

/// BLoC que orquesta el ciclo de vida de las sesiones de escaneo BLE.
///
/// Responsabilidades:
/// - Recibir [StartSession] para crear una nueva sesión en la BD.
/// - Recibir [EndSession] para cerrar la sesión activa con endedAt.
/// - Recibir [AddNodesToSession] para registrar nodos en la sesión.
///
/// QUÉ resuelve: antes, la creación de sesiones estaba en HomePage
/// (_triggerGraphBuild) con acceso directo a AppDatabase, violando
/// Clean Architecture. Ahora el ciclo de vida de sesiones está
/// encapsulado en un BLoC dedicado que delega al repositorio.
///
/// POR QUÉ: separar la lógica de sesiones del widget HomePage
/// permite testear el ciclo de vida de sesión aisladamente y
/// respeta Single Responsibility Principle.
class ScanSessionBloc extends Bloc<ScanSessionEvent, ScanSessionState> {
  final ScanSessionRepository _repository;

  ScanSessionBloc({required ScanSessionRepository repository})
      : _repository = repository,
        super(const SessionInitial()) {
    on<StartSession>(_onStartSession);
    on<EndSession>(_onEndSession);
    on<AddNodesToSession>(_onAddNodesToSession);
  }

  /// Crea una nueva sesión de escaneo con timestamp actual.
  Future<void> _onStartSession(
    StartSession event,
    Emitter<ScanSessionState> emit,
  ) async {
    try {
      final sessionId = await _repository.startSession();
      emit(SessionActive(sessionId: sessionId, nodeCount: 0));
    } catch (e) {
      emit(SessionError('Error al iniciar sesión: $e'));
    }
  }

  /// Cierra la sesión activa estableciendo endedAt = now().
  Future<void> _onEndSession(
    EndSession event,
    Emitter<ScanSessionState> emit,
  ) async {
    try {
      await _repository.endSession(event.sessionId);
      emit(const SessionEnded());
    } catch (e) {
      emit(SessionError('Error al cerrar sesión: $e'));
    }
  }

  /// Registra nodos detectados en la sesión activa.
  ///
  /// QUÉ: asocia los nodeIds a la sesión en scan_session_nodes
  /// y actualiza el contador nodeCount en el estado.
  Future<void> _onAddNodesToSession(
    AddNodesToSession event,
    Emitter<ScanSessionState> emit,
  ) async {
    try {
      await _repository.addNodesToSession(event.sessionId, event.nodeIds);

      final currentState = state;
      if (currentState is SessionActive) {
        emit(SessionActive(
          sessionId: currentState.sessionId,
          nodeCount: currentState.nodeCount + event.nodeIds.length,
        ));
      }
    } catch (e) {
      emit(SessionError('Error al agregar nodos: $e'));
    }
  }
}
