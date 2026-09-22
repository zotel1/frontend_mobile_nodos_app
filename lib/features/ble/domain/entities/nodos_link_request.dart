import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';

/// Solicitud de enlace enviada por una instalación Nodos a otra.
///
/// Este mensaje pertenece al protocolo de aplicación de Nodos.
/// No representa pairing ni bonding Bluetooth.
///
/// El requester se identifica mediante su [deviceUuid] estable y no mediante
/// IDs locales de SQLite ni direcciones BLE.
class NodosLinkRequest extends Equatable {
  const NodosLinkRequest({
    required this.deviceUuid,
    required this.name,
    required this.color,
    this.protocolVersion = nodosProtocolVersion,
  });

  final int protocolVersion;

  /// UUID estable de la instalación que solicita el enlace.
  final String deviceUuid;

  /// Nombre público configurado por el usuario solicitante.
  final String name;

  /// Color público configurado por el usuario solicitante.
  final String color;

  Map<String, dynamic> toJson() {
    return {
      'protocolVersion': protocolVersion,
      'deviceUuid': deviceUuid,
      'name': name,
      'color': color,
    };
  }

  Uint8List toBytes() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  factory NodosLinkRequest.fromJson(Map<String, dynamic> json) {
    final protocolVersion = json['protocolVersion'];
    final deviceUuid = json['deviceUuid'];
    final name = json['name'];
    final color = json['color'];

    if (protocolVersion is! int ||
        deviceUuid is! String ||
        name is! String ||
        color is! String) {
      throw const FormatException('NodosLinkRequest inválido.');
    }

    final normalizedUuid = deviceUuid.trim();
    final normalizedName = name.trim();
    final normalizedColor = color.trim();

    if (protocolVersion != nodosProtocolVersion) {
      throw FormatException(
        'Versión de protocolo Nodos no soportada: $protocolVersion.',
      );
    }

    if (normalizedUuid.isEmpty ||
        normalizedName.isEmpty ||
        normalizedColor.isEmpty) {
      throw const FormatException('NodosLinkRequest contiene campos vacíos.');
    }

    return NodosLinkRequest(
      protocolVersion: protocolVersion,
      deviceUuid: normalizedUuid,
      name: normalizedName,
      color: normalizedColor,
    );
  }

  factory NodosLinkRequest.fromBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('NodosLinkRequest vacío.');
    }

    final decoded = jsonDecode(utf8.decode(bytes));

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('NodosLinkRequest debe ser un objeto JSON.');
    }

    return NodosLinkRequest.fromJson(decoded);
  }

  @override
  List<Object?> get props => [protocolVersion, deviceUuid, name, color];
}
