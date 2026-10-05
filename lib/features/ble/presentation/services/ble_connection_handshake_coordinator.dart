import 'dart:async';

import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_identity.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_link_request.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_link_response.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/active_graph_exchange_service.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/graph_exchange_session_manager.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/services/live_graph_sync_service.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

sealed class BleConnectionHandshakeProgress {
  const BleConnectionHandshakeProgress();
}

class RemoteIdentityDiscovered extends BleConnectionHandshakeProgress {
  final String remoteId;
  final NodosIdentity identity;

  const RemoteIdentityDiscovered({
    required this.remoteId,
    required this.identity,
  });
}

class LinkApprovalRequested extends BleConnectionHandshakeProgress {
  final String remoteId;
  final NodosIdentity identity;

  const LinkApprovalRequested({required this.remoteId, required this.identity});
}

class ConnectionPersisted extends BleConnectionHandshakeProgress {
  final String remoteId;

  const ConnectionPersisted(this.remoteId);
}

class BleConnectionHandshakeFailure implements Exception {
  final String message;
  final bool retryable;

  const BleConnectionHandshakeFailure({
    required this.message,
    required this.retryable,
  });
}

class BleConnectionHandshakeResult {
  final bool genericDevice;

  const BleConnectionHandshakeResult({required this.genericDevice});
}

/// Coordinates the post-GATT connection protocol without owning BLoC state.
///
/// This service covers identity reconciliation, LinkRequest/LinkResponse,
/// LINKED persistence, Graph Exchange activation, and the initial snapshot.
/// It intentionally does not publish later local changes; that responsibility
/// belongs to [LiveGraphSyncService].
class BleConnectionHandshakeCoordinator {
  final BleConnectionRepository _connectionRepo;
  final NodeRepository _nodeRepository;
  final UserRepository _userRepository;
  final ActiveGraphExchangeService _activeGraphExchange;
  final RemoteRelationRepository _remoteRelationRepository;
  final GraphExchangeSessionManager _sessionManager;
  final LiveGraphSyncService? _liveGraphSync;
  final Map<String, StreamSubscription<List<int>>> _graphSubscriptions =
      <String, StreamSubscription<List<int>>>{};

  BleConnectionHandshakeCoordinator({
    required BleConnectionRepository connectionRepository,
    required NodeRepository nodeRepository,
    required UserRepository userRepository,
    required ActiveGraphExchangeService activeGraphExchange,
    required RemoteRelationRepository remoteRelationRepository,
    required GraphExchangeSessionManager sessionManager,
    LiveGraphSyncService? liveGraphSync,
  }) : _connectionRepo = connectionRepository,
       _nodeRepository = nodeRepository,
       _userRepository = userRepository,
       _activeGraphExchange = activeGraphExchange,
       _remoteRelationRepository = remoteRelationRepository,
       _sessionManager = sessionManager,
       _liveGraphSync = liveGraphSync;

