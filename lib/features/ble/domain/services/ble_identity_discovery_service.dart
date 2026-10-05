import 'dart:async';

import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_identity.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';

/// Identifies a Nodos device without entering the linking protocol.
///
/// Discovery is deliberately serialized. A scan can expose many devices at
/// once, but opening many GATT connections in parallel is both unnecessary
/// and unsafe on mobile BLE stacks. This service only reads the identity
/// characteristic and always disconnects in a finally block.
class BleIdentityDiscoveryService {
  final BleGattDataSource _gatt;
  final NodeRepository _nodeRepository;
  final Set<String> _pendingDeviceIds = <String>{};

  Future<void> _queue = Future<void>.value();
  bool _disposed = false;

  BleIdentityDiscoveryService({
    required BleGattDataSource gatt,
    required NodeRepository nodeRepository,
  }) : _gatt = gatt,
       _nodeRepository = nodeRepository;

  Future<NodosIdentity?> identify(BleDevice device) {
    if (_disposed ||
        device.kind != BleDeviceKind.nodos ||
        !device.connectable ||
        !_pendingDeviceIds.add(device.deviceId)) {
      return Future<NodosIdentity?>.value(null);
    }

    final result = _queue.then((_) => _identifyNow(device));
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result.whenComplete(() => _pendingDeviceIds.remove(device.deviceId));
  }

  Future<NodosIdentity?> _identifyNow(BleDevice device) async {
    var connected = false;
    try {
      await _gatt.connect(device.deviceId);
      connected = true;
      await _gatt.discoverServices(device.deviceId);
      final bytes = await _gatt.readCharacteristic(
        device.deviceId,
        identityCharacteristicUUID,
      );
      if (bytes == null) return null;

      final identity = NodosIdentity.fromBytes(bytes);
      await _reconcile(device, identity);
      return identity;
    } catch (_) {
      // A device can disappear between scan and GATT connection. Discovery is
      // best effort; it must not make scanning or linking fail.
      return null;
    } finally {
      if (connected) {
        try {
          await _gatt.disconnect(device.deviceId);
        } catch (_) {
          // The platform may already have closed the temporary connection.
        }
      }
    }
  }

  Future<void> _reconcile(BleDevice device, NodosIdentity identity) async {
    var node = await _nodeRepository.getNodeByBleAddress(device.deviceId);
    if (node == null) {
      final now = DateTime.now();
      await _nodeRepository.upsertNode(
        Node(
          bleAddress: device.deviceId,
          firstSeen: now,
          lastSeen: now,
          rssiHistory: [device.rssi],
          deviceType: 'Nodo',
          connectable: device.connectable,
          estimatedDistance: device.distance,
        ),
      );
      node = await _nodeRepository.getNodeByBleAddress(device.deviceId);
    }

    final nodeId = node?.id;
    if (nodeId == null) return;

    // protocolVersion is validated by NodosIdentity. The existing `nodes`
    // schema stores the stable identity metadata, while the version remains
    // protocol compatibility information for this runtime discovery.
    await _nodeRepository.reconcileNodeIdentity(
      nodeId,
      deviceUuid: identity.uuid,
      name: identity.name,
      color: identity.color,
    );
  }

  void dispose() {
    _disposed = true;
  }
}
