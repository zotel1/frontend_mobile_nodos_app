import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_identity.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_link_request.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_link_response.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/active_graph_exchange_service.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

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
///
/// Este estado representa solamente que existe transporte GATT.
///
/// Para otra instalación Nodos esto NO significa todavía que el enlace
/// haya sido aceptado por el usuario remoto.
class BleConnected extends BleConnectionState {
  final String remoteId;

  const BleConnected({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

/// Se reconoció una instalación Nodos y se envió una solicitud de enlace.
///
/// El BLoC está esperando la decisión del usuario remoto.
class BleLinkAwaitingApproval extends BleConnectionState {
  final String remoteId;
  final String remoteUuid;
  final String remoteName;

  const BleLinkAwaitingApproval({
    required this.remoteId,
    required this.remoteUuid,
    required this.remoteName,
  });

  @override
  List<Object?> get props => [remoteId, remoteUuid, remoteName];
}

/// La instalación Nodos remota rechazó explícitamente la solicitud.
class BleLinkRejected extends BleConnectionState {
  final String remoteId;
  final String remoteUuid;

  const BleLinkRejected({required this.remoteId, required this.remoteUuid});

  @override
  List<Object?> get props => [remoteId, remoteUuid];
}

/// Error durante la conexión o durante el protocolo de enlace.
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
/// El dispositivo continúa tratándose como BLE genérico.
///
/// La UI puede solicitar metadatos manuales.
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
/// - distinguir BLE genérico de otra instalación Nodos;
/// - persistir BLE genérico al establecer la conexión;
/// - solicitar aceptación explícita antes de persistir Nodos ↔ Nodos;
/// - leer la identidad Nodos remota;
/// - reconciliar remoteId con el UUID estable Nodos;
/// - intercambiar snapshots activos en ambas direcciones;
/// - persistir snapshots remotos en `remote_relations`;
/// - eliminar snapshots remotos al perder la conexión;
/// - informar relaciones BLE activas a [ActiveGraphExchangeService].
///
/// `connections` y `remote_relations` tienen semánticas diferentes:
///
/// `connections`
///   relaciones persistentes aceptadas localmente.
///
/// `remote_relations`
///   snapshot activo declarado por otra instalación Nodos mientras esa
///   instalación permanece conectada.
class BleConnectionBloc extends Bloc<BleConnectionEvent, BleConnectionState> {
  final BleConnectionRepository _connectionRepo;
  final NodeRepository _nodeRepository;
  final UserRepository _userRepository;
  final ActiveGraphExchangeService _activeGraphExchange;
  final RemoteRelationRepository _remoteRelationRepository;

  /// Suscripción al estado GATT de cada remoteId.
  final Map<String, StreamSubscription<bool>> _stateSubscriptions =
      <String, StreamSubscription<bool>>{};

  /// myNodeId asociado a cada conexión.
  final Map<String, int> _localNodeIds = <String, int>{};

  /// Asociación temporal entre remoteId BLE e identidad estable Nodos.
  final Map<String, String> _reporterUuids = <String, String>{};

  /// Evita procesar dos veces el mismo evento `connected=true` mientras
  /// el protocolo de esa conexión ya está en curso o completado.
  final Set<String> _connectedRemoteIds = <String>{};

  BleConnectionBloc({
    required BleConnectionRepository connectionRepository,
    required NodeRepository nodeRepository,
    required UserRepository userRepository,
    required ActiveGraphExchangeService activeGraphExchange,
    required RemoteRelationRepository remoteRelationRepository,
  }) : _connectionRepo = connectionRepository,
       _nodeRepository = nodeRepository,
       _userRepository = userRepository,
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

      _connectedRemoteIds.remove(remoteId);
      _reporterUuids.remove(remoteId);

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
      _connectedRemoteIds.remove(remoteId);

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
      _connectedRemoteIds.remove(remoteId);

      await _handleInactiveRemote(remoteId);

      emit(const BleConnectionInitial());
      return;
    }

    // Algunos stacks BLE pueden volver a emitir `connected=true`.
    //
    // No debemos repetir un LinkRequest ni volver a ejecutar todo el
    // protocolo para la misma conexión física.
    if (!_connectedRemoteIds.add(remoteId)) {
      return;
    }

    emit(BleConnected(remoteId: remoteId));

    // ── 1. Descubrir servicios ──
    //
    // A diferencia de FEAT-002, todavía NO marcamos la relación como activa
    // ni persistimos `connections`.
    //
    // Primero necesitamos saber si el remoto implementa Nodos.
    try {
      await _connectionRepo.discoverServices(remoteId);
    } catch (_) {
      // No pudimos identificarlo como Nodos.
      //
      // Conservamos la compatibilidad con BLE genérico.
      await _activateGenericDevice(remoteId, emit);

      emit(RemoteIdentityUnavailable(remoteId: remoteId));
      return;
    }

    // ── 2. Intentar leer identidad Nodos ──
    final NodosIdentity identity;

    try {
      final identityBytes = await _connectionRepo.readCharacteristic(
        remoteId,
        identityCharacteristicUUID,
      );

      if (identityBytes == null || identityBytes.isEmpty) {
        await _activateGenericDevice(remoteId, emit);

        emit(RemoteIdentityUnavailable(remoteId: remoteId));
        return;
      }

      identity = NodosIdentity.fromBytes(identityBytes);
    } catch (_) {
      // Un dispositivo BLE genérico puede no implementar el protocolo Nodos.
      await _activateGenericDevice(remoteId, emit);

      emit(RemoteIdentityUnavailable(remoteId: remoteId));
      return;
    }

    // ── 3. Registrar identidad estable Nodos ──
    //
    // Desde este momento sabemos qué instalación corresponde a remoteId.
    _reporterUuids[remoteId] = identity.uuid;

    // ── 4. Reconciliar identidad estable ──
    await _reconcileNodosIdentity(remoteId: remoteId, identity: identity);

    emit(
      RemoteIdentityLoaded(
        remoteId: remoteId,
        uuid: identity.uuid,
        name: identity.name,
        color: identity.color,
      ),
    );

    // ── 5. Obtener identidad local ──
    final localUser = await _userRepository.getUserProfile();

    if (localUser == null || localUser.uuid.trim().isEmpty) {
      await _abortNodosHandshake(remoteId);

      emit(
        const BleConnectionError(
          message: 'No existe una identidad Nodos local válida',
          retryable: false,
        ),
      );
      return;
    }

    if (localUser.uuid.trim() == identity.uuid.trim()) {
      await _abortNodosHandshake(remoteId);

      emit(
        const BleConnectionError(
          message: 'No se puede enlazar la instalación Nodos consigo misma',
          retryable: false,
        ),
      );
      return;
    }

    // ── 6. Crear LinkRequest ──
    final request = NodosLinkRequest(
      deviceUuid: localUser.uuid,
      name: localUser.name,
      color: localUser.color,
    );

    emit(
      BleLinkAwaitingApproval(
        remoteId: remoteId,
        remoteUuid: identity.uuid,
        remoteName: identity.name,
      ),
    );

    // ── 7. Enviar solicitud y esperar decisión remota ──
    final List<int>? responseBytes;

    try {
      responseBytes = await _connectionRepo.writeAndWaitForResponse(
        remoteId,
        linkCharacteristicUUID,
        request.toBytes(),
        timeout: const Duration(seconds: 30),
      );
    } on TimeoutException {
      await _abortNodosHandshake(remoteId);

      emit(
        const BleConnectionError(
          message: 'La solicitud de enlace expiró sin respuesta',
          retryable: true,
        ),
      );
      return;
    } catch (error) {
      await _abortNodosHandshake(remoteId);

      emit(
        BleConnectionError(
          message: 'No se pudo completar la solicitud de enlace: $error',
          retryable: true,
        ),
      );
      return;
    }

    if (responseBytes == null || responseBytes.isEmpty) {
      // La identidad 202 existe pero la característica de handshake 204 no.
      //
      // No degradamos este caso a BLE genérico: ya sabemos que el dispositivo
      // declara una identidad Nodos. Persistir sin aceptación violaría el
      // protocolo de FEAT-003.
      await _abortNodosHandshake(remoteId);

      emit(
        const BleConnectionError(
          message:
              'La instalación Nodos remota no soporta el protocolo de enlace',
          retryable: false,
        ),
      );
      return;
    }

    // ── 8. Validar LinkResponse ──
    final NodosLinkResponse response;

    try {
      response = NodosLinkResponse.fromBytes(responseBytes);
    } catch (_) {
      await _abortNodosHandshake(remoteId);

      emit(
        const BleConnectionError(
          message: 'La respuesta de enlace recibida no es válida',
          retryable: false,
        ),
      );
      return;
    }

    final localUuid = localUser.uuid.trim();
    final remoteUuid = identity.uuid.trim();

    if (response.requesterUuid.trim() != localUuid ||
        response.responderUuid.trim() != remoteUuid) {
      await _abortNodosHandshake(remoteId);

      emit(
        const BleConnectionError(
          message: 'La respuesta de enlace no corresponde a esta solicitud',
          retryable: false,
        ),
      );
      return;
    }

    // ── 9. Rechazo explícito ──
    if (!response.accepted) {
      emit(BleLinkRejected(remoteId: remoteId, remoteUuid: remoteUuid));

      await _abortNodosHandshake(remoteId);
      return;
    }

    // ── 10. Enlace Nodos aceptado ──
    //
    // Recién ahora la conexión pasa a formar parte del grafo activo local.
    await _safeMarkConnected(remoteId);

    // ── 11. Persistir relación local ──
    await _persistLocalConnection(remoteId, emit);

    // ── 12. Enviar nuestro snapshot activo al peer ──
    //
    // markConnected() ya terminó antes de construir el payload, por lo que
    // el remoto aceptado puede formar parte del snapshot que enviamos.
    await _trySendLocalGraph(remoteId);

    // ── 13. Recibir snapshot activo del peer ──
    await _tryReceiveRemoteGraph(remoteId: remoteId, identity: identity);
  }

  /// Activa y persiste un dispositivo que no implementa el protocolo Nodos.
  ///
  /// Mantiene el comportamiento existente para BLE genérico.
  Future<void> _activateGenericDevice(
    String remoteId,
    Emitter<BleConnectionState> emit,
  ) async {
    await _safeMarkConnected(remoteId);
    await _persistLocalConnection(remoteId, emit);
  }

  /// Persiste una relación local en `connections`.
  ///
  /// Para Nodos se llama únicamente después de aceptación explícita.
  ///
  /// Para BLE genérico se llama después de determinar que el dispositivo
  /// no implementa la identidad Nodos.
  Future<void> _persistLocalConnection(
    String remoteId,
    Emitter<BleConnectionState> emit,
  ) async {
    final myNodeId = _localNodeIds[remoteId];

    if (myNodeId == null) {
      return;
    }

    try {
      final remoteNode = await _nodeRepository.getNodeByBleAddress(remoteId);

      if (remoteNode == null || remoteNode.id == null) {
        return;
      }

      await _connectionRepo.saveConnection(myNodeId, remoteNode.id!);

      emit(ConnectionInserted(remoteId: remoteId));
    } catch (_) {
      // La persistencia local no debe derribar una conexión GATT válida.
    }
  }

  /// Reconciliación del Node descubierto mediante scan con la identidad
  /// estable informada por el protocolo Nodos.
  Future<void> _reconcileNodosIdentity({
    required String remoteId,
    required NodosIdentity identity,
  }) async {
    try {
      final remoteNode = await _nodeRepository.getNodeByBleAddress(remoteId);

      if (remoteNode == null || remoteNode.id == null) {
        return;
      }

      await _nodeRepository.reconcileNodeIdentity(
        remoteNode.id!,
        deviceUuid: identity.uuid,
        name: identity.name,
        color: identity.color,
      );
    } catch (_) {
      // La identidad GATT sigue siendo válida aunque falle temporalmente
      // la reconciliación local.
    }
  }

  /// Envía al peer Nodos el mismo snapshot activo que esta instalación
  /// publica mediante su característica GATT 203.
  ///
  /// El envío central → peripheral utiliza la característica 205.
  Future<void> _trySendLocalGraph(String remoteId) async {
    try {
      final payload = await _activeGraphExchange.buildCurrentPayload();

      await _connectionRepo.writeCharacteristic(
        remoteId,
        peerGraphCharacteristicUUID,
        payload.toBytes(),
      );
    } catch (_) {
      // El intercambio del grafo es adicional al enlace ya aceptado.
      //
      // Un fallo temporal enviando el snapshot no elimina la conexión
      // persistente ni transforma la aceptación en rechazo.
    }
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

  /// Cancela un handshake Nodos que no llegó a ser aceptado.
  ///
  /// Como la conexión nunca fue incorporada al grafo activo, no se crea
  /// ninguna fila nueva en `connections`.
  Future<void> _abortNodosHandshake(String remoteId) async {
    _connectedRemoteIds.remove(remoteId);

    try {
      await _connectionRepo.disconnect(remoteId);
    } catch (_) {
      // El transporte puede haberse cerrado antes.
    }

    await _handleInactiveRemote(remoteId);
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

    _connectedRemoteIds.remove(remoteId);

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
      // Un error publicando el snapshot no debe derribar el transporte GATT.
    }
  }

  Future<void> _safeMarkDisconnected(String remoteId) async {
    try {
      await _activeGraphExchange.markDisconnected(remoteId);
    } catch (_) {
      // Un error publicando el snapshot no debe impedir la desconexión.
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
    _connectedRemoteIds.clear();

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
