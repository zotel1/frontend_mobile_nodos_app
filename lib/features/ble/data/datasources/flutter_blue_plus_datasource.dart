import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:frontend_mobile_nodos_app/core/utils/device_classifier.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

class FlutterBluePlusDataSource implements BleScannerDataSource {
  final StreamController<List<BleDevice>> _controller;

  StreamSubscription<Object?>? _scanSub;

  /// BUG-005:
  /// Suscripción al estado REAL del scanner reportado por FlutterBluePlus.
  ///
  /// Permite detectar cuando FlutterBluePlus termina automáticamente
  /// un escaneo por timeout.
  StreamSubscription<bool>? _scanStateSub;

  bool _isScanning = false;

  final bool _isTestMode;

  /// Stream del estado del adaptador Bluetooth.
  ///
  /// En producción se deriva de FlutterBluePlus.adapterState.
  /// En modo test se puede inyectar.
  Stream<bool>? _btStateStream;

  /// BUG-005:
  /// Stream que representa el estado real del scanner.
  ///
  /// En producción usa FlutterBluePlus.isScanning.
  /// En tests puede inyectarse para simular:
  ///
  /// true  → plataforma escaneando
  /// false → plataforma detuvo el scan por timeout
  Stream<bool>? _scanStateStream;

  /// Production constructor.
  ///
  /// Conecta el datasource con FlutterBluePlus.
  FlutterBluePlusDataSource()
    : _controller = StreamController<List<BleDevice>>.broadcast(),
      _isTestMode = false {
    _bindToPlatform();

    _btStateStream = FlutterBluePlus.adapterState.map(
      (state) => state == BluetoothAdapterState.on,
    );

    // BUG-005:
    // FlutterBluePlus es la fuente de verdad del estado real del scanner.
    //
    // startScan() utiliza un timeout de 15 segundos. Cuando ese timeout
    // vence, FlutterBluePlus puede detener el scan internamente sin que
    // nuestro método stopScan() sea llamado.
    //
    // Antes de este fix, _isScanning permanecía en true y bloqueaba
    // posteriores intentos de startScan().
    _scanStateStream = FlutterBluePlus.isScanning;

    _bindScanState();
  }

  /// Test constructor.
  ///
  /// Permite inyectar:
  ///
  /// - stream de resultados BLE;
  /// - estado Bluetooth;
  /// - estado real del scanner.
  ///
  /// Esto permite reproducir BUG-005 sin depender del hardware Android.
  @visibleForTesting
  FlutterBluePlusDataSource.test(
    Stream<List<BleDevice>> stream, {
    Stream<bool>? btStateStream,
    Stream<bool>? scanStateStream,
  }) : _controller = StreamController<List<BleDevice>>.broadcast(),
       _isTestMode = true,
       _btStateStream = btStateStream,
       _scanStateStream = scanStateStream {
    stream.listen((results) {
      if (results.isNotEmpty) {
        _controller.add(results);
      }
    });

    // BUG-005:
    // También sincronizamos el flag interno durante tests.
    _bindScanState();
  }

  /// Se suscribe a los resultados reales de FlutterBluePlus.
  void _bindToPlatform() {
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isEmpty) {
        return;
      }

      // PR6a:
      // No filtramos por RSSI en datasource.
      // Todos los dispositivos detectados se persisten y el filtrado
      // visual se realiza posteriormente en presentación.
      final mapped = results.map(mapScanResultToDevice).toList();

