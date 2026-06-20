import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';

/// Implementación stub para verificar la interfaz [BleGattDataSource].
///
/// Cada método almacena los parámetros recibidos para que los tests
/// puedan validar que se llamaron correctamente.
class _StubGattDataSource extends BleGattDataSource {
  String? lastConnectedRemoteId;
  String? lastDisconnectedRemoteId;
  String? lastIsConnectedRemoteId;
  String? lastConnectionStateRemoteId;

  final _connectCompleter = Completer<void>();
  final _disconnectCompleter = Completer<void>();
  bool _isConnectedResult = false;
  final _connectionStateController = StreamController<bool>.broadcast();

  @override
  Future<void> connect(String remoteId) async {
    lastConnectedRemoteId = remoteId;
    await _connectCompleter.future;
  }

  @override
  Future<void> disconnect(String remoteId) async {
    lastDisconnectedRemoteId = remoteId;
    await _disconnectCompleter.future;
  }

  @override
  Future<bool> isConnected(String remoteId) async {
    lastIsConnectedRemoteId = remoteId;
    return _isConnectedResult;
  }

  @override
  Stream<bool> connectionState(String remoteId) {
    lastConnectionStateRemoteId = remoteId;
    return _connectionStateController.stream;
  }
}

void main() {
  group('BleGattDataSource', () {
    late _StubGattDataSource datasource;

    setUp(() {
      datasource = _StubGattDataSource();
    });

    // ─────────────── connect ───────────────
    test('connect recibe remoteId como parámetro', () async {
      final id = 'AA:BB:CC:DD:EE:FF';
      datasource._connectCompleter.complete(); // desbloquea el future

      await datasource.connect(id);

      expect(datasource.lastConnectedRemoteId, equals(id));
    });

    // ─────────────── disconnect ───────────────
    test('disconnect recibe remoteId como parámetro', () async {
      final id = '11:22:33:44:55:66';
      datasource._disconnectCompleter.complete();

      await datasource.disconnect(id);

      expect(datasource.lastDisconnectedRemoteId, equals(id));
    });

    // ─────────────── isConnected ───────────────
    test('isConnected retorna false por defecto', () async {
      final result = await datasource.isConnected('any-id');

      expect(result, isFalse);
    });

    test('isConnected retorna true cuando el stub está configurado', () async {
      datasource._isConnectedResult = true;

      final result = await datasource.isConnected('any-id');

      expect(result, isTrue);
    });

    // ─────────────── connectionState ───────────────
    test('connectionState emite valores booleanos del stream', () async {
      final stream = datasource.connectionState('device-123');

      // Escuchar primero, luego emitir — garantiza que el listener reciba el evento.
      final future = stream.first;
      datasource._connectionStateController.add(true);

      final emitted = await future;

      expect(emitted, isTrue);
      expect(datasource.lastConnectionStateRemoteId, equals('device-123'));
    });

    test('connectionState emite false al desconectar', () async {
      final stream = datasource.connectionState('device-456');

      final future = stream.first;
      datasource._connectionStateController.add(false);

      final emitted = await future;

      expect(emitted, isFalse);
      expect(datasource.lastConnectionStateRemoteId, equals('device-456'));
    });
  });
}
