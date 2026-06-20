import 'package:equatable/equatable.dart';

class User extends Equatable {
  final int? id;
  final String uuid;
  final String name;
  final String color;
  final String deviceType;
  final DateTime createdAt;

  const User({
    this.id,
    required this.uuid,
    required this.name,
    required this.color,
    required this.deviceType,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, uuid, name, color, deviceType, createdAt];

  User copyWith({
    int? id,
    String? uuid,
    String? name,
    String? color,
    String? deviceType,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      color: color ?? this.color,
      deviceType: deviceType ?? this.deviceType,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
