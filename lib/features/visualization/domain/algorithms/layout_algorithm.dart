/// Interfaz abstracta para algoritmos de layout de grafos.
///
/// Define el contrato que cualquier algoritmo de posicionamiento
/// (Fruchterman-Reingold, Kamada-Kawai, Eades, etc.) debe cumplir.
/// 
/// La capa de dominio depende de esta interfaz, no de implementaciones
/// concretas. La capa de datos provee la implementación (ej. FR).
///
/// QUÉ problema resuelve: AD-31, AD-34 — el dominio no debe depender
/// de la capa de datos ni de Flutter. Con esta interfaz, CalculateLayout
/// (use case de dominio) no conoce qué algoritmo concreto se ejecuta,
/// solo que recibe params y retorna un Map serializable.
abstract class LayoutAlgorithm {
  /// Calcula las posiciones de los nodos del grafo.
  ///
  /// Recibe un [params] con la estructura esperada por el algoritmo:
  /// ```dart
  /// {
  ///   'nodes': [{id, x, y, z?}, ...],
  ///   'edges': [{fromId, toId}, ...],
  ///   'width': double,
  ///   'height': double,
  ///   'depth': double?,        // opcional, 3D
  ///   'iterations': int,
  ///   'k': double,
  ///   'temperature': double,
  ///   'coolingFactor': double,
  ///   'seed': int?,            // opcional, tests deterministas
  /// }
  /// ```
  ///
  /// Retorna un Map con la misma estructura pero con posiciones
  /// actualizadas (x, y, z) y metadatos (iterations, converged).
  Future<Map<String, dynamic>> calculate(Map<String, dynamic> params);
}
