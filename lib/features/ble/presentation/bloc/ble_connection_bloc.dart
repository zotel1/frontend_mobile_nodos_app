import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/active_graph_exchange_service.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/graph_exchange_session_manager.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/services/ble_connection_handshake_coordinator.dart';
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

/// Invalida todo el estado GATT activo sin tocar las relaciones persistentes.
class ResetActiveConnections extends BleConnectionEvent {
  const ResetActiveConnections();
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
  final GraphExchangeSessionManager _sessionManager;
  late final BleConnectionHandshakeCoordinator _handshakeCoordinator;

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
    GraphExchangeSessionManager? sessionManager,
    BleConnectionHandshakeCoordinator? handshakeCoordinator,
  }) : _connectionRepo = connectionRepository,
       _nodeRepository = nodeRepository,
       _userRepository = userRepository,
       _activeGraphExchange = activeGraphExchange,
       _remoteRelationRepository = remoteRelationRepository,
       _sessionManager = sessionManager ?? GraphExchangeSessionManager(),
       super(const BleConnectionInitial()) {
    _handshakeCoordinator =
        handshakeCoordinator ??
        BleConnectionHandshakeCoordinator(
          connectionRepository: _connectionRepo,
          nodeRepository: _nodeRepository,
          userRepository: _userRepository,
          activeGraphExchange: _activeGraphExchange,
          remoteRelationRepository: _remoteRelationRepository,
          sessionManager: _sessionManager,
        );
    on<ConnectToDevice>(_onConnect);
    on<DisconnectDevice>(_onDisconnect);
    on<ResetActiveConnections>(_onResetActiveConnections);
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
      await _cancelSubscription(remoteId);
      _connectedRemoteIds.remove(remoteId);
      _localNodeIds.remove(remoteId);

      await _handleInactiveRemote(remoteId);

      emit(const BleConnectionInitial());
      return;
    }

    if (!_connectedRemoteIds.add(remoteId)) {
      return;
    }

    emit(BleConnected(remoteId: remoteId));

    try {
      final result = await _handshakeCoordinator.handleConnected(
        remoteId: remoteId,
        myNodeId: _localNodeIds[remoteId],
        onProgress: (progress) {
          switch (progress) {
            case RemoteIdentityDiscovered(:final remoteId, :final identity):
              emit(
                RemoteIdentityLoaded(
                  remoteId: remoteId,
                  uuid: identity.uuid,
                  name: identity.name,
                  color: identity.color,
                ),
              );
            case LinkApprovalRequested(:final remoteId, :final identity):
              emit(
                BleLinkAwaitingApproval(
                  remoteId: remoteId,
                  remoteUuid: identity.uuid,
                  remoteName: identity.name,
                ),
              );
            case ConnectionPersisted(:final remoteId):
              emit(ConnectionInserted(remoteId: remoteId));
            case LinkRejected(:final remoteId, :final identity):
              emit(
                BleLinkRejected(remoteId: remoteId, remoteUuid: identity.uuid),
              );
          }
        },
        abort: _abortNodosHandshake,
      );

      if (result.genericDevice) {
        emit(RemoteIdentityUnavailable(remoteId: remoteId));
      }
    } on BleConnectionHandshakeFailure catch (error) {
      emit(
        BleConnectionError(message: error.message, retryable: error.retryable),
      );
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

  Future<void> _onResetActiveConnections(
    ResetActiveConnections event,
    Emitter<BleConnectionState> emit,
  ) async {
    await _resetActiveConnections();
    emit(const BleConnectionInitial());
  }

  Future<void> _resetActiveConnections() async {
    final remoteIds = <String>{
      ..._stateSubscriptions.keys,
      ..._connectedRemoteIds,
      ..._localNodeIds.keys,
    };

    for (final remoteId in remoteIds) {
      await _cancelSubscription(remoteId);

      try {
        await _connectionRepo.disconnect(remoteId);
      } catch (_) {
        // El transporte puede ya estar cerrado.
      }

      _localNodeIds.remove(remoteId);
      _connectedRemoteIds.remove(remoteId);
      await _handleInactiveRemote(remoteId);
    }

    _stateSubscriptions.clear();
    _localNodeIds.clear();
    _connectedRemoteIds.clear();
    _reporterUuids.clear();
    _sessionManager.clear();

    try {
      await _activeGraphExchange.clear();
    } catch (_) {
      // La invalidación del grafo no debe bloquear el cleanup de BLE.
    }

    try {
      await _clearAllRemoteSnapshots();
    } catch (_) {
      // El próximo ciclo de lifecycle volverá a limpiar la caché.
    }
  }

  Future<void> _clearAllRemoteSnapshots() {
    if (_remoteRelationRepository is RemoteRelationLifecycle) {
      return (_remoteRelationRepository as RemoteRelationLifecycle)
          .clearAllSnapshots();
    }
    return Future<void>.value();
  }

  Future<void> _handleInactiveRemote(String remoteId) async {
    await _safeMarkDisconnected(remoteId);

    _sessionManager.invalidateByRemoteId(remoteId);

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
    await _resetActiveConnections();

    final subscriptions = _stateSubscriptions.values.toList();

    _stateSubscriptions.clear();
    _localNodeIds.clear();
    _reporterUuids.clear();
    _connectedRemoteIds.clear();
    _sessionManager.clear();

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
