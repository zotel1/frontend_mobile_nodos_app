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
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

// ──────────────────────── Events ────────────────────────

sealed class BleConnectionEvent extends Equatable {
  const BleConnectionEvent();

  @override
  List<Object?> get props => [];
}

class ConnectToDevice extends BleConnectionEvent {
  final String remoteId;
  final int myNodeId;

  const ConnectToDevice(this.remoteId, {required this.myNodeId});

  @override
  List<Object> get props => [remoteId, myNodeId];
}

class DisconnectDevice extends BleConnectionEvent {
  final String remoteId;

  const DisconnectDevice(this.remoteId);

  @override
  List<Object?> get props => [remoteId];
}

// ──────────────────────── States ────────────────────────

sealed class BleConnectionState extends Equatable {
  const BleConnectionState();

  @override
  List<Object?> get props => [];
}

class BleConnectionInitial extends BleConnectionState {
  const BleConnectionInitial();
}

class BleConnecting extends BleConnectionState {
  final String remoteId;

  const BleConnecting({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

class BleConnected extends BleConnectionState {
  final String remoteId;

  const BleConnected({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

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

class BleLinkRejected extends BleConnectionState {
  final String remoteId;
  final String remoteUuid;

  const BleLinkRejected({required this.remoteId, required this.remoteUuid});

  @override
  List<Object?> get props => [remoteId, remoteUuid];
}

class BleConnectionError extends BleConnectionState {
  final String message;
  final bool retryable;

  const BleConnectionError({required this.message, required this.retryable});

  @override
  List<Object?> get props => [message, retryable];
}

class ConnectionInserted extends BleConnectionState {
  final String remoteId;

  const ConnectionInserted({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

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

/// La característica de identidad Nodos no existe.
///
/// Este estado se reserva para el caso en que el dispositivo se considera
/// BLE genérico. Una identidad Nodos vacía, malformada o un fallo real de
/// transporte no deben producir este estado.
class RemoteIdentityUnavailable extends BleConnectionState {
  final String remoteId;

  const RemoteIdentityUnavailable({required this.remoteId});

  @override
  List<Object?> get props => [remoteId];
}

// ──────────────────────── BLoC ────────────────────────

class BleConnectionBloc extends Bloc<BleConnectionEvent, BleConnectionState> {
  final BleConnectionRepository _connectionRepo;
  final NodeRepository _nodeRepository;
  final UserRepository _userRepository;
  final ActiveGraphExchangeService _activeGraphExchange;
  final RemoteRelationRepository _remoteRelationRepository;

  final Map<String, StreamSubscription<bool>> _stateSubscriptions =
      <String, StreamSubscription<bool>>{};

  final Map<String, int> _localNodeIds = <String, int>{};

  final Map<String, String> _reporterUuids = <String, String>{};

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

    if (!_connectedRemoteIds.add(remoteId)) {
      return;
    }

    emit(BleConnected(remoteId: remoteId));

    // ── 1. Descubrir servicios ──
    try {
      await _connectionRepo.discoverServices(remoteId);
    } catch (error) {
      await _abortNodosHandshake(remoteId);

      emit(
        BleConnectionError(
          message: 'No se pudieron descubrir los servicios GATT: $error',
          retryable: true,
        ),
      );
      return;
    }

    // ── 2. Leer característica de identidad ──
    //
    // null significa que la característica Nodos no existe.
    // ÚNICAMENTE ese caso se degrada a BLE genérico.
    final List<int>? identityBytes;

    try {
      identityBytes = await _connectionRepo.readCharacteristic(
        remoteId,
        identityCharacteristicUUID,
      );
    } catch (error) {
      await _abortNodosHandshake(remoteId);

      emit(
        BleConnectionError(
          message: 'Error leyendo la identidad Nodos remota: $error',
          retryable: true,
        ),
      );
      return;
    }

    if (identityBytes == null) {
      await _activateGenericDevice(remoteId, emit);

      emit(RemoteIdentityUnavailable(remoteId: remoteId));
      return;
    }

    if (identityBytes.isEmpty) {
      await _abortNodosHandshake(remoteId);

      emit(
        const BleConnectionError(
          message: 'La identidad Nodos remota está vacía',
          retryable: false,
        ),
      );
      return;
    }

    // ── 3. Interpretar identidad Nodos ──
    final NodosIdentity identity;

    try {
      identity = NodosIdentity.fromBytes(identityBytes);
    } catch (error) {
      await _abortNodosHandshake(remoteId);

      emit(
        BleConnectionError(
          message: 'La identidad Nodos remota no es válida: $error',
          retryable: false,
        ),
      );
      return;
    }

    // ── 4. Registrar identidad estable Nodos ──
    _reporterUuids[remoteId] = identity.uuid;

    // ── 5. Reconciliar identidad estable ──
    final Node? canonicalRemoteNode;

    try {
      canonicalRemoteNode = await _reconcileNodosIdentity(
        remoteId: remoteId,
        identity: identity,
      );
    } catch (error) {
      await _abortNodosHandshake(remoteId);

      emit(
        BleConnectionError(
          message: 'No se pudo reconciliar la identidad Nodos remota: $error',
          retryable: true,
        ),
      );
      return;
    }

    if (canonicalRemoteNode == null || canonicalRemoteNode.id == null) {
      await _abortNodosHandshake(remoteId);

      emit(
        const BleConnectionError(
          message:
              'No se pudo resolver el nodo persistente de la instalación Nodos remota',
          retryable: true,
        ),
      );
      return;
    }

    emit(
      RemoteIdentityLoaded(
        remoteId: remoteId,
        uuid: identity.uuid,
        name: identity.name,
        color: identity.color,
      ),
    );

    // ── 6. Obtener identidad local ──
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

    // ── 7. Crear LinkRequest ──
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

    // ── 8. Enviar solicitud y esperar decisión remota ──
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

    // ── 9. Validar LinkResponse ──
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

    // ── 10. Rechazo explícito ──
    if (!response.accepted) {
      emit(BleLinkRejected(remoteId: remoteId, remoteUuid: remoteUuid));

      await _abortNodosHandshake(remoteId);
      return;
    }

    // ── 11. Persistencia estricta del enlace Nodos ──
    //
    // Una aceptación remota no alcanza para considerar establecido el
    // enlace local. Primero debemos garantizar que la relación pueda quedar
    // persistida contra el Node canónico.
    try {
      await _persistNodosConnection(
        remoteId: remoteId,
        remoteNodeId: canonicalRemoteNode.id!,
      );
    } catch (error) {
      await _abortNodosHandshake(remoteId);

      emit(
        BleConnectionError(
          message: 'No se pudo persistir el enlace Nodos aceptado: $error',
          retryable: true,
        ),
      );
      return;
    }

    emit(ConnectionInserted(remoteId: remoteId));

    // ── 12. Incorporar al grafo activo ──
    //
    // Esto ocurre únicamente después de haber persistido correctamente el
    // enlace local.
    await _safeMarkConnected(remoteId);

    // ── 13. Enviar nuestro snapshot activo al peer ──
    await _trySendLocalGraph(remoteId);

    // ── 14. Recibir snapshot activo del peer ──
    await _tryReceiveRemoteGraph(remoteId: remoteId, identity: identity);
  }

  /// Activa y persiste un dispositivo BLE genérico.
  ///
  /// El comportamiento de BLE genérico continúa siendo tolerante:
  /// una falla de persistencia no derriba una conexión GATT válida.
  Future<void> _activateGenericDevice(
    String remoteId,
    Emitter<BleConnectionState> emit,
  ) async {
    await _safeMarkConnected(remoteId);
    await _persistGenericConnection(remoteId, emit);
  }

  /// Persiste una relación local con un dispositivo BLE genérico.
  Future<void> _persistGenericConnection(
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
      // BLE genérico conserva el comportamiento tolerante.
    }
  }

  /// Persiste estrictamente una relación Nodos aceptada.
  ///
  /// A diferencia del camino BLE genérico, cualquier inconsistencia o error
  /// se propaga al caller para que el handshake sea abortado.
  Future<void> _persistNodosConnection({
    required String remoteId,
    required int remoteNodeId,
  }) async {
    final myNodeId = _localNodeIds[remoteId];

    if (myNodeId == null) {
      throw StateError('No existe un nodo local asociado a la conexión Nodos');
    }

    if (myNodeId == remoteNodeId) {
      throw StateError(
        'El nodo local y el nodo remoto Nodos no pueden ser el mismo',
      );
    }

    await _connectionRepo.saveConnection(myNodeId, remoteNodeId);
  }

  /// Reconcilia el Node descubierto por BLE con la identidad Nodos estable
  /// y devuelve el Node canónico resultante.
  Future<Node?> _reconcileNodosIdentity({
    required String remoteId,
    required NodosIdentity identity,
  }) async {
    final remoteNode = await _nodeRepository.getNodeByBleAddress(remoteId);

    if (remoteNode == null || remoteNode.id == null) {
      return null;
    }

    return _nodeRepository.reconcileNodeIdentity(
      remoteNode.id!,
      deviceUuid: identity.uuid,
      name: identity.name,
      color: identity.color,
    );
  }

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
    }
  }

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

      if (payload.ownerUuid != identity.uuid) {
        return;
      }

      await _remoteRelationRepository.replaceSnapshot(
        reporterUuid: identity.uuid,
        connections: payload.connections,
      );
    } catch (_) {
      // Fallo de transporte != snapshot vacío.
    }
  }

  Future<void> _abortNodosHandshake(String remoteId) async {
    _connectedRemoteIds.remove(remoteId);

    try {
      await _connectionRepo.disconnect(remoteId);
    } catch (_) {
      // El transporte puede haberse cerrado antes.
    }

    await _handleInactiveRemote(remoteId);
  }

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

  Future<void> _handleInactiveRemote(String remoteId) async {
    await _safeMarkDisconnected(remoteId);

    final reporterUuid = _reporterUuids.remove(remoteId);

    if (reporterUuid == null || reporterUuid.trim().isEmpty) {
      return;
    }

    try {
      await _remoteRelationRepository.clearSnapshot(reporterUuid);
    } catch (_) {
      // La limpieza remota no debe impedir la desconexión local.
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
