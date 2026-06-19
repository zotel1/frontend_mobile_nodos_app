import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';

class BleBloc extends Bloc<BleEvent, BleState> {
  final BleRepository repository;
  StreamSubscription<List<BleDevice>>? _scanSubscription;
  StreamSubscription<bool>? _btSubscription;

  BleBloc({required this.repository}) : super(const BleInitial()) {
    on<StartScan>(_onStartScan);
    on<StopScan>(_onStopScan);
    on<StartAdvertise>(_onStartAdvertise);
    on<StopAdvertise>(_onStopAdvertise);
    on<BluetoothStateChanged>(_onBluetoothStateChanged);
    on<_ScanResultsUpdated>(_onScanResultsUpdated);
    on<_ScanError>(_onScanError);
  }

  Future<void> _onStartScan(StartScan event, Emitter<BleState> emit) async {
    try {
      await _scanSubscription?.cancel();
      _scanSubscription = repository.scanResults.listen(
        (devices) {
          if (!isClosed) {
            add(_ScanResultsUpdated(devices));
          }
        },
        onError: (error) {
          if (!isClosed) {
            add(_ScanError(error.toString()));
          }
        },
      );
      await repository.startScan();
      emit(const BleScanning());
    } catch (e) {
      emit(BleError(e.toString()));
    }
  }

  Future<void> _onStopScan(StopScan event, Emitter<BleState> emit) async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await repository.stopScan();
    emit(const BleStopped());
  }

  Future<void> _onStartAdvertise(
      StartAdvertise event, Emitter<BleState> emit) async {
    await repository.startAdvertise(event.deviceUuid);
    emit(const BleAdvertising());
  }

  Future<void> _onStopAdvertise(
      StopAdvertise event, Emitter<BleState> emit) async {
    await repository.stopAdvertise();
    emit(const BleStopped());
  }

  void _onBluetoothStateChanged(
      BluetoothStateChanged event, Emitter<BleState> emit) {
    if (event.isOn) {
      emit(const BleStopped());
    } else {
      emit(const BluetoothOff());
    }
  }

  void _onScanResultsUpdated(
      _ScanResultsUpdated event, Emitter<BleState> emit) {
    emit(BleScanning(devices: event.devices));
  }

  void _onScanError(_ScanError event, Emitter<BleState> emit) {
    emit(BleError(event.message));
  }

  @override
  Future<void> close() {
    _scanSubscription?.cancel();
    _btSubscription?.cancel();
    return super.close();
  }
}

/// Internal event for scan result updates.
class _ScanResultsUpdated extends BleEvent {
  final List<BleDevice> devices;

  const _ScanResultsUpdated(this.devices);

  @override
  List<Object> get props => [devices];
}

/// Internal event for scan stream errors.
class _ScanError extends BleEvent {
  final String message;

  const _ScanError(this.message);

  @override
  List<Object> get props => [message];
}
