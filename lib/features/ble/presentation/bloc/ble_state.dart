import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';

abstract class BleState extends Equatable {
  const BleState();

  @override
  List<Object?> get props => [];
}

class BleInitial extends BleState {
  const BleInitial();
}

class BleScanning extends BleState {
  final List<BleDevice> devices;

  const BleScanning({this.devices = const []});

  @override
  List<Object> get props => [devices];
}

class BleStopped extends BleState {
  const BleStopped();
}

class BleAdvertising extends BleState {
  const BleAdvertising();
}

class BleError extends BleState {
  final String message;

  const BleError(this.message);

  @override
  List<Object> get props => [message];
}

class BluetoothOff extends BleState {
  const BluetoothOff();
}
