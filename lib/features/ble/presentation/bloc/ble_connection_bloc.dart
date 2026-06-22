import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:permission_handler/permission_handler.dart';

// ──────────────────────── Events ────────────────────────

/// Eventos del [BleConnectionBloc].
sealed class BleConnectionEvent extends Equatable {
  const BleConnectionEvent();

  @override
  List<Object?> get props => [];
}

/// Conecta al dispositivo identificado por [remoteId].
///
/// [myNodeId] es el ID en la tabla nodes del dispositivo local
/// (el que inicia la conexión). Se usa para insertar la fila
/// en la tabla connections (R5.2).
class ConnectToDevice extends BleConnectionEvent {
  final String remoteId;
  final int myNodeId;

  const ConnectToDevice(this.remoteId, {required this.myNodeId});

  @override
  List<Object> get props => [remoteId, myNodeId];
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

/// Conexión insertada en la tabla connections tras conectar exitosamente.
///
/// Emitido después de [BleConnected], cuando se insertó la fila
/// en la tabla connections (R5.2).
class ConnectionInserted extends BleConnectionState {
  final String remoteId;

  const ConnectionInserted({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

/// Identidad remota cargada exitosamente vía GATT read.
///
/// [remoteId] es la dirección BLE del dispositivo remoto.
/// [name] y [color] son los valores leídos de la característica de identidad.
class RemoteIdentityLoaded extends BleConnectionState {
  final String remoteId;
  final String name;
  final String color;

  const RemoteIdentityLoaded({
    required this.remoteId,
    required this.name,
    required this.color,
  });

  @override
  List<Object?> get props => [remoteId, name, color];
}

/// No se pudo leer la identidad remota vía GATT.
///
/// [remoteId] es la dirección del dispositivo. La UI debe mostrar
/// un bottom sheet para entrada manual de metadatos (R5.5).
class RemoteIdentityUnavailable extends BleConnectionState {
  final String remoteId;

  const RemoteIdentityUnavailable({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

// ──────────────────────── BLoC ────────────────────────

/// BLoC que gestiona el ciclo de vida de una conexión GATT.
///
/// QUÉ hace: orquesta connect → wait for connected → emit BleConnected.
/// Después de conectar, inserta una fila en la tabla connections,
/// intenta leer la identidad remota vía GATT, y emite estados
/// según el resultado (RemoteIdentityLoaded o RemoteIdentityUnavailable).
///
/// POR QUÉ separado de BleBloc: single responsibility — BleBloc maneja
/// escaneo/advertising, BleConnectionBloc maneja conexiones punto a punto.
/// Esto evita el bloat de BleBloc y permite testear cada máquina aislada.
///
/// Depende de [BleConnectionRepository] para operaciones GATT y persistencia,
/// y de [NodeRepository] para lookup de nodeId por bleAddress.
class BleConnectionBloc
    extends Bloc<BleConnectionEvent, BleConnectionState> {
  final BleConnectionRepository _connectionRepo;
  final NodeRepository _nodeRepository;
  StreamSubscription<bool>? _stateSubscription;

  BleConnectionBloc({
    required BleConnectionRepository connectionRepository,
    required NodeRepository nodeRepository,
  })  : _connectionRepo = connectionRepository,
        _nodeRepository = nodeRepository,
        super(const BleConnectionInitial()) {
    on<ConnectToDevice>(_onConnect);
    on<DisconnectDevice>(_onDisconnect);
    on<_ConnectionStateChanged>(_onConnectionStateChanged);
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

    // R5.8: Verificar permiso BLUETOOTH_CONNECT en runtime (Android 12+).
    try {
      final permission = await Permission.bluetoothConnect.request();
      if (!permission.isGranted) {
        emit(const BleConnectionError(
          message: 'Permiso BLUETOOTH_CONNECT requerido',
          retryable: false,
        ));
        return;
      }
    } catch (_) {
      // Entorno sin platform channel (tests, web) — continuar sin verificación
    }

    try {
      await _connectionRepo.connect(event.remoteId);

      // Cancelar suscripción previa si existe
      await _stateSubscription?.cancel();

      // Suscribirse al stream de estado de conexión
      _stateSubscription = _connectionRepo
          .connectionState(event.remoteId)
          .listen((connected) {
        if (!isClosed) {
          add(_ConnectionStateChanged(
            remoteId: event.remoteId,
            connected: connected,
            myNodeId: event.myNodeId,
          ));
        }
      });

      // Emitir BleConnected — la lógica post-conexión ocurre
      // en _onConnectionStateChanged cuando el stream emita true.
      emit(BleConnected(remoteId: event.remoteId));
    } catch (e) {
      final message = e.toString();
      final retryable = _isRetryableError(e);

      emit(BleConnectionError(message: message, retryable: retryable));
    }
  }

  /// Handler interno: ejecuta la lógica post-conexión cuando el stream
  /// de connectionState emite `true` (conexión establecida).
  Future<void> _onConnectionStateChanged(
    _ConnectionStateChanged event,
    Emitter<BleConnectionState> emit,
  ) async {
    if (!event.connected) {
      emit(const BleConnectionInitial());
      return;
    }

    final remoteId = event.remoteId;

    // ── 1. Insertar fila en connections ──
    try {
      final remoteNode =
          await _nodeRepository.getNodeByBleAddress(remoteId);
      if (remoteNode != null && remoteNode.id != null) {
        await _connectionRepo.saveConnection(event.myNodeId, remoteNode.id!);
        emit(ConnectionInserted(remoteId: remoteId));
      }
    } catch (_) {
      // Fallo silencioso: la conexión ya existe (UNIQUE constraint)
      // o el nodo no se encontró. No es crítico para el flujo.
    }

    // ── 2. Intentar GATT identity read ──
    try {
      await _connectionRepo.discoverServices(remoteId);
      final bytes = await _connectionRepo.readCharacteristic(
        remoteId,
        identityCharacteristicUUID,
      );

      if (bytes != null && bytes.isNotEmpty) {
        final jsonStr = utf8.decode(bytes);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final name = data['name'] as String? ?? 'Desconocido';
        final color = data['color'] as String? ?? '#2196F3';

        emit(RemoteIdentityLoaded(
          remoteId: remoteId,
          name: name,
          color: color,
        ));
        return;
      }
    } catch (_) {
      // GATT read falló — continuar con fallback
    }

    // ── 3. Fallback: identidad no disponible ──
    emit(RemoteIdentityUnavailable(remoteId: remoteId));
  }

  /// Maneja la solicitud de desconexión.
  Future<void> _onDisconnect(
    DisconnectDevice event,
    Emitter<BleConnectionState> emit,
  ) async {
    if (state is BleConnectionInitial) return;

    await _stateSubscription?.cancel();
    _stateSubscription = null;

    try {
      await _connectionRepo.disconnect(event.remoteId);
    } catch (_) {
      // Ignorar errores de desconexión — el estado ya se resetea
    }

    emit(const BleConnectionInitial());
  }

  /// Determina si un error de conexión es retryable.
  bool _isRetryableError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('bluetooth') && message.contains('disabled')) {
      return false;
    }
    if (error is StateError) return false;
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
  final int myNodeId;

  const _ConnectionStateChanged({
    required this.remoteId,
    required this.connected,
    required this.myNodeId,
  });

  @override
  List<Object> get props => [remoteId, connected, myNodeId];
}
