import 'dart:async';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/domain/repositories/scan_session_repository.dart';

class BleRepositoryImpl implements BleRepository {
  final BleScannerDataSource _scanner;
  final BleAdvertiserDataSource _advertiser;
  final ScanSessionRepository? _sessionRepository;

  BleRepositoryImpl({
    required BleScannerDataSource scanner,
    required BleAdvertiserDataSource advertiser,
    ScanSessionRepository? sessionRepository,
  })  : _scanner = scanner,
        _advertiser = advertiser,
        _sessionRepository = sessionRepository;

  @override
  Stream<List<BleDevice>> get scanResults => _scanner.scanResults;

  /// Inicia escaneo promiscuo sin filtro UUID para detectar
  /// cualquier dispositivo BLE en rango, no solo los que anuncian
  /// el UUID Nodos.
  ///
  /// QUÉ cambió: serviceUuids: null en lugar de [serviceUuid].
  /// POR QUÉ: flutter_ble_peripheral es stub — nadie anuncia
  /// el UUID Nodos, por lo que el filtro previo resultaba en
  /// cero detecciones. El escaneo promiscuo detecta todo BLE.
  @override
  Future<void> startScan() => _scanner.startScan(
        serviceUuids: null,
      );

  @override
  Future<void> stopScan() => _scanner.stopScan();

  /// Inicia el advertising BLE con los metadatos de identidad.
  ///
  /// Delega en el datasource [BleAdvertiserDataSource] con
  /// deviceUuid, name y color para que otros dispositivos Nodos
  /// detecten este dispositivo vía escaneo BLE.
  @override
  Future<void> startAdvertise(
          String deviceUuid, String name, String color) =>
      _advertiser.startAdvertise(deviceUuid, name, color);

  @override
  Future<void> stopAdvertise() => _advertiser.stopAdvertise();

  /// Delegación directa al scanner: el stream de estado BT viene
  /// de [FlutterBluePlusDataSource.bluetoothState], que a su vez
  /// deriva de [FlutterBluePlus.adapterState].
  @override
  Stream<bool> get bluetoothState => _scanner.bluetoothState;

  /// Cierra la sesión de escaneo activa delegando al
  /// [ScanSessionRepository].
  ///
  /// QUÉ hace: busca la sesión activa (endedAt=null) y la cierra
  /// estableciendo endedAt=now().
  ///
  /// POR QUÉ: completa el ciclo de vida de la sesión cuando el
  /// escaneo se detiene, permitiendo al historial distinguir
  /// sesiones finalizadas de activas.
  ///
  /// Lanza [StateError] si no se inyectó [ScanSessionRepository].
  @override
  Future<void> endScanSession() async {
    if (_sessionRepository == null) {
      throw StateError(
        'ScanSessionRepository no fue inyectado en BleRepositoryImpl',
      );
    }
    final activeId = await _sessionRepository.getActiveSession();
    if (activeId != null) {
      await _sessionRepository.endSession(activeId);
    }
  }
}
