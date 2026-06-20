import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Estados de la visualización del grafo.
///
/// Sigue el patrón de máquina de estados BLoC para gestionar
/// el ciclo de vida completo: inicial → construyendo → listo/vista
/// del grafo → error. Cada estado es inmutable y extiende Equatable
/// para comparación eficiente.
abstract class VisualizationState extends Equatable {
  const VisualizationState();

  @override
  List<Object?> get props => [];
}

/// Estado inicial antes de cualquier acción del usuario o sistema.
class VisualizationInitial extends VisualizationState {
  const VisualizationInitial();
}

/// El grafo se está construyendo y posicionando.
///
/// La UI debe mostrar un indicador de carga mientras se ejecutan
/// BuildGraph (repositorio) y CalculateLayout (Isolate FR).
class GraphBuilding extends VisualizationState {
  const GraphBuilding();
}

/// El grafo está listo para ser renderizado por GraphPainter.
///
/// [selectedNodeId] es no-nulo cuando el usuario tocó un nodo
/// y el tooltip está visible. Nulo cuando no hay selección activa.
///
/// [barycenter] es el centro geométrico del cluster de nodos
/// (promedio de todas las posiciones x,y). Se usa en GraphView
/// para centrar la vista automáticamente en el primer GraphReady (R5.13).
/// Agregado en PR2.
class GraphReady extends VisualizationState {
  final LayoutResult layout;
  final int? selectedNodeId;

  /// Centro geométrico del cluster: promedio de posiciones (x,y).
  /// null si el layout está vacío (no debería ocurrir en este estado).
  final Offset? barycenter;

  const GraphReady(this.layout, {this.selectedNodeId, this.barycenter});

  @override
  List<Object?> get props => [layout, selectedNodeId, barycenter];
}

/// Ocurrió un error al construir el grafo o calcular su layout.
///
/// La UI muestra el mensaje de error y puede ofrecer reintentar.
class GraphError extends VisualizationState {
  final String message;

  const GraphError(this.message);

  @override
  List<Object?> get props => [message];
}
