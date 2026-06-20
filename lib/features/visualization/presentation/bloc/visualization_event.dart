import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

/// Eventos para el VisualizationBloc.
///
/// Define las acciones que el usuario o el sistema pueden disparar
/// sobre la visualización del grafo. Cada evento representa una
/// intención: construir el grafo, seleccionar un nodo, o cerrar el
/// tooltip.
abstract class VisualizationEvent extends Equatable {
  const VisualizationEvent();

  @override
  List<Object?> get props => [];
}

/// Solicita construir y posicionar un grafo para la sesión de escaneo activa.
///
/// Se dispara cuando la lista de nodos cambia (nuevos detectados,
/// eliminados por timeout). El BLoC aplica debounce de 1s para
/// evitar reconstrucciones excesivas durante escaneos BLE rápidos.
///
/// [scanSessionId] identifica la sesión activa para BuildGraph.
/// [nodes] provee contexto de cantidad de nodos disponibles.
/// [myDeviceUuid] UUID del dispositivo propio, para marcar el self-node
/// en el grafo (R5.13). Opcional — si es null, ningún nodo se marca isSelf.
/// Agregado en PR2.
class BuildGraphRequested extends VisualizationEvent {
  final int scanSessionId;
  final List<Node> nodes;
  final String? myDeviceUuid;

  const BuildGraphRequested({
    required this.scanSessionId,
    required this.nodes,
    this.myDeviceUuid,
  });

  @override
  List<Object?> get props => [scanSessionId, nodes, myDeviceUuid];
}

/// El usuario tocó un nodo en el grafo.
///
/// Cambia el estado para mostrar el tooltip con información
/// detallada del nodo seleccionado.
class NodeSelected extends VisualizationEvent {
  final int nodeId;

  const NodeSelected(this.nodeId);

  @override
  List<Object?> get props => [nodeId];
}

/// El usuario cerró el tooltip tocando fuera del grafo o el botón de cierre.
///
/// Restaura el estado de grafo sin selección activa.
class NodeDeselected extends VisualizationEvent {
  const NodeDeselected();

  @override
  List<Object?> get props => [];
}
