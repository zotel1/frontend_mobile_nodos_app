import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/session_node.dart';

/// Sesión de escaneo con metadatos y lista de nodos detectados.
///
/// QUÉ: representa una sesión de escaneo BLE registrada en la tabla
/// scan_sessions. Contiene fecha de inicio, fin opcional, conteo de
/// nodos y lista de nodos detectados (poblada en consultas de detalle).
///
/// POR QUÉ: separa la capa de presentación (HistoryBloc, UI) de los
/// detalles de la base de datos. La UI usa esta entidad para renderizar
/// tarjetas de sesión con fechas, duración y conteo de nodos.
class ScanSession extends Equatable {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Cantidad de nodos detectados en esta sesión.
  final int nodeCount;

  /// Lista de nodos con RSSI (poblada solo en consultas de detalle).
  final List<SessionNode> nodes;

  const ScanSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    required this.nodeCount,
    this.nodes = const [],
  });

  /// Duración de la sesión si tiene [endedAt].
  Duration? get duration =>
      endedAt?.difference(startedAt);

  @override
  List<Object?> get props => [id, startedAt, endedAt, nodeCount, nodes];
}
