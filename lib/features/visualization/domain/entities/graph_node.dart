import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

/// Nodo posicionado en el canvas del grafo.
///
/// Representa un nodo BLE detectado con su posición (x, y) en el canvas,
/// su nivel de proximidad, y atributos visuales derivados (radio, color,
/// etiqueta). Usado por GraphPainter para renderizar cada nodo.
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

  const GraphNode({
    this.id,
    required this.x,
    required this.y,
    required this.proximity,
    this.name,
  });

  /// Radio del círculo según nivel de proximidad.
  /// CLOSE=24px, MEDIUM=18px, FAR=14px.
  double get radius => switch (proximity) {
        ProximityLevel.close => 24.0,
        ProximityLevel.medium => 18.0,
        ProximityLevel.far => 14.0,
      };

  /// Color de relleno según nivel de proximidad.
  /// Verde (close), ámbar (medium), rojo (far).
  Color get color => switch (proximity) {
        ProximityLevel.close => const Color(0xFF4CAF50),
        ProximityLevel.medium => const Color(0xFFFFC107),
        ProximityLevel.far => const Color(0xFFF44336),
      };

  /// Indica si el nodo tiene identidad conocida (nombre asignado).
  ///
  /// Nodos sin nombre (name == null) son dispositivos detectados a los que
  /// el usuario aún no asignó una identidad. Se renderizan con estilo
  /// visual distinto (gris, borde discontinuo) en el grafo.
  bool get isKnown => name != null;

  /// Etiqueta a mostrar debajo del nodo.
  /// Usa el nombre si existe, sino "Desconocido".
  String get label => name ?? 'Desconocido';

  @override
  List<Object?> get props => [id, x, y, proximity, name];
}
