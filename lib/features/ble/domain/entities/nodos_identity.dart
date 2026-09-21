import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Identidad lógica de una instalación de Nodos.
///
/// Esta entidad forma parte del protocolo BLE de Nodos y no depende
/// de flutter_blue_plus ni de flutter_ble_peripheral.
///
/// El UUID identifica persistentemente a la instalación, mientras que
/// la dirección BLE puede cambiar según plataforma o configuración.
///
/// Protocolo v1:
///
/// {
///   "version": 1,
///   "uuid": "...",
///   "name": "...",
///   "color": "#RRGGBB"
/// }
class NodosIdentity extends Equatable {
  static const int currentVersion = 1;

  final int version;
  final String uuid;
  final String name;
  final String color;

  const NodosIdentity({
    this.version = currentVersion,
    required this.uuid,
    required this.name,
    required this.color,
  });

  Map<String, dynamic> toJson() {
    return {'version': version, 'uuid': uuid, 'name': name, 'color': color};
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }

  List<int> toBytes() {
    return utf8.encode(toJsonString());
  }

  factory NodosIdentity.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final uuid = json['uuid'];
    final name = json['name'];
    final color = json['color'];

    if (version is! int) {
      throw const FormatException('NodosIdentity.version debe ser un entero');
    }

    if (version != currentVersion) {
      throw FormatException(
        'Versión de protocolo Nodos no soportada: $version',
      );
    }

    if (uuid is! String || uuid.trim().isEmpty) {
      throw const FormatException('NodosIdentity.uuid inválido');
    }

    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('NodosIdentity.name inválido');
    }

    if (color is! String || color.trim().isEmpty) {
      throw const FormatException('NodosIdentity.color inválido');
    }

    return NodosIdentity(
      version: version,
      uuid: uuid,
      name: name,
      color: color,
    );
  }

  factory NodosIdentity.fromJsonString(String source) {
    final decoded = jsonDecode(source);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'El payload de identidad Nodos debe ser un objeto JSON',
      );
    }

    return NodosIdentity.fromJson(decoded);
  }

  factory NodosIdentity.fromBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('El payload de identidad Nodos está vacío');
    }

    return NodosIdentity.fromJsonString(utf8.decode(bytes));
  }

  @override
  List<Object?> get props => [version, uuid, name, color];
}