  Future<BleConnectionHandshakeResult> handleConnected({
    required String remoteId,
    required int? myNodeId,
    required void Function(BleConnectionHandshakeProgress progress) onProgress,
    required Future<void> Function(String remoteId) abort,
  }) async {
    try {
      await _connectionRepo.discoverServices(remoteId);
    } catch (error) {
      await abort(remoteId);
      throw BleConnectionHandshakeFailure(
        message: 'No se pudieron descubrir los servicios GATT: $error',
        retryable: true,
      );
    }

    final List<int>? identityBytes;
    try {
      identityBytes = await _connectionRepo.readCharacteristic(
        remoteId,
        identityCharacteristicUUID,
      );
    } catch (error) {
      await abort(remoteId);
      throw BleConnectionHandshakeFailure(
        message: 'Error leyendo la identidad Nodos remota: $error',
        retryable: true,
      );
    }

    if (identityBytes == null) {
      await _safeMarkConnected(remoteId);
      await _persistGenericConnection(
        remoteId: remoteId,
        myNodeId: myNodeId,
        onProgress: onProgress,
      );
      return const BleConnectionHandshakeResult(genericDevice: true);
    }

    if (identityBytes.isEmpty) {
      await abort(remoteId);
      throw const BleConnectionHandshakeFailure(
        message: 'La identidad Nodos remota está vacía',
        retryable: false,
      );
    }

    final NodosIdentity identity;
    try {
      identity = NodosIdentity.fromBytes(identityBytes);
    } catch (error) {
      await abort(remoteId);
      throw BleConnectionHandshakeFailure(
        message: 'La identidad Nodos remota no es válida: $error',
        retryable: false,
      );
    }

    _sessionManager.registerPending(identity.uuid, remoteId: remoteId);

    final Node? canonicalRemoteNode;
    try {
      canonicalRemoteNode = await _reconcileNodosIdentity(
        remoteId: remoteId,
        identity: identity,
      );
    } catch (error) {
      await abort(remoteId);
      throw BleConnectionHandshakeFailure(
        message: 'No se pudo reconciliar la identidad Nodos remota: $error',
        retryable: true,
      );
    }

    if (canonicalRemoteNode == null || canonicalRemoteNode.id == null) {
      await abort(remoteId);
      throw const BleConnectionHandshakeFailure(
        message:
            'No se pudo resolver el nodo persistente de la instalación Nodos remota',
        retryable: true,
      );
    }

    onProgress(
      RemoteIdentityDiscovered(remoteId: remoteId, identity: identity),
    );

    final localUser = await _userRepository.getUserProfile();
    if (localUser == null || localUser.uuid.trim().isEmpty) {
      await abort(remoteId);
      throw const BleConnectionHandshakeFailure(
        message: 'No existe una identidad Nodos local válida',
        retryable: false,
      );
    }

    if (localUser.uuid.trim() == identity.uuid.trim()) {
      await abort(remoteId);
      throw const BleConnectionHandshakeFailure(
        message: 'No se puede enlazar la instalación Nodos consigo misma',
        retryable: false,
      );
    }

    final request = NodosLinkRequest(
      deviceUuid: localUser.uuid,
      name: localUser.name,
      color: localUser.color,
    );
    onProgress(LinkApprovalRequested(remoteId: remoteId, identity: identity));

    final List<int>? responseBytes;
    try {
      responseBytes = await _connectionRepo.writeAndWaitForResponse(
        remoteId,
        linkCharacteristicUUID,
        request.toBytes(),
        timeout: const Duration(seconds: 30),
      );
    } on TimeoutException {
      await abort(remoteId);
      throw const BleConnectionHandshakeFailure(
        message: 'La solicitud de enlace expiró sin respuesta',
        retryable: true,
      );
    } catch (error) {
      await abort(remoteId);
      throw BleConnectionHandshakeFailure(
        message: 'No se pudo completar la solicitud de enlace: $error',
        retryable: true,
      );
    }

    if (responseBytes == null || responseBytes.isEmpty) {
      await abort(remoteId);
      throw const BleConnectionHandshakeFailure(
        message:
            'La instalación Nodos remota no soporta el protocolo de enlace',
        retryable: false,
      );
    }

    final NodosLinkResponse response;
    try {
      response = NodosLinkResponse.fromBytes(responseBytes);
    } catch (_) {
      await abort(remoteId);
      throw const BleConnectionHandshakeFailure(
        message: 'La respuesta de enlace recibida no es válida',
        retryable: false,
      );
    }

    final localUuid = localUser.uuid.trim();
    final remoteUuid = identity.uuid.trim();
    if (response.requesterUuid.trim() != localUuid ||
        response.responderUuid.trim() != remoteUuid) {
      await abort(remoteId);
      throw const BleConnectionHandshakeFailure(
        message: 'La respuesta de enlace no corresponde a esta solicitud',
        retryable: false,
      );
    }

    if (!response.accepted) {
      onProgress(LinkRejected(remoteId: remoteId, identity: identity));
      await abort(remoteId);
      return const BleConnectionHandshakeResult(genericDevice: false);
    }

    try {
      await _persistNodosConnection(
        myNodeId: myNodeId,
        remoteNodeId: canonicalRemoteNode.id!,
      );
    } catch (error) {
      await abort(remoteId);
      throw BleConnectionHandshakeFailure(
        message: 'No se pudo persistir el enlace Nodos aceptado: $error',
        retryable: true,
      );
    }

    onProgress(ConnectionPersisted(remoteId));
    await _safeMarkConnected(remoteId);
    _sessionManager.activate(identity.uuid, remoteId: remoteId);
    await _trySendLocalGraph(remoteId);
    await _tryReceiveRemoteGraph(remoteId: remoteId, identity: identity);
    await _subscribeToRemoteGraph(remoteId: remoteId, identity: identity);

    return const BleConnectionHandshakeResult(genericDevice: false);
  }

