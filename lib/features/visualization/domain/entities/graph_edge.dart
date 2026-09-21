import 'package:equatable/equatable.dart';

/// Tipo de arista en el grafo de visualización.
///
/// [direct]:
/// conexión real registrada localmente en la tabla `connections`.
///
/// [transitive]:
/// arista inferida localmente por transitividad 1-hop.
///
/// [reported]:
/// relación declarada por otra instalación Nodos mediante Graph Exchange.
///
/// Una arista [reported] NO implica que esta instalación posea una conexión
/// directa con el nodo remoto y NO debe persistirse en `connections`.
enum EdgeType { direct, transitive, reported }

/// Arista entre dos nodos en el grafo de visualización.
///
/// [fromId] y [toId] siempre corresponden a IDs reales de la tabla `nodes`.
///
/// La procedencia de la relación se conserva mediante [edgeType]:
///
/// - [EdgeType.direct]: relación local persistida.
/// - [EdgeType.transitive]: relación inferida.
/// - [EdgeType.reported]: relación recibida mediante Graph Exchange.
class GraphEdge extends Equatable {
  /// ID del nodo origen.
  final int fromId;

  /// ID del nodo destino.
  final int toId;

  /// Grosor base de la línea en píxeles.
  final double thickness;

  /// Procedencia semántica de la arista.
  final EdgeType edgeType;

  const GraphEdge({
    required this.fromId,
    required this.toId,
    required this.thickness,
    this.edgeType = EdgeType.direct,
  });

  /// Calcula el grosor de una arista local según cantidad de
  /// co-detecciones.
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
