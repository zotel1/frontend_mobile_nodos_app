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

/// Disparado periódicamente (cada 30s) para limpiar dispositivos
/// que no se han visto recientemente sin necesidad de nuevos datos BLE.
///
/// QUÉ hace: el handler [_onEvictStaleDevices] en BleBloc recorre
/// [_accumulatedDevices] y elimina aquellos cuyo [BleDevice.timestamp]
/// tiene más de 30 segundos de antigüedad.
///
/// POR QUÉ existe: sin este evento los dispositivos que se alejan
/// seguirían apareciendo en la UI hasta que 50 nuevos los desplacen
/// (cap). Con un timer cada 30s, la limpieza es proactiva incluso
/// cuando no hay nueva actividad BLE.
class EvictStaleDevices extends BleEvent {
  const EvictStaleDevices();
}
