import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String uuid;
  final String name;
  final String color;
  final String deviceType;
  final DateTime createdAt;

  const User({
    required this.uuid,
    required this.name,
    required this.color,
    required this.deviceType,
    required this.createdAt,
  });

  @override
  List<Object> get props => [uuid, name, color, deviceType, createdAt];
}
