import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';

/// Implementación concreta de [BleGattDataSource] usando flutter_blue_plus.
///
/// QUÉ hace: reconstruye una referencia [BluetoothDevice] desde el remoteId
/// y delega las operaciones GATT a las APIs nativas de flutter_blue_plus.
///
/// POR QUÉ separar datasource de BLoC: el BLoC solo depende de la interfaz
/// [BleGattDataSource], lo que permite testear la máquina de estados con
/// mocks sin necesidad de hardware BLE real.
///
/// Esta capa solamente transporta bytes. No interpreta LinkRequest,
/// LinkResponse, NodosIdentity ni NodosGraphPayload.
///
/// Conexión: usa [License.nonprofit] y timeout de 10 segundos.
class FlutterBluePlusGattDataSource implements BleGattDataSource {
  // ── Funciones inyectables para testing ──

  final Future<void> Function(String remoteId) _connectFn;
  final Future<void> Function(String remoteId) _disconnectFn;
  final Stream<bool> Function(String remoteId) _connectionStateFn;
  final Future<List<BleServiceInfo>> Function(String remoteId)
  _discoverServicesFn;
  final Future<List<int>?> Function(String remoteId, String characteristicUuid)
  _readCharacteristicFn;
  final Future<bool> Function(
    String remoteId,
    String characteristicUuid,
    List<int> payload,
  )
  _writeCharacteristicFn;

  /// Último valor emitido por el stream de estado de conexión para cada device.
  ///
  /// Usado por [isConnected] para retornar el estado actual sin esperar.
  final Map<String, bool> _lastConnectionState = {};

  /// Constructor de producción — usa las APIs reales de flutter_blue_plus.
  FlutterBluePlusGattDataSource()
    : _connectFn = _defaultConnect,
      _disconnectFn = _defaultDisconnect,
      _connectionStateFn = _defaultConnectionState,
      _discoverServicesFn = _defaultDiscoverServices,
      _readCharacteristicFn = _defaultReadCharacteristic,
      _writeCharacteristicFn = _defaultWriteCharacteristic;

  /// Constructor de testing — inyecta funciones mock para cada operación.
  ///
  /// Permite verificar que el datasource delega correctamente sin depender
  /// de la plataforma BLE real.
  @visibleForTesting
  FlutterBluePlusGattDataSource.test({
    required Future<void> Function(String remoteId) connectFn,
    required Future<void> Function(String remoteId) disconnectFn,
    required Stream<bool> Function(String remoteId) connectionStateFn,
    required Future<List<BleServiceInfo>> Function(String remoteId)
    discoverServicesFn,
    required Future<List<int>?> Function(
      String remoteId,
      String characteristicUuid,
    )
    readCharacteristicFn,
    required Future<bool> Function(
      String remoteId,
      String characteristicUuid,
      List<int> payload,
    )
    writeCharacteristicFn,
  }) : _connectFn = connectFn,
       _disconnectFn = disconnectFn,
       _connectionStateFn = connectionStateFn,
       _discoverServicesFn = discoverServicesFn,
       _readCharacteristicFn = readCharacteristicFn,
       _writeCharacteristicFn = writeCharacteristicFn;

  // ── Implementaciones por defecto (producción) ──

  /// Conecta al dispositivo reconstruido desde [remoteId].
  ///
  /// Usa [BluetoothDevice.fromId], timeout de 10 segundos,
  /// autoConnect=false y [License.nonprofit].
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
  /// Mapea [BluetoothConnectionState] → `bool`.
  static Stream<bool> _defaultConnectionState(String remoteId) {
    final device = BluetoothDevice.fromId(remoteId);

    return device.connectionState.map(
      (state) => state == BluetoothConnectionState.connected,
    );
  }

  /// Descubre los servicios GATT del dispositivo reconstruido desde [remoteId].
  ///
  /// Mapea cada [BluetoothService] a [BleServiceInfo].
  static Future<List<BleServiceInfo>> _defaultDiscoverServices(
    String remoteId,
  ) async {
    final device = BluetoothDevice.fromId(remoteId);
    final services = await device.discoverServices();

    return services
        .map(
          (service) => BleServiceInfo(
            uuid: service.serviceUuid.toString(),
            characteristicUuids: service.characteristics
                .map(
                  (characteristic) =>
                      characteristic.characteristicUuid.toString(),
                )
                .toList(),
          ),
        )
        .toList();
  }