  Future<void> _persistGenericConnection({
    required String remoteId,
    required int? myNodeId,
    required void Function(BleConnectionHandshakeProgress progress) onProgress,
  }) async {
    try {
      final remoteNode = await _nodeRepository.getNodeByBleAddress(remoteId);
      if (remoteNode == null || remoteNode.id == null) return;

      await _connectionRepo.saveConnection(myNodeId!, remoteNode.id!);
      onProgress(ConnectionPersisted(remoteId));
    } catch (_) {
      // BLE genérico conserva el comportamiento tolerante.
    }
  }

  Future<void> _persistNodosConnection({
    required int? myNodeId,
    required int remoteNodeId,
  }) async {
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

  Future<Node?> _reconcileNodosIdentity({
    required String remoteId,
    required NodosIdentity identity,
  }) async {
    final remoteNode = await _nodeRepository.getNodeByBleAddress(remoteId);
    if (remoteNode == null || remoteNode.id == null) return null;

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

      if (_liveGraphSync != null) {
        await _liveGraphSync.sendInitialSnapshot(
          remoteId: remoteId,
          payload: payload,
        );
        return;
      }

      await _connectionRepo.writeCharacteristic(
        remoteId,
        peerGraphCharacteristicUUID,
        payload.toBytes(),
      );
    } catch (_) {
      // El intercambio del grafo es adicional al enlace ya aceptado.
    }
  }

  Future<void> _safeMarkConnected(String remoteId) async {
    try {
      await _activeGraphExchange.markConnected(remoteId);
    } catch (_) {
      // Un error publicando el snapshot no debe derribar el transporte GATT.
    }
  }

  Future<void> _tryReceiveRemoteGraph({
    required String remoteId,
    required NodosIdentity identity,
  }) async {
    if (!_sessionManager.isAuthorized(identity.uuid)) return;

    try {
      final graphBytes = await _connectionRepo.readCharacteristic(
        remoteId,
        graphCharacteristicUUID,
      );
      if (graphBytes == null || graphBytes.isEmpty) return;

      await _replaceRemoteGraph(graphBytes, identity);
    } catch (_) {
      // Fallo de transporte != snapshot vacío.
    }
  }

  Future<void> _subscribeToRemoteGraph({
    required String remoteId,
    required NodosIdentity identity,
  }) async {
    await cancelRemoteGraph(remoteId);

    try {
      final stream = _connectionRepo.characteristicValueStream(
        remoteId,
        graphCharacteristicUUID,
      );
      _graphSubscriptions[remoteId] = stream.listen(
        (bytes) => unawaited(_replaceRemoteGraph(bytes, identity)),
        onError: (Object error, StackTrace stackTrace) {
          // GATT connectionState remains the authority for disconnects.
        },
      );
    } catch (_) {
      // Older transports may not expose characteristic notifications.
    }
  }

  Future<void> _replaceRemoteGraph(
    List<int> graphBytes,
    NodosIdentity identity,
  ) async {
    if (graphBytes.isEmpty || !_sessionManager.isAuthorized(identity.uuid)) {
      return;
    }

    try {
      final payload = NodosGraphPayload.fromBytes(graphBytes);
      if (payload.ownerUuid != identity.uuid) return;

      await _remoteRelationRepository.replaceSnapshot(
        reporterUuid: identity.uuid,
        connections: payload.connections,
      );
    } catch (_) {
      // Invalid or incomplete notifications are ignored safely.
    }
  }

  Future<void> cancelRemoteGraph(String remoteId) async {
    final subscription = _graphSubscriptions.remove(remoteId);
    await subscription?.cancel();
  }

  Future<void> dispose() async {
    final subscriptions = _graphSubscriptions.values.toList();
    _graphSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

class LinkRejected extends BleConnectionHandshakeProgress {
  final String remoteId;
  final NodosIdentity identity;

  const LinkRejected({required this.remoteId, required this.identity});
}
