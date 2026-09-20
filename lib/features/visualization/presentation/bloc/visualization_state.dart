import 'dart:ui';

import 'package:equatable/equatable.dart';

import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Estados posibles de la visualización del grafo.
///
/// La visualización sigue una máquina de estados BLoC:
///
/// inicial → construyendo → listo
///                       ↘ error
///
/// El estado es inmutable y utiliza Equatable para evitar
/// reconstrucciones innecesarias cuando sus valores no cambian.
abstract class VisualizationState extends Equatable {
  const VisualizationState();

  @override
  List<Object?> get props => [];
}

/// Estado inicial antes de construir el grafo.
class VisualizationInitial extends VisualizationState {
  const VisualizationInitial();
}

/// El grafo está siendo construido o posicionado.
///
/// Se utiliza principalmente durante la carga inicial.
/// Las actualizaciones BLE posteriores intentan conservar el grafo
/// visible para evitar parpadeos o reinicios visuales.
class GraphBuilding extends VisualizationState {
  const GraphBuilding();
}

/// El grafo está listo para ser renderizado.
///
/// Existen dos conceptos de interacción independientes:
///
/// [selectedNodeId]
///   Nodo seleccionado mediante un toque simple.
///   Se utiliza para el menú/acción actual del nodo.
///
/// [detailsNodeId]
///   Nodo cuyos detalles fueron solicitados mediante doble toque.
///   Se utilizará para mostrar nombre, identidad, distancia u otra
///   información contextual sin llenar permanentemente el grafo
///   de etiquetas.
///
/// Ambos valores son independientes. Esto permite que la selección
/// funcional de un nodo no esté acoplada a la visualización de detalles.
///
/// [barycenter]
///   Centro inicial del grafo utilizado por GraphView para realizar
///   el primer centrado del viewport.
///
/// Después del centrado inicial, GraphView conserva la transformación
/// elegida por el usuario.
class GraphReady extends VisualizationState {
  final LayoutResult layout;

  /// Nodo seleccionado mediante toque simple.
  final int? selectedNodeId;

  /// Nodo cuyos detalles están visibles.
  ///
  /// null significa que actualmente no se muestran detalles.
  final int? detailsNodeId;

  /// Centro del cluster utilizado para el centrado inicial.
  final Offset? barycenter;

  const GraphReady(
    this.layout, {
    this.selectedNodeId,
    this.detailsNodeId,
    this.barycenter,
  });

  @override
  List<Object?> get props => [
    layout,
    selectedNodeId,
    detailsNodeId,
    barycenter,
  ];
}

/// Ocurrió un error al construir el grafo o calcular su layout.
class GraphError extends VisualizationState {
  final String message;

  const GraphError(this.message);

  @override
  List<Object?> get props => [message];
}
