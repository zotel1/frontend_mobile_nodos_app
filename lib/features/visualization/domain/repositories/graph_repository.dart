import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Contrato para obtener datos del grafo desde las fuentes de datos.
///
/// Proporciona los nodos y aristas necesarios para construir un grafo
/// de visualización a partir de una sesión de escaneo.
abstract class GraphRepository {
  /// Construye el grafo completo para una sesión de escaneo.
  ///
  /// Retorna un [LayoutResult] con nodos posicionados inicialmente
  /// (posiciones iniciales circulares) y aristas derivadas de las
  /// co-detecciones dentro de la sesión.
  ///
  /// [myDeviceUuid] permite identificar el nodo que representa al
  /// dispositivo del usuario. Si la dirección BLE de algún nodo coincide
  /// con este UUID, se marca con `isSelf = true` para renderizado especial.
  ///
  /// [userName] y [userColor] se usan para inyectar un self-node sintético
  /// (REQ-SN-01) con la identidad del perfil del usuario, incluso cuando
  /// no hay nodos externos detectados.
  Future<LayoutResult> buildGraph(int scanSessionId,
      {String? myDeviceUuid, String? userName, String? userColor});

  /// Obtiene las aristas para una sesión específica.
  ///
  /// Cada arista representa un par de nodos detectados juntos
  /// en la misma sesión. El grosor se deriva del conteo de
  /// co-detecciones.
  Future<List<GraphEdge>> getEdges(int sessionId);
}
