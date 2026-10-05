import 'package:equatable/equatable.dart';

enum GraphExchangeSessionState { pending, active, invalidated }

class GraphExchangeSession extends Equatable {
  final String peerUuid;
  final String? remoteId;
  final GraphExchangeSessionState state;
  final bool connected;
  final DateTime updatedAt;

  const GraphExchangeSession({
    required this.peerUuid,
    required this.remoteId,
    required this.state,
    required this.connected,
    required this.updatedAt,
  });

  GraphExchangeSession copyWith({
    String? remoteId,
    bool clearRemoteId = false,
    GraphExchangeSessionState? state,
    bool? connected,
    DateTime? updatedAt,
  }) {
    return GraphExchangeSession(
      peerUuid: peerUuid,
      remoteId: clearRemoteId ? null : (remoteId ?? this.remoteId),
      state: state ?? this.state,
      connected: connected ?? this.connected,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [peerUuid, remoteId, state, connected, updatedAt];
}

/// Owns the runtime authorization state for Graph Exchange, keyed by peer.
///
/// Sessions are intentionally in-memory. `connections` remains LINKED
/// persistence and must never be used to reconstruct an ACTIVE session.
class GraphExchangeSessionManager {
  final Map<String, GraphExchangeSession> _sessions = {};

  Iterable<GraphExchangeSession> get sessions =>
      List<GraphExchangeSession>.unmodifiable(_sessions.values);

  Iterable<GraphExchangeSession> get activeSessions => sessions.where(
    (session) =>
        session.state == GraphExchangeSessionState.active && session.connected,
  );

  GraphExchangeSession? byPeerUuid(String peerUuid) =>
      _sessions[_key(peerUuid)];

  GraphExchangeSession? byRemoteId(String remoteId) {
    final normalized = remoteId.trim();
    for (final session in _sessions.values) {
      if (session.remoteId == normalized) return session;
    }
    return null;
  }

  GraphExchangeSession registerPending(String peerUuid, {String? remoteId}) {
    final key = _key(peerUuid);
    final now = DateTime.now();
    final existing = _sessions[key];
    final session = GraphExchangeSession(
      peerUuid: peerUuid.trim(),
      remoteId: remoteId?.trim().isEmpty == true ? null : remoteId?.trim(),
      state: GraphExchangeSessionState.pending,
      connected: false,
      updatedAt: now,
    );
    _sessions[key] =
        existing != null && existing.state == GraphExchangeSessionState.active
        ? existing
        : session;
    return _sessions[key]!;
  }

  GraphExchangeSession activate(String peerUuid, {String? remoteId}) {
    final key = _key(peerUuid);
    final now = DateTime.now();
    final previous = _sessions[key];
    final session = GraphExchangeSession(
      peerUuid: peerUuid.trim(),
      remoteId: remoteId?.trim().isEmpty == true
          ? previous?.remoteId
          : remoteId?.trim(),
      state: GraphExchangeSessionState.active,
      connected: true,
      updatedAt: now,
    );
    _sessions[key] = session;
    return session;
  }

  bool isAuthorized(String peerUuid) {
    final session = byPeerUuid(peerUuid);
    return session != null &&
        session.state == GraphExchangeSessionState.active &&
        session.connected;
  }

  GraphExchangeSession? invalidatePeer(String peerUuid) {
    return _invalidate(_key(peerUuid));
  }

  GraphExchangeSession? invalidateByRemoteId(String remoteId) {
    final session = byRemoteId(remoteId);
    if (session == null) return null;
    return _invalidate(_key(session.peerUuid));
  }

  void clear() {
    final now = DateTime.now();
    for (final key in _sessions.keys.toList()) {
      _sessions[key] = _sessions[key]!.copyWith(
        state: GraphExchangeSessionState.invalidated,
        connected: false,
        updatedAt: now,
      );
    }
  }

  GraphExchangeSession? _invalidate(String key) {
    final session = _sessions[key];
    if (session == null) return null;
    final invalidated = session.copyWith(
      state: GraphExchangeSessionState.invalidated,
      connected: false,
      updatedAt: DateTime.now(),
    );
    _sessions[key] = invalidated;
    return invalidated;
  }

  String _key(String peerUuid) => peerUuid.trim();
}
