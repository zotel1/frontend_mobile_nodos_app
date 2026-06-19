import 'package:equatable/equatable.dart';

/// Entidad que representa un nodo detectado en una sesión de escaneo,
/// incluyendo su RSSI y nivel de proximidad en esa sesión.
///
/// QUÉ: empareja un nodeId con su RSSI medido durante la sesión
/// y el nombre del nodo (si existe).
/// POR QUÉ: el detalle de sesión necesita mostrar qué nodos
/// fueron detectados y con qué intensidad de señal.
class SessionNode extends Equatable {
  /// ID del registro en scan_session_nodes.
  final int? id;

  /// ID de la sesión de escaneo.
  final int sessionId;

  /// ID del nodo detectado.
  final int nodeId;

  /// RSSI medido durante la sesión.
  final int rssi;

  /// Nombre del nodo (puede ser null si es "Desconocido").
  final String? nodeName;

  /// Nivel de proximidad derivado del RSSI: 'close', 'medium', 'far'.
  final String proximityLevel;

  const SessionNode({
    this.id,
    required this.sessionId,
    required this.nodeId,
    required this.rssi,
    this.nodeName,
    required this.proximityLevel,
  });

  @override
  List<Object?> get props =>
      [id, sessionId, nodeId, rssi, nodeName, proximityLevel];
}
