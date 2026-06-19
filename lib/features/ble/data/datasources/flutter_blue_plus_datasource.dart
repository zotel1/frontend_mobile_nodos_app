import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show FlutterBluePlus, Guid, BluetoothAdapterState;
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

class FlutterBluePlusDataSource implements BleScannerDataSource {
  final StreamController<List<BleDevice>> _controller;
  StreamSubscription? _scanSub;
  bool _isScanning = false;
  final bool _isTestMode;

  /// Stream del estado del adaptador Bluetooth.
  /// En producción se deriva de [FlutterBluePlus.adapterState].
  /// En modo test se inyecta como parámetro opcional.
  Stream<bool>? _btStateStream;

  /// Production constructor — binds to [FlutterBluePlus] platform.
  FlutterBluePlusDataSource()
      : _controller = StreamController<List<BleDevice>>.broadcast(),
        _isTestMode = false {
    _bindToPlatform();
    _btStateStream = FlutterBluePlus.adapterState
        .map((s) => s == BluetoothAdapterState.on);
  }

  /// Test constructor — inject pre-built scan results and optional BT state.
  @visibleForTesting
  FlutterBluePlusDataSource.test(
    Stream<List<BleDevice>> stream, {
    Stream<bool>? btStateStream,
  })  : _controller = StreamController<List<BleDevice>>.broadcast(),
        _isTestMode = true,
        _btStateStream = btStateStream {
    stream.listen((results) {
      if (results.isNotEmpty) {
        _controller.add(results);
      }
    });
  }

  void _bindToPlatform() {
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isEmpty) return;
      final mapped = results
          .map((r) => BleDevice(
                deviceId: r.device.remoteId.toString(),
                deviceUuid: null,
                rssi: r.rssi,
                distance: rssiToDistance(r.rssi),
                proximity: rssiToProximity(r.rssi),
                timestamp: r.timeStamp,
              ))
          .where((s) => s.rssi >= proximityThresholdMedium)
          .toList();
      if (mapped.isNotEmpty) {
        _controller.add(mapped);
      }
    });
  }

  @override
  Stream<List<BleDevice>> get scanResults => _controller.stream;

  /// Expone el estado del adaptador Bluetooth como stream de bool.
  ///
  /// QUÉ hace: retorna true cuando el adaptador está encendido (`on`),
  /// false en cualquier otro estado.
  ///
  /// POR QUÉ: permite a la capa de presentación reaccionar al estado real
  /// del hardware en lugar de asumir que siempre está activo.
  @override
  Stream<bool> get bluetoothState =>
      _btStateStream ?? Stream.value(true);

  @override
  Future<void> startScan({List<String>? serviceUuids}) async {
    if (_isScanning) return;
    _isScanning = true;
    if (_isTestMode) return;

    // F2: Recrear listener de plataforma si fue cancelado en stopScan().
    // _bindToPlatform() tiene guard interno (if (_scanSub != null) return)
    // por lo que es seguro llamarlo incluso con listener activo.
    if (_scanSub == null) _bindToPlatform();

    // F3: try/catch — resetea _isScanning si la plataforma lanza error
    // para no dejar el scanner en estado muerto.
    try {
      await FlutterBluePlus.startScan(
        withServices: serviceUuids?.map((u) => Guid(u)).toList() ?? [],
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );
    } catch (_) {
      _isScanning = false;
      rethrow;
    }
  }

  @override
  Future<void> stopScan() async {
    if (!_isScanning) return;
    await _scanSub?.cancel();
    _scanSub = null;
    if (!_isTestMode) {
      await FlutterBluePlus.stopScan();
    }
    // F3: Reset explícito después del stop de plataforma.
    // Garantiza que incluso si la plataforma lanza, _isScanning
    // refleje el estado real para el próximo startScan().
    _isScanning = false;
  }
}
