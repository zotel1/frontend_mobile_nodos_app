/// Contrato del repositorio de sesiones de escaneo.
///
/// QUÉ: define las operaciones disponibles sobre sesiones de escaneo:
/// iniciar, finalizar, agregar nodos y consultar la sesión activa.
///
/// POR QUÉ: la interfaz es el contrato del dominio. La implementación
/// concreta (Drift) vive en la capa data/. Esto permite testear el
/// BLoC con un mock del repositorio sin dependencia real de la BD.
abstract class ScanSessionRepository {
  /// Crea una nueva sesión de escaneo con `startedAt = now()`.
  /// Retorna el ID de la sesión creada.
  Future<int> startSession();

  /// Cierra una sesión activa estableciendo `endedAt = now()`.
  Future<void> endSession(int sessionId);

  /// Registra nodos detectados en una sesión activa.
  /// Usa insertOrIgnore para evitar duplicados (mismo nodo en la misma sesión).
  /// Actualiza el contador `nodesDetected` en la tabla scan_sessions.
  Future<void> addNodesToSession(int sessionId, List<int> nodeIds);

  /// Retorna el ID de la sesión activa (con `endedAt = null`), o null si no hay.
  Future<int?> getActiveSession();
}
