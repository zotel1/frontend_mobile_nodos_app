import 'dart:async';
import 'dart:convert';

import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/active_graph_exchange_service.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/graph_exchange_session_manager.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/transport/ble_frame_codec.dart';

/// Publishes local active snapshots to currently authorized central peers.
///
/// The peripheral path is handled by [ActiveGraphExchangeService], which
/// updates the advertised GATT characteristic. This service handles the
/// complementary central path by writing the peer graph characteristic.
class LiveGraphSyncService {
  final ActiveGraphExchangeService _activeGraphExchange;
  final GraphExchangeSessionManager _sessionManager;
  final BleConnectionRepository _connectionRepository;
  final BleMessageFramer _framer;

  StreamSubscription<NodosGraphPayload>? _snapshotSubscription;
  Future<void> _operationQueue = Future<void>.value();
  final Map<String, _SentSnapshot> _lastSentByRemoteId =
      <String, _SentSnapshot>{};
  bool _started = false;
  bool _disposed = false;

  LiveGraphSyncService({
    required ActiveGraphExchangeService activeGraphExchange,
    required GraphExchangeSessionManager sessionManager,
    required BleConnectionRepository connectionRepository,
    BleMessageFramer? framer,
  }) : _activeGraphExchange = activeGraphExchange,
       _sessionManager = sessionManager,
       _connectionRepository = connectionRepository,
       _framer = framer ?? BleMessageFramer();

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _snapshotSubscription = _activeGraphExchange.snapshotChanges.listen(
      (payload) => unawaited(_publishToActivePeers(payload)),
      onError: (Object error, StackTrace stackTrace) {
        // Snapshot notification failures must not terminate the subscription.
      },
    );
  }

  /// Sends the snapshot produced during the handshake to one central peer.
  ///
  /// The write is deduplicated with later live updates for the same runtime
  /// session, so activation does not cause an identical second write.
  Future<void> sendInitialSnapshot({
    required String remoteId,
    required NodosGraphPayload payload,
  }) {
    start();
    return _enqueue(() => _sendToPeer(remoteId, payload));
  }

  Future<void> _publishToActivePeers(NodosGraphPayload payload) {
    start();
    return _enqueue(() async {
      final activeSessions = List<GraphExchangeSession>.from(
        _sessionManager.activeSessions,
      );
      final activeRemoteIds = activeSessions
          .map((session) => session.remoteId)
          .whereType<String>()
          .toSet();

      _lastSentByRemoteId.removeWhere(
        (remoteId, _) => !activeRemoteIds.contains(remoteId),
      );

      for (final remoteId in activeRemoteIds) {
        try {
          await _sendToPeer(remoteId, payload);
        } catch (_) {
          // One peer must not block publication to the remaining peers.
        }
      }
    });
  }

  Future<void> _sendToPeer(String remoteId, NodosGraphPayload payload) async {
    final normalizedRemoteId = remoteId.trim();
    final session = _sessionManager.byRemoteId(normalizedRemoteId);
    if (normalizedRemoteId.isEmpty ||
        session == null ||
        session.state != GraphExchangeSessionState.active ||
        !session.connected) {
      return;
    }

    final payloadKey = base64Encode(payload.toBytes());
    final previous = _lastSentByRemoteId[normalizedRemoteId];
    if (previous?.payloadKey == payloadKey &&
        previous?.sessionUpdatedAt == session.updatedAt) {
      return;
    }

    final payloadBytes = payload.toBytes();
    final frames = _framer.frame(
      payloadBytes,
      mtu: await _connectionRepository.mtu(normalizedRemoteId),
    );

    for (final frame in frames) {
      final current = _sessionManager.byRemoteId(normalizedRemoteId);
      if (current == null ||
          current.state != GraphExchangeSessionState.active ||
          !current.connected ||
          current.updatedAt != session.updatedAt) {
        return;
      }

      final written = await _connectionRepository.writeCharacteristic(
        normalizedRemoteId,
        peerGraphCharacteristicUUID,
        frame,
      );
      if (!written) {
        throw StateError('BLE frame write rejected for $normalizedRemoteId');
      }
    }

    _lastSentByRemoteId[normalizedRemoteId] = _SentSnapshot(
      payloadKey: payloadKey,
      sessionUpdatedAt: session.updatedAt,
    );
  }

  Future<void> _run(Future<void> Function() operation) => operation();

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operationQueue.then<void>(
      (_) => _run(operation),
      onError: (Object error, StackTrace stackTrace) => _run(operation),
    );

    _operationQueue = next.catchError((Object error, StackTrace stackTrace) {
      // Keep future publications schedulable after a failed write.
    });

    return next;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _snapshotSubscription?.cancel();
    _snapshotSubscription = null;
    _lastSentByRemoteId.clear();
  }
}

class _SentSnapshot {
  final String payloadKey;
  final DateTime sessionUpdatedAt;

  const _SentSnapshot({
    required this.payloadKey,
    required this.sessionUpdatedAt,
  });
}
