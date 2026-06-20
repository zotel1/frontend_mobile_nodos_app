import 'package:equatable/equatable.dart';

/// Entidad que representa una sesión de escaneo BLE en el dominio.
///
/// QUÉ: contiene los datos esenciales de una sesión: identificador,
/// timestamps de inicio/fin y cantidad de nodos detectados.
///
/// POR QUÉ: desacopla la capa de presentación del schema Drift,
/// permitiendo que el BLoC y la UI operen con una abstracción
/// pura del dominio sin depender de las tablas de la base de datos.
class ScanSessionEntity extends Equatable {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int nodeCount;

  const ScanSessionEntity({
    required this.id,
    required this.startedAt,
    this.endedAt,
    required this.nodeCount,
  });

  @override
  List<Object?> get props => [id, startedAt, endedAt, nodeCount];
}
