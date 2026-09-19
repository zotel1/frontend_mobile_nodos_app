import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

/// Eventos para el VisualizationBloc.
///
/// Define las acciones que el usuario o el sistema pueden disparar
/// sobre la visualización del grafo.
///
/// Incluye:
///
/// - construcción/actualización del grafo;
/// - selección de nodos;
/// - movimiento interactivo de nodos;
/// - reintento después de errores.
abstract class VisualizationEvent extends Equatable {
  const VisualizationEvent();

  @override
  List<Object?> get props => [];
}

/// Solicita construir o actualizar el grafo para la sesión activa.
///
/// Las actualizaciones BLE no implican necesariamente recalcular
/// posiciones. VisualizationBloc determina posteriormente si cambió
/// realmente la topología del grafo.
class BuildGraphRequested extends VisualizationEvent {
  final int scanSessionId;
  final List<Node> nodes;
  final String? myDeviceUuid;
  final String? userName;
  final String? userColor;

  const BuildGraphRequested({
    required this.scanSessionId,
    required this.nodes,
    this.myDeviceUuid,
    this.userName,
    this.userColor,
  });

  @override
  List<Object?> get props => [
    scanSessionId,
    nodes,
    myDeviceUuid,
    userName,
    userColor,
  ];
}

/// El usuario realizó un toque simple sobre un nodo.
///
/// Mantiene la semántica existente:
/// seleccionar el nodo para mostrar su menú/acciones.
class NodeSelected extends VisualizationEvent {
  final int nodeId;

  const NodeSelected(this.nodeId);

  @override
  List<Object?> get props => [nodeId];
}

/// El usuario cerró la selección activa.
class NodeDeselected extends VisualizationEvent {
  const NodeDeselected();
}

/// Comienza el movimiento manual de un nodo.
///
/// Se dispara después de mantener presionado un nodo.
///
/// [nodeId] identifica el nodo que queda temporalmente "agarrado".
class NodeDragStarted extends VisualizationEvent {
  final int nodeId;

  const NodeDragStarted(this.nodeId);

  @override
  List<Object?> get props => [nodeId];
}

/// Actualiza la posición del nodo que está siendo arrastrado.
///
/// Las coordenadas pertenecen al espacio lógico del canvas 2000×2000,
/// no al espacio físico de la pantalla.
///
/// Esto permite que el movimiento funcione correctamente aunque exista
/// zoom o desplazamiento del InteractiveViewer.
class NodeDragUpdated extends VisualizationEvent {
  final int nodeId;
  final double x;
  final double y;

  const NodeDragUpdated({
    required this.nodeId,
    required this.x,
    required this.y,
  });

  @override
  List<Object?> get props => [nodeId, x, y];
}

/// Finaliza el movimiento manual de un nodo.
///
/// En esta primera etapa simplemente libera el nodo.
///
/// Posteriormente este evento será el punto de entrada para iniciar
/// la relajación física del sistema.
class NodeDragEnded extends VisualizationEvent {
  final int nodeId;

  const NodeDragEnded(this.nodeId);

  @override
  List<Object?> get props => [nodeId];
}

/// Reintenta la construcción del grafo después de un error.
class RetryGraphBuild extends VisualizationEvent {
  final int lastSessionId;
  final List<Node> lastNodes;
  final String? myDeviceUuid;
  final String? userName;
  final String? userColor;

  const RetryGraphBuild({
    required this.lastSessionId,
    required this.lastNodes,
    this.myDeviceUuid,
    this.userName,
    this.userColor,
  });

  @override
  List<Object?> get props => [
    lastSessionId,
    lastNodes,
    myDeviceUuid,
    userName,
    userColor,
  ];
}
