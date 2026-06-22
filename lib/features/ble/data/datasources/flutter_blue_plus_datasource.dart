import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/core/utils/device_classifier.dart';
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
      // PR6a: Sin filtro RSSI en datasource — todos los dispositivos
      // se persisten. El filtrado por proximidad ocurre en la capa
      // de presentación (toggle "Mostrar solo cercanos").
      // REQ-PR6a-004.
      final mapped = results.map(mapScanResultToDevice).toList();
      if (mapped.isNotEmpty) {
        _controller.add(mapped);
      }
    });
  }

  /// Sin filtro RSSI: todos los dispositivos se persisten.
  ///
  /// QUÉ cambió (PR6a): antes filtraba con [proximityThresholdFar] (-95 dBm).
  /// Ahora siempre retorna true — el filtrado se delegó a la capa de
  /// presentación para que el usuario decida qué dispositivos ver.
  ///
  /// Se mantiene como método público para compatibilidad con tests existentes.
  /// REQ-PR6a-004.
  @visibleForTesting
  static bool rssiPassesFilter(int rssi) => true;

  /// Convierte un [ScanResult] de flutter_blue_plus en un [BleDevice] de dominio.
  ///
  /// QUÉ hace: extrae todos los campos relevantes del advertisement BLE y los
  /// mapea a la entidad de dominio, incluyendo txPowerLevel para cálculo de
  /// distancia más preciso, advName/platformName para identidad, y
  /// serviceUuids/connectable para clasificación.
  ///
  /// POR QUÉ es estático y público: permite testear el mapeo unitariamente
  /// sin depender de FlutterBluePlus platform (Extract-Before-Mock).
  @visibleForTesting
  static BleDevice mapScanResultToDevice(ScanResult r) {
    // Extraer service UUIDs como List<String> para el classifier
    final serviceUuidsStrings = r.advertisementData.serviceUuids.isNotEmpty
        ? r.advertisementData.serviceUuids
            .map((g) => g.toString())
            .toList()
        : <String>[];

    // Extraer manufacturer ID del primer entry en manufacturerData
    final manufacturerId = r.advertisementData.manufacturerData.isNotEmpty
        ? r.advertisementData.manufacturerData.keys.first
        : null;

    // F4: Clasificar el dispositivo usando los service UUIDs y
    // manufacturer ID. El classifier es estático y sync (~1μs).
    final deviceType =
        DeviceClassifier.classify(serviceUuidsStrings, manufacturerId);

    return BleDevice(
      deviceId: r.device.remoteId.toString(),
      deviceUuid: null,
      rssi: r.rssi,
      distance: rssiToDistance(r.rssi,
          txPowerLevel: r.advertisementData.txPowerLevel),
      proximity: rssiToProximity(r.rssi),
      timestamp: r.timeStamp,
      advName: r.advertisementData.advName,
      platformName: r.device.platformName,
      txPowerLevel: r.advertisementData.txPowerLevel,
      connectable: r.advertisementData.connectable,
      serviceUuids: serviceUuidsStrings.isNotEmpty ? serviceUuidsStrings : null,
      deviceType: deviceType,
    );
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

  /// Expone si el StreamController interno está cerrado.
  ///
  /// QUÉ: permite a los tests verificar que dispose() efectivamente
  /// cerró el controller sin necesidad de acceder al campo privado.
  @visibleForTesting
  bool get isControllerClosed => _controller.isClosed;

  /// Libera los recursos del datasource: cierra el StreamController
  /// y cancela la suscripción de escaneo BLE.
  ///
  /// QUÉ: llama _controller.close() (con try/catch para idempotencia)
  /// y _scanSub?.cancel() para detener el listener de plataforma.
  ///
  /// POR QUÉ: el StreamController nunca se cerraba, causando un
  /// memory leak (P1). El try/catch garantiza que llamar dispose()
  /// dos veces no lance StateError (idempotente).
  ///
  /// CUÁNDO usarlo: cuando el datasource ya no se necesita (ej. al
  /// cerrar la sesión de escaneo o al desmontar la feature de BLE).
  @override
  void dispose() {
    // Cancelar suscripción de scan BLE (puede ser null en test mode).
    _scanSub?.cancel();
    _scanSub = null;

    // Cerrar StreamController. Usamos try/catch en lugar de chequear
    // _controller.isClosed porque:
    //   - Evita race condition entre el chequeo y el close().
    //   - El comportamiento ante un close() fallido es el mismo (no-op).
    //   - La primera llamada siempre cierra; la segunda atrapa StateError.
    try {
      _controller.close();
    } catch (_) {
      // Controller ya cerrado — no-op. Esto hace al método idempotente.
    }
  }
}
