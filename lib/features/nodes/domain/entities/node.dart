import 'package:equatable/equatable.dart';

class Node extends Equatable {
  /// ID real en la tabla nodes.
  final int? id;

  /// UUID estable de identidad Nodos.
  ///
  /// - Self node: contiene el UUID de esta instalación.
  /// - Otro dispositivo con Nodos: podrá contener su UUID cuando
  ///   ARCH-003 complete el protocolo de identidad.
  /// - BLE genérico: null.
  final String? deviceUuid;

  /// Identificador de transporte BLE observado localmente.
  ///
  /// En Android normalmente corresponde al remoteId expuesto por
  /// flutter_blue_plus.
  ///
  /// Es nullable porque el nodo local existe persistentemente aunque
  /// no necesite descubrirse a sí mismo mediante BLE.
  final String? bleAddress;

  /// Indica que este Node representa al dispositivo donde corre la app.
  ///
  /// Debe existir como máximo un nodo con isSelf=true.
  final bool isSelf;

  final String? name;
  final String? color;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final List<int> rssiHistory;

  /// Nombre sugerido desde el advertisement BLE (advName).
  /// Solo se asigna en la primera detección.
  final String? suggestedName;

  /// Tipo de dispositivo clasificado.
  final String? deviceType;

  /// Si el dispositivo BLE acepta conexiones GATT.
  final bool connectable;

  /// Distancia estimada en metros desde RSSI.
  final double? estimatedDistance;

  bool get isKnown => name != null;

  const Node({
    this.id,
    this.deviceUuid,
    this.bleAddress,
    this.isSelf = false,
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

  Node copyWith({
    int? id,
    String? deviceUuid,
    bool clearDeviceUuid = false,
    String? bleAddress,
    bool clearBleAddress = false,
    bool? isSelf,
    String? name,
    bool clearName = false,
    String? color,
    bool clearColor = false,
    DateTime? firstSeen,
    DateTime? lastSeen,
    List<int>? rssiHistory,
    String? suggestedName,
    bool clearSuggestedName = false,
    String? deviceType,
    bool clearDeviceType = false,
    bool? connectable,
    double? estimatedDistance,
    bool clearEstimatedDistance = false,
  }) {
    return Node(
      id: id ?? this.id,
      deviceUuid: clearDeviceUuid ? null : (deviceUuid ?? this.deviceUuid),
      bleAddress: clearBleAddress ? null : (bleAddress ?? this.bleAddress),
      isSelf: isSelf ?? this.isSelf,
      name: clearName ? null : (name ?? this.name),
      color: clearColor ? null : (color ?? this.color),
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      rssiHistory: rssiHistory ?? this.rssiHistory,
      suggestedName: clearSuggestedName
          ? null
          : (suggestedName ?? this.suggestedName),
      deviceType: clearDeviceType ? null : (deviceType ?? this.deviceType),
      connectable: connectable ?? this.connectable,
      estimatedDistance: clearEstimatedDistance
          ? null
          : (estimatedDistance ?? this.estimatedDistance),
    );
  }

  @override
  List<Object?> get props => [
    id,
    deviceUuid,
    bleAddress,
    isSelf,
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
