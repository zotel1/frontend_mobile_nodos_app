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
  Future<LayoutResult> buildGraph(int scanSessionId);

  /// Obtiene las aristas para una sesión específica.
  ///
  /// Cada arista representa un par de nodos detectados juntos
  /// en la misma sesión. El grosor se deriva del conteo de
  /// co-detecciones.
  Future<List<GraphEdge>> getEdges(int sessionId);
}