  /// Busca una característica GATT por UUID.
  ///
  /// flutter_blue_plus entrega las características dentro de los servicios
  /// descubiertos. Este helper centraliza la búsqueda para lectura y escritura.
  static Future<BluetoothCharacteristic?> _findCharacteristic(
    String remoteId,
    String characteristicUuid,
  ) async {
    final device = BluetoothDevice.fromId(remoteId);
    final services = await device.discoverServices();

    final normalizedUuid = characteristicUuid.toLowerCase();

    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.characteristicUuid.toString().toLowerCase() ==
            normalizedUuid) {
          return characteristic;
        }
      }
    }

    return null;
  }

  /// Lee el valor de una característica GATT del dispositivo reconstruido.
  ///
  /// Si la característica permite NOTIFY/INDICATE, primero se suscribe y
  /// espera el primer payload no vacío.
  ///
  /// Este comportamiento es necesario para las características Nodos donde
  /// el periférico responde a la suscripción mediante sendData().
  ///
  /// Si no llega una notificación dentro del timeout, intenta READ.
  ///
  /// Retorna null si la característica no existe o no puede obtenerse
  /// ningún valor.
  static Future<List<int>?> _defaultReadCharacteristic(
    String remoteId,
    String characteristicUuid,
  ) async {
    final target = await _findCharacteristic(remoteId, characteristicUuid);

    if (target == null) {
      return null;
    }

    if (target.properties.notify || target.properties.indicate) {
      try {
        await target.setNotifyValue(true);

        final value = await target.onValueReceived
            .firstWhere((bytes) => bytes.isNotEmpty)
            .timeout(const Duration(seconds: 3));

        return value;
      } on TimeoutException {
        // Si el periférico no envía nada, intentamos READ como fallback.
      } finally {
        try {
          await target.setNotifyValue(false);
        } catch (_) {
          // La conexión pudo haberse cerrado durante el proceso.
        }
      }
    }

    try {
      final value = await target.read();

      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// Escribe bytes en una característica GATT remota.
  ///
  /// Retorna false únicamente cuando la característica solicitada no existe.
  ///
  /// Los errores reales producidos por la operación de escritura se propagan
  /// al llamador para que las capas superiores puedan distinguir entre:
  ///
  /// - característica no disponible;
  /// - fallo real de transporte.
  static Future<bool> _defaultWriteCharacteristic(
    String remoteId,
    String characteristicUuid,
    List<int> payload,
  ) async {
    final target = await _findCharacteristic(remoteId, characteristicUuid);

    if (target == null) {
      return false;
    }

    if (!target.properties.write && !target.properties.writeWithoutResponse) {
      throw StateError(
        'La característica $characteristicUuid no admite escritura.',
      );
    }

    // Preferimos WRITE con respuesta cuando está disponible.
    //
    // Para mensajes de control como LinkRequest queremos confirmación GATT
    // de que la escritura fue procesada por la pila BLE antes de continuar.
    final withoutResponse =
        !target.properties.write && target.properties.writeWithoutResponse;

    await target.write(payload, withoutResponse: withoutResponse);

    return true;
  }

  // ── Interfaz pública ──

  @override
  Future<void> connect(String remoteId) => _connectFn(remoteId);

  @override
  Future<void> disconnect(String remoteId) => _disconnectFn(remoteId);

  @override
  Future<bool> isConnected(String remoteId) async {
    return _lastConnectionState[remoteId] ?? false;
  }

  @override
  Stream<bool> connectionState(String remoteId) {
    final stream = _connectionStateFn(remoteId);

    return stream.map((connected) {
      _lastConnectionState[remoteId] = connected;
      return connected;
    });
  }

  @override
  Future<List<BleServiceInfo>> discoverServices(String remoteId) =>
      _discoverServicesFn(remoteId);

  @override
  Future<List<int>?> readCharacteristic(
    String remoteId,
    String characteristicUuid,
  ) => _readCharacteristicFn(remoteId, characteristicUuid);

  @override
  Future<bool> writeCharacteristic(
    String remoteId,
    String characteristicUuid,
    List<int> payload,
  ) => _writeCharacteristicFn(remoteId, characteristicUuid, payload);
}
