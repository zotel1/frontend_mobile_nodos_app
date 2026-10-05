import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/graph_exchange_session_manager.dart';

void main() {
  test('activates a pending peer and authorizes repeated snapshots', () {
    final manager = GraphExchangeSessionManager();

    final pending = manager.registerPending('peer-a', remoteId: 'remote-a');
    expect(pending.state, GraphExchangeSessionState.pending);
    expect(manager.isAuthorized('peer-a'), isFalse);

    final active = manager.activate('peer-a', remoteId: 'remote-a');
    expect(active.state, GraphExchangeSessionState.active);
    expect(active.connected, isTrue);
    expect(manager.isAuthorized('peer-a'), isTrue);
    expect(manager.isAuthorized('peer-a'), isTrue);
  });

  test('rejects peers without an active session', () {
    final manager = GraphExchangeSessionManager();

    expect(manager.isAuthorized('unknown-peer'), isFalse);
    expect(manager.byPeerUuid('unknown-peer'), isNull);
  });

  test('supports multiple peers and invalidates only one', () {
    final manager = GraphExchangeSessionManager();
    manager.activate('peer-a', remoteId: 'remote-a');
    manager.activate('peer-b', remoteId: 'remote-b');

    expect(manager.activeSessions, hasLength(2));

    manager.invalidatePeer('peer-a');

    expect(manager.isAuthorized('peer-a'), isFalse);
    expect(manager.isAuthorized('peer-b'), isTrue);
    expect(
      manager.byPeerUuid('peer-a')!.state,
      GraphExchangeSessionState.invalidated,
    );
  });

  test('disconnect invalidates by remoteId', () {
    final manager = GraphExchangeSessionManager();
    manager.activate('peer-a', remoteId: 'remote-a');

    manager.invalidateByRemoteId('remote-a');

    expect(manager.isAuthorized('peer-a'), isFalse);
    expect(manager.byRemoteId('remote-a')!.connected, isFalse);
  });

  test('updates the runtime transport id without changing peer identity', () {
    final manager = GraphExchangeSessionManager();
    manager.activate('peer-a', remoteId: 'AA:BB:CC:DD:EE:FF');

    final updated = manager.activate(
      'peer-a',
      remoteId: '6A7B0E4D-1234-4EAB-9ABC-1234567890AB',
    );

    expect(updated.peerUuid, 'peer-a');
    expect(updated.remoteId, '6A7B0E4D-1234-4EAB-9ABC-1234567890AB');
    expect(manager.byRemoteId('AA:BB:CC:DD:EE:FF'), isNull);
    expect(manager.isAuthorized('peer-a'), isTrue);
  });

  test('clear invalidates every active session idempotently', () {
    final manager = GraphExchangeSessionManager();
    manager.activate('peer-a', remoteId: 'remote-a');
    manager.activate('peer-b', remoteId: 'remote-b');

    manager.clear();
    manager.clear();

    expect(manager.activeSessions, isEmpty);
    expect(manager.sessions, hasLength(2));
  });

  test('a new manager does not restore persisted LINKED relationships', () {
    final firstRun = GraphExchangeSessionManager();
    firstRun.activate('historical-peer', remoteId: 'remote-old');

    final afterRestart = GraphExchangeSessionManager();

    expect(afterRestart.activeSessions, isEmpty);
    expect(afterRestart.sessions, isEmpty);
  });
}
