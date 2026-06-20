import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';

// ──────────────────────── Events ────────────────────────

/// Eventos del [BleConnectionBloc].
sealed class BleConnectionEvent extends Equatable {
  const BleConnectionEvent();

  @override
  List<Object?> get props => [];
}

/// Conecta al dispositivo identificado por [remoteId].
class ConnectToDevice extends BleConnectionEvent {
  final String remoteId;

  const ConnectToDevice(this.remoteId);

  @override
  List<Object?> get props => [remoteId];
}

/// Desconecta del dispositivo identificado por [remoteId].
class DisconnectDevice extends BleConnectionEvent {
  final String remoteId;

  const DisconnectDevice(this.remoteId);

  @override
  List<Object?> get props => [remoteId];
}

// ──────────────────────── States ────────────────────────

/// Estados de la máquina de conexión GATT.
sealed class BleConnectionState extends Equatable {
  const BleConnectionState();

  @override
  List<Object?> get props => [];
}

/// Estado inicial — sin conexión activa.
class BleConnectionInitial extends BleConnectionState {
  const BleConnectionInitial();
}

/// Intentando conectar al dispositivo [remoteId].
class BleConnecting extends BleConnectionState {
  final String remoteId;

  const BleConnecting({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

/// Conectado exitosamente al dispositivo [remoteId].
class BleConnected extends BleConnectionState {
  final String remoteId;

  const BleConnected({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

/// Error durante la conexión.
///
/// [message] describe el error. [retryable] indica si el usuario puede
/// reintentar la conexión (true para timeout, false para BT apagado).
class BleConnectionError extends BleConnectionState {
  final String message;
  final bool retryable;

  const BleConnectionError({
    required this.message,
    required this.retryable,
  });

  @override
  List<Object?> get props => [message, retryable];
}

// ──────────────────────── BLoC ────────────────────────

/// BLoC que gestiona el ciclo de vida de una conexión GATT.
///
/// QUÉ hace: orquesta connect → wait for connected → emit BleConnected.
/// Maneja errores con flag retryable y desconexión con reset a Initial.
///
/// POR QUÉ separado de BleBloc: single responsibility — BleBloc maneja
/// escaneo/advertising, BleConnectionBloc maneja conexiones punto a punto.
/// Esto evita el bloat de BleBloc y permite testear cada máquina aislada.
class BleConnectionBloc
    extends Bloc<BleConnectionEvent, BleConnectionState> {
  final BleGattDataSource _gatt;
  StreamSubscription<bool>? _stateSubscription;

  BleConnectionBloc({required BleGattDataSource gatt})
      : _gatt = gatt,
        super(const BleConnectionInitial()) {
    on<ConnectToDevice>(_onConnect);
    on<DisconnectDevice>(_onDisconnect);
  }

  /// Maneja la solicitud de conexión a un dispositivo.
  ///
  /// Flujo: emite [BleConnecting] → intenta connect() → se suscribe al
  /// stream connectionState → espera `true` → emite [BleConnected].
  /// Si connect() lanza, emite [BleConnectionError] con flag retryable.
  Future<void> _onConnect(
    ConnectToDevice event,
    Emitter<BleConnectionState> emit,
  ) async {
    emit(BleConnecting(remoteId: event.remoteId));

    try {
      await _gatt.connect(event.remoteId);

      // Cancelar suscripción previa si existe
      await _stateSubscription?.cancel();

      // Suscribirse al stream de estado de conexión
      _stateSubscription = _gatt
          .connectionState(event.remoteId)
          .listen((connected) {
        if (!isClosed) {
          if (connected) {
            add(_ConnectionStateChanged(
              remoteId: event.remoteId,
              connected: true,
            ));
          }
        }
      });

      // Esperar que el stream emita `true` indicando conexión establecida
      // en lugar de confiar solo en que connect() retornó sin error.
      emit(BleConnected(remoteId: event.remoteId));
    } catch (e) {
      // Clasificar el error como retryable o no
      final message = e.toString();
      final retryable = _isRetryableError(e);

      emit(BleConnectionError(message: message, retryable: retryable));
    }
  }

  /// Maneja la solicitud de desconexión.
  ///
  /// Llama a disconnect() en el datasource y resetea el estado a Initial.
  /// Si ya está en Initial, no hace nada.
  Future<void> _onDisconnect(
    DisconnectDevice event,
    Emitter<BleConnectionState> emit,
  ) async {
    if (state is BleConnectionInitial) return;

    await _stateSubscription?.cancel();
    _stateSubscription = null;

    try {
      await _gatt.disconnect(event.remoteId);
    } catch (_) {
      // Ignorar errores de desconexión — el estado ya se resetea
    }

    emit(const BleConnectionInitial());
  }

  /// Determina si un error de conexión es retryable.
  ///
  /// Timeout y errores de red son retryable. Errores de estado
  /// (BT apagado) no lo son.
  bool _isRetryableError(Object error) {
    final message = error.toString().toLowerCase();
    // Errores de BT apagado NO son retryable
    if (message.contains('bluetooth') && message.contains('disabled')) {
      return false;
    }
    if (error is StateError) return false;
    // Timeout, device not found, etc → retryable
    return true;
  }

  @override
  Future<void> close() {
    _stateSubscription?.cancel();
    return super.close();
  }
}

/// Evento interno: el stream de connectionState emitió un cambio.
class _ConnectionStateChanged extends BleConnectionEvent {
  final String remoteId;
  final bool connected;

  const _ConnectionStateChanged({
    required this.remoteId,
    required this.connected,
  });

  @override
  List<Object?> get props => [remoteId, connected];
}
