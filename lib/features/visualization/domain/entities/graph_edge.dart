import 'package:equatable/equatable.dart';

/// Tipo de arista en el grafo de visualización.
///
/// [direct]: conexión real registrada en la tabla connections
///   (A↔B mutuamente conectados). Se renderiza sólida, opacidad completa.
///
/// [transitive]: arista inferida por transitividad 1-hop
///   (A→B y B→C ⇒ A—C). Se renderiza con patrón discontinuo (dashed)
///   y opacidad 50% (R5.3).
/// Agregado en PR2 — Phase 5 Graph Social Model.
enum EdgeType { direct, transitive }

/// Arista entre dos nodos en el grafo de visualización.
///
/// Conecta dos GraphNode por sus IDs. El grosor (thickness) depende de
/// la cantidad de co-detecciones entre los nodos conectados, siguiendo
/// la especificación GRAPH-VIZ AC-5.
class GraphEdge extends Equatable {
  /// ID del nodo origen.
  final int fromId;

  /// ID del nodo destino.
  final int toId;

  /// Grosor de la línea en píxeles.
  /// Derivado de la cantidad de co-detecciones.
  final double thickness;

  /// Tipo de arista: [EdgeType.direct] (conexión real) o
  /// [EdgeType.transitive] (inferida por transitividad 1-hop).
  /// Default: direct. Agregado en PR2.
  final EdgeType edgeType;

  const GraphEdge({
    required this.fromId,
    required this.toId,
    required this.thickness,
    this.edgeType = EdgeType.direct,
  });

  /// Calcula el grosor de arista según cantidad de co-detecciones.
  ///
  /// 1 detección → 1.0 px
  /// 2-3 detecciones → 2.0 px
  /// ≥4 detecciones → 3.0 px
  static double thicknessFromCount(int count) {
    if (count >= 4) return 3.0;
    if (count >= 2) return 2.0;
    return 1.0;
  }

  @override
  List<Object?> get props => [fromId, toId, thickness, edgeType];
}
