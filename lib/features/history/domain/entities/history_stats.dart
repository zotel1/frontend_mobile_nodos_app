import 'package:equatable/equatable.dart';

/// Estadísticas agregadas de todas las sesiones de escaneo.
///
/// QUÉ: resultado de queries de agregación SQL sobre scan_sessions
/// y scan_session_nodes. Contiene totales, promedios y el nodo
/// más frecuente detectado.
///
/// POR QUÉ: la UI de Stats muestra estas métricas en tarjetas.
/// Separar los cálculos de agregación en esta entidad mantiene
/// la lógica de negocio fuera de los widgets.
class HistoryStats extends Equatable {
  /// Total de sesiones registradas.
  final int totalSessions;

  /// Cantidad de nodos únicos detectados en todas las sesiones.
  final int uniqueNodes;

  /// Duración promedio de sesiones completadas.
  final Duration averageDuration;

  /// Nombre del nodo detectado en más sesiones, o null si no hay datos.
  final String? mostFrequentNodeName;

  const HistoryStats({
    required this.totalSessions,
    required this.uniqueNodes,
    required this.averageDuration,
    this.mostFrequentNodeName,
  });

  @override
  List<Object?> get props =>
      [totalSessions, uniqueNodes, averageDuration, mostFrequentNodeName];
}
