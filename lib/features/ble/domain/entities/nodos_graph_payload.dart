import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Tipo de referencia utilizada por una relación compartida mediante
/// Graph Exchange.
///
/// [nodos] representa otra instalación de Nodos cuya identidad estable
/// conocemos mediante deviceUuid.
///
/// [generic] representa un dispositivo BLE genérico conocido localmente
/// por la instalación que publica el grafo.
enum NodosGraphNodeKind { nodos, generic }

/// Referencia transportable a uno de los extremos relacionados directamente
/// con el propietario de un [NodosGraphPayload].
///
/// Existen dos formas de identidad:
///
/// 1. Instalación Nodos:
///
///    ref = nodos:<deviceUuid>
///
/// 2. Dispositivo BLE genérico:
///
///    ref = local:<ownerUuid>:<localNodeId>
///
/// En el segundo caso [localNodeId] NO se interpreta como un identificador
/// global. Solo forma parte de una referencia namespaced por el UUID de la
/// instalación que publica el grafo.
///
/// Esto permite que otro teléfono represente, por ejemplo:
///
///   A25 ── JBL Charge 3
///
/// sin afirmar que puede identificar globalmente ese JBL ni fusionarlo
/// automáticamente con otro dispositivo de nombre similar.
class NodosGraphConnection extends Equatable {
  final String ref;
  final NodosGraphNodeKind kind;

  /// UUID estable cuando el extremo ejecuta Nodos.
  ///
  /// Debe existir cuando [kind] == [NodosGraphNodeKind.nodos].
  /// Debe ser null cuando [kind] == [NodosGraphNodeKind.generic].
  final String? deviceUuid;

  /// Nombre conocido por el dispositivo que publica el grafo.
  final String? name;

  /// Color de perfil cuando el extremo es otra instalación Nodos.
  final String? color;

  /// Tipo de dispositivo conocido por el reporter.
  ///
  /// Puede utilizarse para representar mejor nodos BLE genéricos.
  final String? deviceType;

  const NodosGraphConnection({
    required this.ref,
    required this.kind,
    this.deviceUuid,
    this.name,
    this.color,
    this.deviceType,
  });

  /// Construye una referencia para otra instalación Nodos.
  factory NodosGraphConnection.nodos({
    required String deviceUuid,
    String? name,
    String? color,
    String? deviceType,
  }) {
    final normalizedUuid = deviceUuid.trim();

    if (normalizedUuid.isEmpty) {
      throw const FormatException('NodosGraphConnection.deviceUuid inválido');
    }

    return NodosGraphConnection(
      ref: 'nodos:$normalizedUuid',
      kind: NodosGraphNodeKind.nodos,
      deviceUuid: normalizedUuid,
      name: _normalizeOptional(name),
      color: _normalizeOptional(color),
      deviceType: _normalizeOptional(deviceType),
    );
  }

  /// Construye una referencia namespaced para un BLE genérico.
  ///
  /// [localNodeId] pertenece exclusivamente a la base local del
  /// dispositivo identificado por [ownerUuid].
  factory NodosGraphConnection.generic({
    required String ownerUuid,
    required int localNodeId,
    String? name,
    String? deviceType,
  }) {
    final normalizedOwnerUuid = ownerUuid.trim();

    if (normalizedOwnerUuid.isEmpty) {
      throw const FormatException('NodosGraphConnection.ownerUuid inválido');
    }

    if (localNodeId <= 0) {
      throw const FormatException('NodosGraphConnection.localNodeId inválido');
    }

    return NodosGraphConnection(
      ref: 'local:$normalizedOwnerUuid:$localNodeId',
      kind: NodosGraphNodeKind.generic,
      name: _normalizeOptional(name),
      deviceType: _normalizeOptional(deviceType),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ref': ref,
      'kind': kind.name,
      if (deviceUuid != null) 'deviceUuid': deviceUuid,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (deviceType != null) 'deviceType': deviceType,
    };
  }

  factory NodosGraphConnection.fromJson(Map<String, dynamic> json) {
    final ref = json['ref'];
    final kindValue = json['kind'];
    final deviceUuid = json['deviceUuid'];
    final name = json['name'];
    final color = json['color'];
    final deviceType = json['deviceType'];

    if (ref is! String || ref.trim().isEmpty) {
      throw const FormatException('NodosGraphConnection.ref inválido');
    }

    if (kindValue is! String) {
      throw const FormatException('NodosGraphConnection.kind inválido');
    }

    final kind = switch (kindValue) {
      'nodos' => NodosGraphNodeKind.nodos,
      'generic' => NodosGraphNodeKind.generic,
      _ => throw FormatException(
        'Tipo de nodo remoto no soportado: $kindValue',
      ),
    };

    if (deviceUuid != null && deviceUuid is! String) {
      throw const FormatException('NodosGraphConnection.deviceUuid inválido');
    }

    if (name != null && name is! String) {
      throw const FormatException('NodosGraphConnection.name inválido');
    }

    if (color != null && color is! String) {
      throw const FormatException('NodosGraphConnection.color inválido');
    }

    if (deviceType != null && deviceType is! String) {
      throw const FormatException('NodosGraphConnection.deviceType inválido');
    }

    final normalizedRef = ref.trim();
    final normalizedDeviceUuid = _normalizeOptional(deviceUuid as String?);

    switch (kind) {
      case NodosGraphNodeKind.nodos:
        if (normalizedDeviceUuid == null) {
          throw const FormatException(
            'Una conexión Nodos debe incluir deviceUuid',
          );
        }

        final expectedRef = 'nodos:$normalizedDeviceUuid';

        if (normalizedRef != expectedRef) {
          throw FormatException(
            'Referencia Nodos inconsistente: $normalizedRef',
          );
        }

      case NodosGraphNodeKind.generic:
        if (normalizedDeviceUuid != null) {
          throw const FormatException(
            'Una conexión BLE genérica no debe incluir deviceUuid',
          );
        }

        if (!normalizedRef.startsWith('local:')) {
          throw FormatException(
            'Referencia BLE genérica inválida: $normalizedRef',
          );
        }

        final parts = normalizedRef.split(':');

        if (parts.length != 3 ||
            parts[1].trim().isEmpty ||
            int.tryParse(parts[2]) == null ||
            int.parse(parts[2]) <= 0) {
          throw FormatException(
            'Referencia BLE genérica inválida: $normalizedRef',
          );
        }
    }

    return NodosGraphConnection(
      ref: normalizedRef,
      kind: kind,
      deviceUuid: normalizedDeviceUuid,
      name: _normalizeOptional(name as String?),
      color: _normalizeOptional(color as String?),
      deviceType: _normalizeOptional(deviceType as String?),
    );
  }

