import 'package:equatable/equatable.dart';

class User extends Equatable {
  final int? id;

  /// UUID estable de esta instalación de Nodos.
  ///
  /// No representa un ID de SQLite ni una dirección BLE.
  final String uuid;

  final String name;
  final String color;
  final String deviceType;
  final DateTime createdAt;

  /// FK lógica hacia Nodes.id que representa al dispositivo local.
  ///
  /// Puede ser null durante migraciones o antes de ejecutar
  /// EnsureLocalNode. En operación normal debe apuntar al único
  /// Node con isSelf=true.
  final int? localNodeId;

  const User({
    this.id,
    required this.uuid,
    required this.name,
    required this.color,
    required this.deviceType,
    required this.createdAt,
    this.localNodeId,
  });

  @override
  List<Object?> get props => [
    id,
    uuid,
    name,
    color,
    deviceType,
    createdAt,
    localNodeId,
  ];

  User copyWith({
    int? id,
    String? uuid,
    String? name,
    String? color,
    String? deviceType,
    DateTime? createdAt,
    int? localNodeId,
    bool clearLocalNodeId = false,
  }) {
    return User(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      color: color ?? this.color,
      deviceType: deviceType ?? this.deviceType,
      createdAt: createdAt ?? this.createdAt,
      localNodeId: clearLocalNodeId ? null : (localNodeId ?? this.localNodeId),
    );
  }
}
