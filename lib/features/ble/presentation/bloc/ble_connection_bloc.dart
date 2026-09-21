import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_identity.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/active_graph_exchange_service.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';

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
/// (el que inicia la conexión).
///
/// Se utiliza exclusivamente para persistir la relación local en
/// `connections`.
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
///
/// IMPORTANTE:
///
/// Estos estados representan feedback/eventos de la operación más reciente.
///
/// El conjunto completo de conexiones activas no vive en este estado.
/// Ese estado agregado pertenece a [ActiveGraphExchangeService].
sealed class BleConnectionState extends Equatable {
  const BleConnectionState();

  @override
  List<Object?> get props => [];
}

/// Estado inicial.
///
/// No implica necesariamente que no exista ninguna otra conexión activa.
/// Puede haber múltiples conexiones administradas simultáneamente por el
/// BLoC.
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

/// Conexión GATT confirmada por el stream connectionState.
class BleConnected extends BleConnectionState {
  final String remoteId;

  const BleConnected({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

/// Error durante la conexión.
class BleConnectionError extends BleConnectionState {
  final String message;
  final bool retryable;

  const BleConnectionError({required this.message, required this.retryable});

  @override
  List<Object?> get props => [message, retryable];
}

/// Conexión persistida en la tabla `connections`.
///
/// La existencia de esta fila NO significa que el dispositivo continúe
/// conectado.
///
/// El estado activo se mantiene independientemente mediante
/// [ActiveGraphExchangeService].
class ConnectionInserted extends BleConnectionState {
  final String remoteId;

  const ConnectionInserted({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

/// Identidad remota cargada exitosamente mediante GATT.
///
/// [remoteId] identifica la conexión BLE local.
///
/// [uuid] identifica persistentemente a la instalación remota de Nodos.
///
/// [name] y [color] son los metadatos configurados por el usuario remoto.
class RemoteIdentityLoaded extends BleConnectionState {
  final String remoteId;
  final String uuid;
  final String name;
  final String color;

  const RemoteIdentityLoaded({
    required this.remoteId,
    required this.uuid,
    required this.name,
    required this.color,
  });

  @override
  List<Object?> get props => [remoteId, uuid, name, color];
}

/// No se pudo leer la identidad remota mediante GATT.
///
/// La UI puede solicitar metadatos manuales para dispositivos que no
/// implementen el protocolo Nodos.
class RemoteIdentityUnavailable extends BleConnectionState {
  final String remoteId;

  const RemoteIdentityUnavailable({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

// ──────────────────────── BLoC ────────────────────────

/// Gestiona conexiones GATT punto a punto.
///
/// Responsabilidades:
///
/// - solicitar permiso BLUETOOTH_CONNECT;
/// - iniciar conexiones GATT;
/// - observar el estado real de cada conexión;
/// - soportar múltiples dispositivos simultáneamente;
/// - persistir enlaces locales en `connections`;
/// - leer la identidad Nodos remota;
/// - reconciliar remoteId con el UUID estable Nodos;
/// - leer y validar el snapshot activo remoto;
/// - persistir ese snapshot en `remote_relations`;
/// - eliminar el snapshot remoto cuando el reporter deja de estar conectado;
/// - informar conexiones/desconexiones activas a
///   [ActiveGraphExchangeService].
///
/// `connections` y `remote_relations` tienen semánticas diferentes:
///
/// `connections`
///   relaciones persistentes creadas localmente.
///
/// `remote_relations`
///   snapshot activo declarado por otra instalación Nodos mientras esa
///   instalación permanece conectada.
class BleConnectionBloc extends Bloc<BleConnectionEvent, BleConnectionState> {
  final BleConnectionRepository _connectionRepo;
  final NodeRepository _nodeRepository;
  final ActiveGraphExchangeService _activeGraphExchange;
  final RemoteRelationRepository _remoteRelationRepository;

  /// Suscripción al estado GATT de cada remoteId.
  final Map<String, StreamSubscription<bool>> _stateSubscriptions =
      <String, StreamSubscription<bool>>{};

  /// myNodeId asociado a cada conexión.
  final Map<String, int> _localNodeIds = <String, int>{};

  /// Asociación temporal entre el identificador BLE local y la identidad
  /// estable Nodos descubierta mediante GATT.
  ///
  /// No se persiste porque únicamente representa el contexto de la conexión
  /// activa administrada por este BLoC.
  ///
  /// Permite que, cuando `connectionState` informe una desconexión, podamos
  /// eliminar el snapshot activo del reporter correcto.
  final Map<String, String> _reporterUuids = <String, String>{};

  BleConnectionBloc({
    required BleConnectionRepository connectionRepository,
    required NodeRepository nodeRepository,
    required ActiveGraphExchangeService activeGraphExchange,
    required RemoteRelationRepository remoteRelationRepository,
  }) : _connectionRepo = connectionRepository,
       _nodeRepository = nodeRepository,
       _activeGraphExchange = activeGraphExchange,
       _remoteRelationRepository = remoteRelationRepository,
       super(const BleConnectionInitial()) {
    on<ConnectToDevice>(_onConnect);
    on<DisconnectDevice>(_onDisconnect);
    on<_ConnectionStateChanged>(_onConnectionStateChanged);
  }

  /// Inicia o reinicia la conexión a [ConnectToDevice.remoteId].
  Future<void> _onConnect(
    ConnectToDevice event,
    Emitter<BleConnectionState> emit,
  ) async {
    final remoteId = event.remoteId.trim();

    if (remoteId.isEmpty) {
      emit(
        const BleConnectionError(
          message: 'remoteId BLE vacío',
          retryable: false,
        ),
      );
      return;
    }

    emit(BleConnecting(remoteId: remoteId));

    try {
      final permission = await Permission.bluetoothConnect.request();

      if (!permission.isGranted) {
        emit(
          const BleConnectionError(
            message: 'Permiso BLUETOOTH_CONNECT requerido',
            retryable: false,
          ),
        );
        return;
      }
    } catch (_) {
      // Entornos sin platform channel.
    }

    try {
      await _cancelSubscription(remoteId);

      _localNodeIds[remoteId] = event.myNodeId;

      _stateSubscriptions[remoteId] = _connectionRepo
          .connectionState(remoteId)
          .listen(
            (connected) {
              if (!isClosed) {
                add(
                  _ConnectionStateChanged(
                    remoteId: remoteId,
                    connected: connected,
                  ),
                );
              }
            },
            onError: (Object error) {
              if (!isClosed) {
                add(
                  _ConnectionStateChanged(remoteId: remoteId, connected: false),
                );
              }
            },
          );

      await _connectionRepo.connect(remoteId);
    } catch (e) {
      await _cancelSubscription(remoteId);
      _localNodeIds.remove(remoteId);

      await _handleInactiveRemote(remoteId);

      emit(
        BleConnectionError(
          message: e.toString(),
          retryable: _isRetryableError(e),
        ),
      );
    }
  }

  /// Procesa cambios reales del stream connectionState.
  Future<void> _onConnectionStateChanged(
    _ConnectionStateChanged event,
    Emitter<BleConnectionState> emit,
  ) async {
    final remoteId = event.remoteId;

    if (!event.connected) {
      await _handleInactiveRemote(remoteId);

      emit(const BleConnectionInitial());
      return;
    }

    emit(BleConnected(remoteId: remoteId));

    // ── 1. Registrar relación activa local ──
    await _safeMarkConnected(remoteId);

    // ── 2. Persistir relación local ──
    //
    // `connections` sigue siendo independiente del snapshot distribuido.
    final myNodeId = _localNodeIds[remoteId];

    if (myNodeId != null) {
      try {
        final remoteNode = await _nodeRepository.getNodeByBleAddress(remoteId);

        if (remoteNode != null && remoteNode.id != null) {
          await _connectionRepo.saveConnection(myNodeId, remoteNode.id!);

          emit(ConnectionInserted(remoteId: remoteId));
        }
      } catch (_) {
        // La persistencia local no debe derribar la conexión GATT.
      }
    }

    // ── 3. Descubrir servicios ──
    try {
      await _connectionRepo.discoverServices(remoteId);
    } catch (_) {
      emit(RemoteIdentityUnavailable(remoteId: remoteId));
      return;
    }

    // ── 4. Leer identidad Nodos ──
    final NodosIdentity identity;

    try {
      final identityBytes = await _connectionRepo.readCharacteristic(
        remoteId,
        identityCharacteristicUUID,
      );

      if (identityBytes == null || identityBytes.isEmpty) {
        emit(RemoteIdentityUnavailable(remoteId: remoteId));
        return;
      }

      identity = NodosIdentity.fromBytes(identityBytes);
    } catch (_) {
      // Un BLE genérico puede no implementar el protocolo Nodos.
      emit(RemoteIdentityUnavailable(remoteId: remoteId));
      return;
    }

    // Desde este momento conocemos qué instalación Nodos corresponde
    // al remoteId de esta conexión.
    _reporterUuids[remoteId] = identity.uuid;

    // ── 5. Reconciliar identidad estable ──
    //
    // El scan conoce inicialmente al dispositivo por remoteId.
    // Una vez leída la identidad Nodos podemos asociarlo a su UUID estable.
    try {
      final remoteNode = await _nodeRepository.getNodeByBleAddress(remoteId);

      if (remoteNode != null && remoteNode.id != null) {
        await _nodeRepository.reconcileNodeIdentity(
          remoteNode.id!,
          deviceUuid: identity.uuid,
          name: identity.name,
          color: identity.color,
        );
      }
    } catch (_) {
      // La identidad GATT sigue siendo válida aunque falle temporalmente
      // la reconciliación local. No descartamos por eso el intercambio.
    }

    emit(
      RemoteIdentityLoaded(
        remoteId: remoteId,
        uuid: identity.uuid,
        name: identity.name,
        color: identity.color,
      ),
    );

    // ── 6. Leer snapshot activo remoto ──
    //
    // IMPORTANTE:
    //
    // Un error, timeout, característica ausente o payload inválido NO
    // equivale a un snapshot vacío.
    //
    // En esos casos conservamos el último snapshot válido almacenado
    // mientras el reporter continúe conectado.
    await _tryReceiveRemoteGraph(remoteId: remoteId, identity: identity);
  }

  /// Intenta leer y persistir el snapshot activo publicado por una
  /// instalación Nodos.
  ///
  /// Solo un payload válido puede reemplazar el snapshot anterior.
  Future<void> _tryReceiveRemoteGraph({
    required String remoteId,
    required NodosIdentity identity,
  }) async {
    try {
      final graphBytes = await _connectionRepo.readCharacteristic(
        remoteId,
        graphCharacteristicUUID,
      );

      if (graphBytes == null || graphBytes.isEmpty) {
        return;
      }

      final payload = NodosGraphPayload.fromBytes(graphBytes);

      // La identidad leída por identityCharacteristicUUID y el propietario
      // declarado por el payload deben representar la misma instalación.
      //
      // Si no coinciden, el snapshot se rechaza completamente.
      if (payload.ownerUuid != identity.uuid) {
        return;
      }

      await _remoteRelationRepository.replaceSnapshot(
        reporterUuid: identity.uuid,
        connections: payload.connections,
      );
    } catch (_) {
      // No borrar el snapshot anterior.
      //
      // Fallo de transporte != "el remoto ya no tiene conexiones".
      //
      // Un payload válido con connections: [] sí llegará hasta
      // replaceSnapshot() y eliminará correctamente las filas anteriores.
    }
  }

  /// Desconecta únicamente el dispositivo solicitado.
  Future<void> _onDisconnect(
    DisconnectDevice event,
    Emitter<BleConnectionState> emit,
  ) async {
    final remoteId = event.remoteId.trim();

    if (remoteId.isEmpty) {
      return;
    }

    await _cancelSubscription(remoteId);

    try {
      await _connectionRepo.disconnect(remoteId);
    } catch (_) {
      // Aunque el transporte ya estuviera desconectado, localmente debemos
      // reflejar que dejó de ser una relación activa.
    }

    _localNodeIds.remove(remoteId);

    await _handleInactiveRemote(remoteId);

    emit(const BleConnectionInitial());
  }

  /// Procesa la pérdida de una relación activa.
  ///
  /// Tiene dos efectos independientes:
  ///
  /// 1. elimina [remoteId] del snapshot local que esta instalación publica;
  /// 2. si [remoteId] pertenecía a otra instalación Nodos identificada,
  ///    elimina el snapshot que esa instalación nos había reportado.
  ///
  /// Ninguna de estas operaciones elimina filas de `connections`.
  Future<void> _handleInactiveRemote(String remoteId) async {
    await _safeMarkDisconnected(remoteId);

    final reporterUuid = _reporterUuids.remove(remoteId);

    if (reporterUuid == null || reporterUuid.trim().isEmpty) {
      return;
    }

    try {
      await _remoteRelationRepository.clearSnapshot(reporterUuid);
    } catch (_) {
      // La limpieza de remote_relations no debe impedir que el estado
      // activo local refleje correctamente la desconexión.
      //
      // TODO(FEAT-002):
      // incorporar logging estructurado para fallos de persistencia.
    }
  }

  Future<void> _cancelSubscription(String remoteId) async {
    final subscription = _stateSubscriptions.remove(remoteId);

    if (subscription != null) {
      await subscription.cancel();
    }
  }

  Future<void> _safeMarkConnected(String remoteId) async {
    try {
      await _activeGraphExchange.markConnected(remoteId);
    } catch (_) {
      // TODO(FEAT-002):
      // incorporar logging estructurado para errores de intercambio.
    }
  }

  Future<void> _safeMarkDisconnected(String remoteId) async {
    try {
      await _activeGraphExchange.markDisconnected(remoteId);
    } catch (_) {
      // TODO(FEAT-002):
      // incorporar logging estructurado para errores de intercambio.
    }
  }

  bool _isRetryableError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('bluetooth') && message.contains('disabled')) {
      return false;
    }

    if (error is StateError) {
      return false;
    }

    return true;
  }

  @override
  Future<void> close() async {
    final subscriptions = _stateSubscriptions.values.toList();

    _stateSubscriptions.clear();
    _localNodeIds.clear();
    _reporterUuids.clear();

    for (final subscription in subscriptions) {
      await subscription.cancel();
    }

    await super.close();
  }
}

/// Evento interno emitido por cada stream connectionState.
class _ConnectionStateChanged extends BleConnectionEvent {
  final String remoteId;
  final bool connected;

  const _ConnectionStateChanged({
    required this.remoteId,
    required this.connected,
  });

  @override
  List<Object> get props => [remoteId, connected];
}