  static String? _normalizeOptional(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  @override
  List<Object?> get props => [ref, kind, deviceUuid, name, color, deviceType];
}

/// Snapshot de las relaciones directas propias publicadas por una
/// instalación Nodos.
///
/// Protocolo v1:
///
/// {
///   "version": 1,
///   "ownerUuid": "uuid-a25",
///   "connections": [
///     {
///       "ref": "nodos:uuid-motorola",
///       "kind": "nodos",
///       "deviceUuid": "uuid-motorola",
///       "name": "Motorola",
///       "color": "#42A5F5"
///     },
///     {
///       "ref": "local:uuid-a25:42",
///       "kind": "generic",
///       "name": "JBL Charge 3",
///       "deviceType": "audio"
///     }
///   ]
/// }
///
/// REGLAS:
///
/// 1. Solo se publican relaciones directas propias.
/// 2. Las relaciones aprendidas remotamente no se retransmiten.
/// 3. Node.id nunca se utiliza como identidad global.
/// 4. bleAddress nunca se utiliza como identidad distribuida.
/// 5. Los dispositivos Nodos utilizan deviceUuid.
/// 6. Los BLE genéricos utilizan referencias namespaced por ownerUuid.
/// 7. Un payload con connections vacío es válido.
class NodosGraphPayload extends Equatable {
  static const int currentVersion = 1;

  final int version;
  final String ownerUuid;
  final List<NodosGraphConnection> connections;

  const NodosGraphPayload({
    this.version = currentVersion,
    required this.ownerUuid,
    this.connections = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'ownerUuid': ownerUuid,
      'connections': connections
          .map((connection) => connection.toJson())
          .toList(),
    };
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }

  List<int> toBytes() {
    return utf8.encode(toJsonString());
  }

  factory NodosGraphPayload.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final ownerUuid = json['ownerUuid'];
    final connections = json['connections'];

    if (version is! int) {
      throw const FormatException(
        'NodosGraphPayload.version debe ser un entero',
      );
    }

    if (version != currentVersion) {
      throw FormatException(
        'Versión de protocolo Nodos no soportada: $version',
      );
    }

    if (ownerUuid is! String || ownerUuid.trim().isEmpty) {
      throw const FormatException('NodosGraphPayload.ownerUuid inválido');
    }

    if (connections is! List) {
      throw const FormatException(
        'NodosGraphPayload.connections debe ser una lista',
      );
    }

    final normalizedOwnerUuid = ownerUuid.trim();
    final parsedConnections = <NodosGraphConnection>[];
    final seenRefs = <String>{};

    for (final connection in connections) {
      if (connection is! Map<String, dynamic>) {
        throw const FormatException(
          'Cada conexión del grafo Nodos debe ser un objeto JSON',
        );
      }

      final parsed = NodosGraphConnection.fromJson(connection);

      if (!seenRefs.add(parsed.ref)) {
        throw FormatException(
          'Referencia de conexión duplicada: ${parsed.ref}',
        );
      }

      if (parsed.kind == NodosGraphNodeKind.nodos &&
          parsed.deviceUuid == normalizedOwnerUuid) {
        throw const FormatException(
          'El propietario no puede relacionarse consigo mismo',
        );
      }

      if (parsed.kind == NodosGraphNodeKind.generic) {
        final expectedPrefix = 'local:$normalizedOwnerUuid:';

        if (!parsed.ref.startsWith(expectedPrefix)) {
          throw FormatException(
            'La referencia genérica ${parsed.ref} '
            'no pertenece al propietario $normalizedOwnerUuid',
          );
        }
      }

      parsedConnections.add(parsed);
    }

    return NodosGraphPayload(
      version: version,
      ownerUuid: normalizedOwnerUuid,
      connections: List.unmodifiable(parsedConnections),
    );
  }

  factory NodosGraphPayload.fromJsonString(String source) {
    final decoded = jsonDecode(source);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'El payload de grafo Nodos debe ser un objeto JSON',
      );
    }

    return NodosGraphPayload.fromJson(decoded);
  }

  factory NodosGraphPayload.fromBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('El payload de grafo Nodos está vacío');
    }

    try {
      return NodosGraphPayload.fromJsonString(utf8.decode(bytes));
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException(
        'No se pudo decodificar el payload de grafo Nodos: $error',
      );
    }
  }

  @override
  List<Object?> get props => [version, ownerUuid, connections];
}
