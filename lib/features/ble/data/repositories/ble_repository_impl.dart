import 'dart:async';
import 'dart:typed_data';

import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/domain/repositories/scan_session_repository.dart';

class BleRepositoryImpl implements BleRepository {
  final BleScannerDataSource _scanner;
  final BleAdvertiserDataSource _advertiser;
  final ScanSessionRepository? _sessionRepository;

  BleRepositoryImpl({
    required BleScannerDataSource scanner,
    required BleAdvertiserDataSource advertiser,
    ScanSessionRepository? sessionRepository,
  }) : _scanner = scanner,
       _advertiser = advertiser,
       _sessionRepository = sessionRepository;

  @override
  Stream<List<BleDevice>> get scanResults => _scanner.scanResults;

  /// Inicia escaneo promiscuo sin filtro UUID para detectar
  /// cualquier dispositivo BLE en rango, no solo los que anuncian
  /// el UUID Nodos.
  ///
  /// QUÉ cambió: serviceUuids: null en lugar de [serviceUuid].
  /// POR QUÉ: el escaneo promiscuo permite detectar tanto instalaciones
  /// Nodos como dispositivos BLE genéricos.
  @override
  Future<void> startScan() => _scanner.startScan(serviceUuids: null);

  @override
  Future<void> stopScan() => _scanner.stopScan();

  /// Inicia el advertising BLE con los metadatos de identidad.
  ///
  /// Delega en [BleAdvertiserDataSource] para que otros dispositivos
  /// puedan descubrir esta instalación Nodos.
  @override
  Future<void> startAdvertise(String deviceUuid, String name, String color) =>
      _advertiser.startAdvertise(deviceUuid, name, color);

  /// Actualiza el snapshot del grafo activo que este dispositivo
  /// expone a otras instalaciones Nodos mediante GATT.
  ///
  /// El repository no interpreta ni modifica el payload. La capa
  /// superior es responsable de construir y serializar el snapshot.
  ///
  /// Esto permite actualizar las relaciones compartidas sin detener
  /// ni reiniciar el advertising BLE.
  @override
  Future<void> updateGraphPayload(Uint8List payload) =>
      _advertiser.updateGraphPayload(payload);

  @override
  Future<void> stopAdvertise() => _advertiser.stopAdvertise();

  /// Stream del estado actual del adaptador Bluetooth.
  @override
  Stream<bool> get bluetoothState => _scanner.bluetoothState;

  /// Cierra la sesión de escaneo activa delegando al
  /// [ScanSessionRepository].
  ///
  /// Busca la sesión activa (endedAt == null) y la finaliza.
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
