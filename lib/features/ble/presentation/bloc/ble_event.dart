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
  final String name;
  final String color;

  const StartAdvertise(this.deviceUuid, this.name, this.color);

  @override
  List<Object> get props => [deviceUuid, name, color];
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
