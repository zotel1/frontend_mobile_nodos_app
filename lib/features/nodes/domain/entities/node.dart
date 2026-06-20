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
  });

  @override
  List<Object?> get props =>
      [id, bleAddress, name, color, firstSeen, lastSeen, rssiHistory, suggestedName, deviceType];
}
