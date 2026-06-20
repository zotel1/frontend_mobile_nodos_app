import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';
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
  final int? myNodeId;

  const ConnectToDevice(this.remoteId, {this.myNodeId});

  @override
  List<Object?> get props => [remoteId, myNodeId];
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
/// Depende de [NodeRepository] para lookup de nodeId por bleAddress
/// y de [AppDatabase] para insertar filas en la tabla connections (R5.2).
class BleConnectionBloc
    extends Bloc<BleConnectionEvent, BleConnectionState> {
  final BleGattDataSource _gatt;
  final NodeRepository _nodeRepository;
  final AppDatabase _db;
  StreamSubscription<bool>? _stateSubscription;

  BleConnectionBloc({
    required BleGattDataSource gatt,
    required NodeRepository nodeRepository,
    required AppDatabase db,
  })  : _gatt = gatt,
        _nodeRepository = nodeRepository,
        _db = db,
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
    // Si el permiso no está concedido, emitir error sin reintento.
    // En entornos sin platform channel (tests, web) se asume concedido.
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
      await _gatt.connect(event.remoteId);

      // Cancelar suscripción previa si existe
      await _stateSubscription?.cancel();

      // Suscribirse al stream de estado de conexión
      _stateSubscription = _gatt
          .connectionState(event.remoteId)
          .listen((connected) {
        if (!isClosed && connected) {
          add(_ConnectionStateChanged(
            remoteId: event.remoteId,
            connected: true,
            myNodeId: event.myNodeId,
          ));
        }
      });

      // Emitir BleConnected — la lógica post-conexión ocurre
      // en _onConnectionStateChanged cuando el stream emita true.
      emit(BleConnected(remoteId: event.remoteId));
    } catch (e) {
      // Clasificar el error como retryable o no
      final message = e.toString();
      final retryable = _isRetryableError(e);

      emit(BleConnectionError(message: message, retryable: retryable));
    }
  }

  /// Handler interno: ejecuta la lógica post-conexión cuando el stream
  /// de connectionState emite `true` (conexión establecida).
  ///
  /// QUÉ hace:
  /// 1. Inserta una fila en la tabla connections (R5.2)
  /// 2. Emite ConnectionInserted
  /// 3. Intenta discoverServices() + readCharacteristic() (AD12)
  /// 4. Si GATT read tiene éxito → emite RemoteIdentityLoaded
  /// 5. Si falla → emite RemoteIdentityUnavailable (R5.11)
  ///
  /// POR QUÉ separado de _onConnect: la conexión puede establecerse
  /// después de que _onConnect ya haya retornado. El stream de
  /// connectionState informa el momento exacto de la conexión.
  Future<void> _onConnectionStateChanged(
    _ConnectionStateChanged event,
    Emitter<BleConnectionState> emit,
  ) async {
    if (!event.connected) return;

    final remoteId = event.remoteId;

    // ── 1. Insertar fila en connections ──
    try {
      final remoteNode =
          await _nodeRepository.getNodeByBleAddress(remoteId);
      if (remoteNode != null &&
          remoteNode.id != null &&
          event.myNodeId != null) {
        await _db.into(_db.connections).insert(
              ConnectionsCompanion.insert(
                fromNodeId: event.myNodeId!,
                toNodeId: remoteNode.id!,
                createdAt: DateTime.now(),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        emit(ConnectionInserted(remoteId: remoteId));
      }
    } catch (_) {
      // Fallo silencioso: la conexión ya existe (UNIQUE constraint)
      // o el nodo no se encontró. No es crítico para el flujo.
    }

    // ── 2. Intentar GATT identity read ──
    try {
      await _gatt.discoverServices(remoteId);
      final bytes = await _gatt.readCharacteristic(
        remoteId,
        identityCharacteristicUUID,
      );

      if (bytes != null && bytes.isNotEmpty) {
        // Decodificar JSON {uuid, name, color} de la característica
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
  final int? myNodeId;

  const _ConnectionStateChanged({
    required this.remoteId,
    required this.connected,
    this.myNodeId,
  });

  @override
  List<Object?> get props => [remoteId, connected, myNodeId];
}
