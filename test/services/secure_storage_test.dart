import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/services/secure_storage.dart';

/// In-memory fake that implements [SecureStorage] for unit testing.
///
/// Backed by a [Map] instead of platform keychain/keystore,
/// so tests run without Flutter engine.
/// Inherits [SecureStorage.getOrCreateDeviceUuid] — the orchestration
/// logic lives in the shared abstract class.
class FakeSecureStorage extends SecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> saveDeviceUuid(String uuid) async {
    _store['device_uuid'] = uuid;
  }

  @override
  Future<String?> getDeviceUuid() async {
    return _store['device_uuid'];
  }

  @override
  Future<void> clearDeviceUuid() async {
    _store.remove('device_uuid');
  }
}

void main() {
  group('DID-001: Device UUID persistence', () {
    late FakeSecureStorage storage;

    setUp(() {
      storage = FakeSecureStorage();
    });

    test('first launch generates a new UUID and saves it', () async {
      // Initially, no UUID is stored.
      expect(await storage.getDeviceUuid(), isNull);

      final uuid = await storage.getOrCreateDeviceUuid();

      // Must be a valid 36-char UUID v4.
      expect(uuid, isNotNull);
      expect(uuid.length, 36);
      final uuidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(uuidPattern.hasMatch(uuid), isTrue);

      // The UUID must be persisted.
      expect(await storage.getDeviceUuid(), uuid);
    });

    test('relaunch returns the same previously saved UUID', () async {
      final first = await storage.getOrCreateDeviceUuid();
      final second = await storage.getOrCreateDeviceUuid();

      expect(first, second,
          reason: 'getOrCreateDeviceUuid must return the same UUID on every call');
      expect(await storage.getDeviceUuid(), first);
    });

    test('clearDeviceUuid removes the stored UUID and next call generates new', () async {
      final first = await storage.getOrCreateDeviceUuid();
      await storage.clearDeviceUuid();

      // After clear, the store should be empty.
      expect(await storage.getDeviceUuid(), isNull);

      // Next getOrCreate must generate a brand-new UUID.
      final second = await storage.getOrCreateDeviceUuid();
      expect(second, isNot(first),
          reason: 'After clear, a new UUID must be generated');
      expect(await storage.getDeviceUuid(), second);
    });

    test('saveDeviceUuid then getDeviceUuid returns exact value', () async {
      const testUuid = '11111111-1111-4111-a111-111111111111';
      await storage.saveDeviceUuid(testUuid);
      expect(await storage.getDeviceUuid(), testUuid);
    });
  });
}
