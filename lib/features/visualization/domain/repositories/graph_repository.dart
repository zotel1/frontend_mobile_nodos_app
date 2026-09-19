import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Contrato para obtener datos del grafo desde las fuentes de datos.
///
/// Proporciona los nodos y aristas necesarios para construir un grafo
/// de visualización a partir de una sesión de escaneo.
abstract class GraphRepository {
  /// Construye el grafo completo para una sesión de escaneo.
  ///
  /// Los dispositivos detectados se obtienen desde scan_session_nodes.
  ///
  /// ARCH-001:
  /// el dispositivo local se obtiene desde el Node persistente marcado
  /// con isSelf=true. Ya no se crea un GraphNode sintético con id=-1.
  ///
  /// El self-node puede formar parte del grafo aunque no exista dentro de
  /// scan_session_nodes, ya que representa al dispositivo local y no un
  /// dispositivo descubierto durante el escaneo.
  ///
  /// [myDeviceUuid], [userName] y [userColor] se mantienen temporalmente
  /// por compatibilidad con consumidores existentes. La identidad principal
  /// del self-node proviene ahora de la persistencia.
  Future<LayoutResult> buildGraph(
    int scanSessionId, {
    String? myDeviceUuid,
    String? userName,
    String? userColor,
  });

  /// Obtiene las aristas para una sesión específica.
  ///
  /// Cada arista representa un par de nodos detectados juntos
  /// en la misma sesión. El grosor se deriva del conteo de
  /// co-detecciones.
  Future<List<GraphEdge>> getEdges(int sessionId);
}
