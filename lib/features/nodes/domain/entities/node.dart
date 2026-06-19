import 'package:equatable/equatable.dart';

class Node extends Equatable {
  final int? id;
  final String bleAddress;
  final String? name;
  final String? color;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final List<int> rssiHistory;

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
  });

  @override
  List<Object?> get props =>
      [id, bleAddress, name, color, firstSeen, lastSeen, rssiHistory];
}
