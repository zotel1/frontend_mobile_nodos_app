import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

/// Nodo posicionado en el canvas del grafo.
///
/// Representa un nodo BLE detectado con su posición (x, y) en el canvas,
/// su nivel de proximidad, y atributos visuales derivados (radio, color,
/// etiqueta). Usado por GraphPainter para renderizar cada nodo.
///
/// Radio basado en [connectionCount] (LinkedIn Maps style):
/// `(12 + degree*3).clamp(12, 50)`. Nodos con más aristas son más grandes.
class GraphNode extends Equatable {
  /// ID del nodo en la tabla nodes de Drift.
  final int? id;

  /// Posición X en el canvas (píxeles).
  final double x;

  /// Posición Y en el canvas (píxeles).
  final double y;

  /// Nivel de proximidad derivado del RSSI.
  final ProximityLevel proximity;

  /// Nombre asignado por el usuario, si existe.
  final String? name;

  /// Nombre sugerido desde el advertisement BLE (Phase 4 enrichment).
  /// Se usa como fallback cuando el usuario no asignó nombre.
  final String? suggestedName;

  /// Cantidad de aristas (conexiones) de este nodo en el grafo.
  /// Determina el tamaño visual del nodo (radio).
  final int connectionCount;

  /// Indica si este nodo representa el dispositivo del usuario ("yo").
  /// Se renderiza con un anillo azul de glow (T2.5).
  final bool isSelf;

  /// Indica si el dispositivo acepta conexiones GATT (Enlazar).
  ///
  /// false → el botón "Enlazar" se deshabilita con estilo gris.
  /// Valor por defecto true — se actualizará cuando el pipeline
  /// de datos propague connectable desde BleDevice.
  final bool connectable;

  /// Coordenada Z para el grafo 3D (profundidad).
  ///
  /// Default 0.0 preserva compatibilidad con el grafo 2D existente.
  /// El algoritmo Fruchterman-Reingold 3D (T5.2) calcula este valor
  /// solo cuando el canvas incluye profundidad. Para 2D, z=0.
  /// Agregado en PR5 — FR Algorithm 3D + 2D/3D Toggle.
  final double z;

  /// Color asignado por el usuario, en formato ARGB int (ej. 0xFF2196F3).
  ///
  /// Si no es null, sobrescribe el color de proximidad en la renderización
  /// del grafo (R5.6). El getter [displayColor] resuelve la prioridad:
  /// userColor > color de proximidad.
  /// Agregado en PR2 — Phase 5 Graph Social Model.
  final int? userColor;

  /// Distancia estimada en metros desde el dispositivo del usuario.
  ///
  /// Computada vía [rssiToDistance] en el pipeline de sincronización BLE.
  /// Se muestra como label adaptativo: ≥1m → "~2.3m", <1m → "~35cm" (R5.15).
  /// null cuando no hay dato de RSSI disponible.
  /// Agregado en PR2 — Phase 5 Graph Social Model.
  final double? estimatedDistance;

  const GraphNode({
    this.id,
    required this.x,
    required this.y,
    required this.proximity,
    this.name,
    this.suggestedName,
    this.connectionCount = 0,
    this.isSelf = false,
    this.connectable = true,
    this.z = 0.0,
    this.userColor,
    this.estimatedDistance,
  });

  /// Radio del círculo proporcional a la cantidad de conexiones.
  ///
  /// Fórmula LinkedIn Maps: `(12 + degree*3).clamp(12, 50)`.
  /// Aislados (0 conexiones) = 12px, muy conectados = hasta 50px.
  double get radius =>
      (12.0 + connectionCount * 3.0).clamp(12.0, 50.0);

  /// Color de relleno según nivel de proximidad.
  /// Verde (close), ámbar (medium), rojo (far).
  Color get color => switch (proximity) {
        ProximityLevel.close => const Color(0xFF4CAF50),
        ProximityLevel.medium => const Color(0xFFFFC107),
        ProximityLevel.far => const Color(0xFFF44336),
      };

  /// Color efectivo para renderizar el nodo.
  ///
  /// Prioridad: si el usuario asignó [userColor], se usa ese color.
  /// Caso contrario, se usa el color derivado de proximidad [color].
  /// R5.6 — user-assigned colors must override proximity color.
  Color get displayColor =>
      userColor != null ? Color(userColor!) : color;

  /// Indica si el nodo tiene identidad conocida (nombre asignado).
  ///
  /// Nodos sin nombre (name == null) son dispositivos detectados a los que
  /// el usuario aún no asignó una identidad. Se renderizan con estilo
  /// visual distinto (gris, borde discontinuo) en el grafo.
  bool get isKnown => name != null;

  /// Etiqueta a mostrar debajo del nodo.
  /// Prioridad: name > suggestedName > "Desconocido" (T1.8).
  String get label => name ?? suggestedName ?? 'Desconocido';

  @override
  List<Object?> get props =>
      [id, x, y, proximity, name, suggestedName, connectionCount, isSelf, connectable, z, userColor, estimatedDistance];
}
