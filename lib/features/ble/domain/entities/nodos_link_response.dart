import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';

/// Resultado de una solicitud de enlace entre instalaciones Nodos.
///
/// La respuesta vuelve por linkCharacteristicUUID mediante NOTIFY.
///
/// [accepted] representa exclusivamente la decisión tomada dentro de Nodos.
/// No representa el estado de pairing/bonding Bluetooth.
class NodosLinkResponse extends Equatable {
  const NodosLinkResponse({
    required this.requesterUuid,
    required this.responderUuid,
    required this.accepted,
    this.protocolVersion = nodosProtocolVersion,
  });

  final int protocolVersion;

  /// Instalación que originó la solicitud.
  final String requesterUuid;

  /// Instalación que aceptó o rechazó la solicitud.
  final String responderUuid;

  /// Resultado de la solicitud.
  final bool accepted;

  Map<String, dynamic> toJson() {
    return {
      'protocolVersion': protocolVersion,
      'requesterUuid': requesterUuid,
      'responderUuid': responderUuid,
      'accepted': accepted,
    };
  }

  Uint8List toBytes() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  factory NodosLinkResponse.fromJson(Map<String, dynamic> json) {
    final protocolVersion = json['protocolVersion'];
    final requesterUuid = json['requesterUuid'];
    final responderUuid = json['responderUuid'];
    final accepted = json['accepted'];

    if (protocolVersion is! int ||
        requesterUuid is! String ||
        responderUuid is! String ||
        accepted is! bool) {
      throw const FormatException('NodosLinkResponse inválido.');
    }

    final normalizedRequesterUuid = requesterUuid.trim();
    final normalizedResponderUuid = responderUuid.trim();

    if (protocolVersion != nodosProtocolVersion) {
      throw FormatException(
        'Versión de protocolo Nodos no soportada: $protocolVersion.',
      );
    }

    if (normalizedRequesterUuid.isEmpty || normalizedResponderUuid.isEmpty) {
      throw const FormatException('NodosLinkResponse contiene UUIDs vacíos.');
    }

    if (normalizedRequesterUuid == normalizedResponderUuid) {
      throw const FormatException(
        'Una instalación Nodos no puede responderse a sí misma.',
      );
    }

    return NodosLinkResponse(
      protocolVersion: protocolVersion,
      requesterUuid: normalizedRequesterUuid,
      responderUuid: normalizedResponderUuid,
      accepted: accepted,
    );
  }

  factory NodosLinkResponse.fromBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('NodosLinkResponse vacío.');
    }

    final decoded = jsonDecode(utf8.decode(bytes));

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('NodosLinkResponse debe ser un objeto JSON.');
    }

    return NodosLinkResponse.fromJson(decoded);
  }

  @override
  List<Object?> get props => [
    protocolVersion,
    requesterUuid,
    responderUuid,
    accepted,
  ];
}
