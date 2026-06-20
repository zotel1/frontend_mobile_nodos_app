import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';

/// Implementación concreta de [BleGattDataSource] usando flutter_blue_plus.
///
/// QUÉ hace: reconstruye una referencia [BluetoothDevice] desde el remoteId
/// y delega las operaciones connect/disconnect a las APIs nativas de FBPlus.
///
/// POR QUÉ separar datasource de BLoC: el BLoC solo depende de la interfaz
/// [BleGattDataSource], lo que permite testear la máquina de estados con
/// mocks sin necesidad de hardware BLE real (Clean Architecture).
///
/// Conexión: usa [License.nonprofit] y timeout de 10 segundos (R5.5, R5.7).
class FlutterBluePlusGattDataSource implements BleGattDataSource {
  // ── Funciones inyectables para testing ──
  final Future<void> Function(String remoteId) _connectFn;
  final Future<void> Function(String remoteId) _disconnectFn;
  final Stream<bool> Function(String remoteId) _connectionStateFn;

  /// Último valor emitido por el stream de estado de conexión para cada device.
  /// Usado por [isConnected] para retornar el estado actual sin esperar.
  final Map<String, bool> _lastConnectionState = {};

  /// Constructor de producción — usa las APIs reales de flutter_blue_plus.
  FlutterBluePlusGattDataSource()
      : _connectFn = _defaultConnect,
        _disconnectFn = _defaultDisconnect,
        _connectionStateFn = _defaultConnectionState;

  /// Constructor de testing — inyecta funciones mock para cada operación.
  ///
  /// Permite verificar que el datasource delega correctamente sin depender
  /// de la plataforma BLE real.
  @visibleForTesting
  FlutterBluePlusGattDataSource.test({
    required Future<void> Function(String remoteId) connectFn,
    required Future<void> Function(String remoteId) disconnectFn,
    required Stream<bool> Function(String remoteId) connectionStateFn,
  })  : _connectFn = connectFn,
        _disconnectFn = disconnectFn,
        _connectionStateFn = connectionStateFn;

  // ── Implementaciones por defecto (producción) ──

  /// Conecta al dispositivo reconstructo desde [remoteId].
  ///
  /// Usa [BluetoothDevice.fromId] (O(1) string parse, AD5), timeout de
  /// 10 segundos, autoConnect=false, y [License.nonprofit].
  static Future<void> _defaultConnect(String remoteId) async {
    final device = BluetoothDevice.fromId(remoteId);
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 10),
      autoConnect: false,
    );
  }

  /// Desconecta del dispositivo reconstruido desde [remoteId].
  static Future<void> _defaultDisconnect(String remoteId) async {
    final device = BluetoothDevice.fromId(remoteId);
    await device.disconnect();
  }

  /// Stream del estado de conexión del dispositivo.
  ///
  /// Mapea [BluetoothConnectionState] → `bool` (connected = true).
  static Stream<bool> _defaultConnectionState(String remoteId) {
    final device = BluetoothDevice.fromId(remoteId);
    return device.connectionState.map(
      (s) => s == BluetoothConnectionState.connected,
    );
  }

  // ── Interfaz pública ──

  @override
  Future<void> connect(String remoteId) => _connectFn(remoteId);

  @override
  Future<void> disconnect(String remoteId) => _disconnectFn(remoteId);

  @override
  Future<bool> isConnected(String remoteId) async {
    // Retorna el último estado conocido o false si nunca se monitoreó.
    return _lastConnectionState[remoteId] ?? false;
  }

  @override
  Stream<bool> connectionState(String remoteId) {
    final stream = _connectionStateFn(remoteId);

    // Actualiza el último estado conocido para isConnected().
    return stream.map((connected) {
      _lastConnectionState[remoteId] = connected;
      return connected;
    });
  }
}
