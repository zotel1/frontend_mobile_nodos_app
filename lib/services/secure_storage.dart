import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:frontend_mobile_nodos_app/core/utils/uuid_generator.dart';

/// Persistence contract for the device UUID.
///
/// Implementations must provide key-value storage primitives.
/// The [getOrCreateDeviceUuid] orchestration is shared across all backends.
abstract class SecureStorage {
  /// Writes the device UUID to persistent storage.
  Future<void> saveDeviceUuid(String uuid);

  /// Reads the device UUID from persistent storage.
  /// Returns `null` if no UUID has been saved yet.
  Future<String?> getDeviceUuid();

  /// Returns the existing device UUID, or generates and persists a new one.
  ///
  /// On first launch: generates a fresh UUIDv4, saves it, and returns it.
  /// On subsequent calls: returns the previously saved UUID.
  Future<String> getOrCreateDeviceUuid() async {
    final existing = await getDeviceUuid();
    if (existing != null) return existing;
    final newUuid = generateUuidV4();
    await saveDeviceUuid(newUuid);
    return newUuid;
  }

  /// Removes the stored device UUID. Used for testing and reset flows.
  Future<void> clearDeviceUuid();
}

/// Production implementation backed by [FlutterSecureStorage]
/// (Android Keystore / iOS Keychain).
class DefaultSecureStorage extends SecureStorage {
  static const _deviceUuidKey = 'device_uuid';
  final FlutterSecureStorage _storage;

  DefaultSecureStorage() : _storage = const FlutterSecureStorage();

  @override
  Future<void> saveDeviceUuid(String uuid) async {
    await _storage.write(key: _deviceUuidKey, value: uuid);
  }

  @override
  Future<String?> getDeviceUuid() async {
    return await _storage.read(key: _deviceUuidKey);
  }

  @override
  Future<void> clearDeviceUuid() async {
    await _storage.delete(key: _deviceUuidKey);
  }
}