      if (mapped.isNotEmpty) {
        _controller.add(mapped);
      }
    });
  }

  /// BUG-005:
  /// Sincroniza [_isScanning] con el estado REAL del scanner.
  ///
  /// Problema original:
  ///
  /// 1. startScan() establecía `_isScanning = true`.
  /// 2. FlutterBluePlus iniciaba un scan con timeout de 15 segundos.
  /// 3. La plataforma finalizaba automáticamente el scan.
  /// 4. Nuestro stopScan() NO era llamado.
  /// 5. `_isScanning` seguía en true.
  /// 6. El siguiente startScan() ejecutaba:
  ///
  ///     if (_isScanning) return;
  ///
  /// 7. El duty cycle quedaba bloqueado permanentemente.
  ///
  /// Con esta suscripción:
  ///
  /// plataforma true  → `_isScanning = true`
  /// plataforma false → `_isScanning = false`
  ///
  /// Por lo tanto el siguiente ciclo puede iniciar normalmente.
  void _bindScanState() {
    final stream = _scanStateStream;

    if (stream == null) {
      return;
    }

    _scanStateSub?.cancel();

    _scanStateSub = stream.listen((isScanning) {
      _isScanning = isScanning;
    });
  }

  /// Sin filtro RSSI: todos los dispositivos se persisten.
  ///
  /// PR6a:
  /// anteriormente el datasource descartaba señales demasiado débiles.
  ///
  /// Ahora el filtrado se realiza únicamente en presentación.
  @visibleForTesting
  static bool rssiPassesFilter(int rssi) => true;

  /// Convierte un ScanResult de FlutterBluePlus en BleDevice de dominio.
  @visibleForTesting
  static BleDevice mapScanResultToDevice(ScanResult r) {
    final serviceUuidsStrings = r.advertisementData.serviceUuids.isNotEmpty
        ? r.advertisementData.serviceUuids
              .map((guid) => guid.toString())
              .toList()
        : <String>[];

    final manufacturerId = r.advertisementData.manufacturerData.isNotEmpty
        ? r.advertisementData.manufacturerData.keys.first
        : null;

    final deviceType = DeviceClassifier.classify(
      serviceUuidsStrings,
      manufacturerId,
    );

    return BleDevice(
      deviceId: r.device.remoteId.toString(),
      deviceUuid: null,
      rssi: r.rssi,
      distance: rssiToDistance(
        r.rssi,
        txPowerLevel: r.advertisementData.txPowerLevel,
      ),
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

  /// Estado del adaptador Bluetooth.
  @override
  Stream<bool> get bluetoothState => _btStateStream ?? Stream.value(true);

  /// BUG-005:
  /// Getter visible para tests.
  ///
  /// Permite verificar que el flag interno representa el estado real
  /// de FlutterBluePlus después de un timeout.
  @visibleForTesting
  bool get isScanning => _isScanning;

  @override
  Future<void> startScan({List<String>? serviceUuids}) async {
    // Evitar iniciar dos scans simultáneamente.
    //
    // BUG-005:
    // Este guard ahora funciona correctamente porque _isScanning
    // es actualizado también por FlutterBluePlus.isScanning.
    if (_isScanning) {
      return;
    }

    _isScanning = true;

    // En test mode no existe plataforma real.
    // El estado posterior puede ser controlado mediante scanStateStream.
    if (_isTestMode) {
      return;
    }

    // Recrear listener si stopScan() lo canceló previamente.
    if (_scanSub == null) {
      _bindToPlatform();
    }

    try {
      await FlutterBluePlus.startScan(
        withServices: serviceUuids?.map((uuid) => Guid(uuid)).toList() ?? [],
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );
    } catch (_) {
      // Si FlutterBluePlus falla al iniciar el scan, liberar inmediatamente
      // el guard para permitir un próximo intento.
      _isScanning = false;
      rethrow;
    }
  }

  @override
  Future<void> stopScan() async {
    if (!_isScanning) {
      return;
    }

    await _scanSub?.cancel();
    _scanSub = null;

    try {
      if (!_isTestMode) {
        await FlutterBluePlus.stopScan();
      }
    } finally {
      // Debe resetearse incluso si stopScan() de plataforma lanza.
      _isScanning = false;
    }
  }

  /// Expone si el StreamController interno está cerrado.
  @visibleForTesting
  bool get isControllerClosed => _controller.isClosed;

  /// Libera todos los recursos del datasource.
  ///
  /// Cancela:
  ///
  /// - resultados BLE;
  /// - estado real del scanner;
  /// - StreamController interno.
  @override
  void dispose() {
    _scanSub?.cancel();
    _scanSub = null;

    _scanStateSub?.cancel();
    _scanStateSub = null;

    _isScanning = false;

    try {
      _controller.close();
    } catch (_) {
      // Controller ya cerrado.
      // Dispose debe ser idempotente.
    }
  }
}
