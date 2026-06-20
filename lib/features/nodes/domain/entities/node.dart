import 'package:equatable/equatable.dart';

class Node extends Equatable {
  final int? id;
  final String bleAddress;
  final String? name;
  final String? color;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final List<int> rssiHistory;

  /// Nombre sugerido desde el advertisement BLE (advName).
  /// Solo se asigna en la primera detección (freeze on first detection).
  /// No se sobreescribe en escaneos posteriores.
  final String? suggestedName;

  /// Tipo de dispositivo clasificado (ej: "Reloj/Fitness", "Nodo").
  /// Calculado por DeviceClassifier a partir de los service UUIDs.
  final String? deviceType;

  /// Si el dispositivo BLE acepta conexiones GATT.
  /// Se propaga desde [BleDevice.connectable] en el mapeo del BLoC.
  /// Por defecto false — solo true si el advertisement lo indica.
  final bool connectable;

  /// Distancia estimada en metros, calculada desde el último RSSI.
  /// Se computa en [NodeListBloc._onSyncBleDevices] usando [rssiToDistance].
  /// Null si no hay RSSI válido todavía.
  final double? estimatedDistance;

  /// Whether this node has been identified/named by the user.
  bool get isKnown => name != null;

  const Node({
    this.id,
    required this.bleAddress,
    this.name,
    this.color,
    required this.firstSeen,
    required this.lastSeen,
    this.rssiHistory = const [],
    this.suggestedName,
    this.deviceType,
    this.connectable = false,
    this.estimatedDistance,
  });

  @override
  List<Object?> get props => [
        id,
        bleAddress,
        name,
        color,
        firstSeen,
        lastSeen,
        rssiHistory,
        suggestedName,
        deviceType,
        connectable,
        estimatedDistance,
      ];
}
