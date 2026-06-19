import 'package:equatable/equatable.dart';

abstract class BleEvent extends Equatable {
  const BleEvent();

  @override
  List<Object?> get props => [];
}

class StartScan extends BleEvent {
  const StartScan();
}

class StopScan extends BleEvent {
  const StopScan();
}

class StartAdvertise extends BleEvent {
  final String deviceUuid;

  const StartAdvertise(this.deviceUuid);

  @override
  List<Object> get props => [deviceUuid];
}

class StopAdvertise extends BleEvent {
  const StopAdvertise();
}

class BluetoothStateChanged extends BleEvent {
  final bool isOn;

  const BluetoothStateChanged(this.isOn);

  @override
  List<Object> get props => [isOn];
}
