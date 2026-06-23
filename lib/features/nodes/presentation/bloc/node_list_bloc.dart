import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/update_node_metadata.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

// ── Events ──

abstract class NodeListEvent extends Equatable {
  const NodeListEvent();

  @override
  List<Object?> get props => [];
}

class LoadNodes extends NodeListEvent {
  const LoadNodes();
}

class NodeDetected extends NodeListEvent {
  final Node node;

  const NodeDetected(this.node);

  @override
  List<Object> get props => [node];
}

class RefreshNodes extends NodeListEvent {
  const RefreshNodes();
}

/// Evento público que actúa como puente entre el escaneo BLE y la
/// persistencia de nodos.
///
/// QUÉ resuelve: convierte cada [BleDevice] detectado por [BleBloc]
/// en una entidad [Node] y la persiste mediante [NodeRepository.upsertNode].
/// POR QUÉ: sin este evento, los resultados del escaneo BLE nunca se
/// convierten en nodos visibles en la UI — el flujo de datos se rompe
/// entre el datasource BLE y el repositorio de nodos.
///
/// Se despacha desde [HomePage] vía [BlocListener<BleBloc>] cuando
/// [BleBloc] emite [BleScanning] con dispositivos detectados.
class SyncBleDevices extends NodeListEvent {
  final List<BleDevice> devices;

  const SyncBleDevices(this.devices);

  @override
  List<Object> get props => [devices];
}

/// Elimina todos los nodos de la base de datos y re-suscribe el stream.
///
/// QUÉ resuelve: pipeline para limpiar el contador de nodos a 0
/// cuando se apaga Bluetooth (R5.17). La re-suscripción al stream
/// Drift emite una lista vacía → NodeListEmpty.
/// POR QUÉ: sin este evento, los nodos persisten en BD aunque BT
/// esté apagado, mostrando datos stale en la UI.
class ClearNodes extends NodeListEvent {
  const ClearNodes();
}

/// Actualiza el nombre de un nodo identificado por [nodeId].
///
/// QUÉ resuelve: persiste el nombre asignado manualmente por el usuario
/// desde el bottom sheet de metadata (R5.5).
class UpdateNodeName extends NodeListEvent {
  final int nodeId;
  final String name;

  const UpdateNodeName(this.nodeId, this.name);

  @override
  List<Object> get props => [nodeId, name];
}

/// Actualiza el color de un nodo identificado por [nodeId].
///
/// QUÉ resuelve: persiste el color asignado manualmente por el usuario
/// desde el color picker del bottom sheet de metadata (R5.6).
class UpdateNodeColor extends NodeListEvent {
  final int nodeId;
  final String color;

  const UpdateNodeColor(this.nodeId, this.color);

  @override
  List<Object> get props => [nodeId, color];
}

// ── States ──

abstract class NodeListState extends Equatable {
  const NodeListState();

  @override
  List<Object?> get props => [];
}

class NodeListInitial extends NodeListState {
  const NodeListInitial();
}

class NodeListLoading extends NodeListState {
  const NodeListLoading();
}

class NodeListLoaded extends NodeListState {
  final List<Node> nodes;

  const NodeListLoaded(this.nodes);

  @override
  List<Object> get props => [nodes];
}

class NodeListEmpty extends NodeListState {
  const NodeListEmpty();
}

class NodeListError extends NodeListState {
  final String message;

  const NodeListError(this.message);

  @override
  List<Object> get props => [message];
}

// ── BLoC ──

/// BLoC que gestiona el estado de la lista de nodos detectados.
///
/// Responsabilidades:
/// - Recibir eventos [LoadNodes] y [RefreshNodes] para suscribirse
///   al stream [watchNodes] del repositorio.
/// - Procesar [SyncBleDevices] para convertir resultados de escaneo BLE
///   en entidades [Node] persistentes (puente BLE→Node).
/// - Emitir estados [NodeListLoaded], [NodeListEmpty], [NodeListError]
///   según el resultado del stream o del handler de sincronización.
///
/// Dependencias:
/// - [ObserveNodes]: use case que expone el stream de nodos desde Drift.
/// - [UpdateNodeMetadata]: use case para actualizar nombre/color de un nodo.
/// - [NodeRepository]: repositorio para persistir nodos (usado por SyncBleDevices).
class NodeListBloc extends Bloc<NodeListEvent, NodeListState> {
  final ObserveNodes observeNodes;
  final UpdateNodeMetadata updateNodeMetadata;
  final NodeRepository _nodeRepository;
  StreamSubscription<List<Node>>? _nodesSubscription;

  NodeListBloc({
    required this.observeNodes,
    required this.updateNodeMetadata,
    required NodeRepository nodeRepository,
  }) : _nodeRepository = nodeRepository,
       super(const NodeListInitial()) {
    on<LoadNodes>(_onLoadNodes);
    on<NodeDetected>(_onNodeDetected);
    on<RefreshNodes>(_onRefreshNodes);
    on<SyncBleDevices>(_onSyncBleDevices);
    on<ClearNodes>(_onClearNodes);
    on<UpdateNodeName>(_onUpdateNodeName);
    on<UpdateNodeColor>(_onUpdateNodeColor);
    on<_NodesUpdated>(_onNodesUpdated);
    on<_NodesUpdatedEmpty>(_onNodesUpdatedEmpty);
    on<_NodesLoadError>(_onNodesLoadError);
  }

  Future<void> _onLoadNodes(
      LoadNodes event, Emitter<NodeListState> emit) async {
    _ensureSubscription();
  }

  void _onNodeDetected(
      NodeDetected event, Emitter<NodeListState> emit) {
    emit(NodeListLoaded([event.node]));
  }

  /// El stream Drift .watch() ya es reactivo — los cambios en la BD
  /// se emiten automáticamente sin necesidad de cancelar y recrear
  /// la suscripción. Este handler es un no-op intencional.
  Future<void> _onRefreshNodes(
      RefreshNodes event, Emitter<NodeListState> emit) async {}

  /// Convierte dispositivos BLE detectados en entidades [Node] y las persiste.
  ///
  /// QUÉ hace: itera cada [BleDevice], lo convierte a [Node] aplicando
  /// reglas de mapeo (deviceId→bleAddress, rssi→rssiHistory), y llama
  /// [NodeRepository.upsertNode] para persistir.
  ///
  /// POR QUÉ esta implementación:
  /// - Dedup por bleAddress: Drift maneja inserción/reemplazo por clave única.
  /// - rssiHistory limitado a 20: evita crecimiento ilimitado de la lista.
  /// - RSSI >= 0 ignorado: señal inválida según especificación BLE.
  /// - firstSeen preservado: nodos existentes mantienen su timestamp original.
  ///
  /// QUÉ problema resuelve: cierra la brecha entre el escaneo BLE (BleBloc)
  /// y la UI de nodos (NodeListBloc). Sin este handler, los dispositivos
  /// detectados nunca se convierten en nodos visibles.
  Future<void> _onSyncBleDevices(
    SyncBleDevices event,
    Emitter<NodeListState> emit,
  ) async {
    if (event.devices.isEmpty) return;

    // Mapa local de nodos procesados en este batch para soportar
    // dedup dentro del mismo lote (mismo deviceId aparece varias veces).
    final processed = <String, Node>{};

    for (final device in event.devices) {
      // Ignorar dispositivos con señal inválida (RSSI >= 0).
      if (device.rssi >= 0) continue;

      final existing = processed[device.deviceId];

      if (existing != null) {
        // Mismo deviceId ya procesado en este batch: append RSSI.
        // Preservar suggestedName del primer avistamiento (freeze).
        final updatedHistory = [...existing.rssiHistory, device.rssi];
        if (updatedHistory.length > 20) {
          updatedHistory.removeAt(0);
        }
          processed[device.deviceId] = Node(
            id: existing.id,
            bleAddress: existing.bleAddress,
            name: existing.name,
            color: existing.color,
            firstSeen: existing.firstSeen,
            lastSeen: DateTime.now(),
            rssiHistory: updatedHistory,
            suggestedName: existing.suggestedName,
            deviceType: device.deviceType ?? existing.deviceType,
            connectable: device.connectable,
            estimatedDistance: device.rssi < 0
                ? rssiToDistance(device.rssi, txPowerLevel: device.txPowerLevel)
                : null,
          );
      } else {
        // Nuevo nodo (o primera aparición en este batch).
        // T1.6: mapear advName → suggestedName y deviceType.
        // El freeze on first detection se maneja en el datasource Drift.
        processed[device.deviceId] = Node(
          bleAddress: device.deviceId,
          name: null,
          color: null,
          firstSeen: DateTime.now(),
          lastSeen: DateTime.now(),
          rssiHistory: [device.rssi],
              suggestedName: device.advName != null && device.advName!.isNotEmpty
                  ? device.advName
                  : null,
              deviceType: device.deviceType,
              connectable: device.connectable,
              estimatedDistance: device.rssi < 0
                  ? rssiToDistance(device.rssi, txPowerLevel: device.txPowerLevel)
                  : null,
            );
      }
    }

    // Persistir todos los nodos procesados.
    for (final node in processed.values) {
      await _nodeRepository.upsertNode(node);
    }

    // Asegurar que la suscripción al stream Drift existe.
    // Si ya existe, no se cancela ni recrea — .watch() emite
    // reactivamente los cambios sin intervención.
    _ensureSubscription();
  }

  /// Elimina todos los nodos y re-suscribe el stream para emitir vacío.
  ///
  /// QUÉ hace: llama a [NodeRepository.clearAllNodes()] para borrar
  /// todas las filas de la tabla nodes, luego re-suscribe al stream
  /// Drift que emitirá lista vacía → NodeListEmpty.
  /// POR QUÉ: pipeline R5.17 — cuando BT se apaga, los nodos deben
  /// desaparecer de la UI y el contador debe llegar a 0.
  Future<void> _onClearNodes(
      ClearNodes event, Emitter<NodeListState> emit) async {
    await _nodeRepository.clearAllNodes();
    // El stream Drift .watch() emitirá automáticamente la lista vacía
    // sin necesidad de cancelar y recrear la suscripción.
  }

  /// Actualiza el nombre de un nodo y re-emite la lista desde el stream.
  ///
  /// QUÉ hace: delega al use case [UpdateNodeMetadata] pasando solo
  /// el nombre, luego re-suscribe al stream Drift para emitir la
  /// lista actualizada con el nuevo nombre.
  Future<void> _onUpdateNodeName(
      UpdateNodeName event, Emitter<NodeListState> emit) async {
    await updateNodeMetadata(
      UpdateNodeMetadataParams(id: event.nodeId, name: event.name),
    );
    // El stream Drift .watch() emitirá automáticamente la lista actualizada.
  }

  /// Actualiza el color de un nodo y re-emite la lista desde el stream.
  ///
  /// QUÉ hace: delega al use case [UpdateNodeMetadata] pasando solo
  /// el color, luego re-suscribe al stream Drift para emitir la
  /// lista actualizada con el nuevo color.
  Future<void> _onUpdateNodeColor(
      UpdateNodeColor event, Emitter<NodeListState> emit) async {
    await updateNodeMetadata(
      UpdateNodeMetadataParams(id: event.nodeId, color: event.color),
    );
    // El stream Drift .watch() emitirá automáticamente la lista actualizada.
  }

  /// Crea la suscripción al stream Drift exactamente UNA vez.
  ///
  /// La suscripción no se cancela ni recrea porque Drift .watch()
  /// emite reactivamente ante cualquier cambio en la tabla nodes.
  /// Si la suscripción ya existe, este método es un no-op.
  void _ensureSubscription() {
    if (_nodesSubscription != null) return;
    _nodesSubscription = observeNodes().listen(
      (nodes) {
        if (!isClosed) {
          if (nodes.isEmpty) {
            add(const _NodesUpdatedEmpty());
          } else {
            add(_NodesUpdated(nodes));
          }
        }
      },
      onError: (Object error) {
        if (!isClosed) {
          add(_NodesLoadError(error.toString()));
        }
      },
    );
  }

  void _onNodesUpdated(_NodesUpdated event, Emitter<NodeListState> emit) {
    emit(NodeListLoaded(event.nodes));
  }

  void _onNodesUpdatedEmpty(
      _NodesUpdatedEmpty event, Emitter<NodeListState> emit) {
    emit(const NodeListEmpty());
  }

  void _onNodesLoadError(
      _NodesLoadError event, Emitter<NodeListState> emit) {
    emit(NodeListError(event.message));
  }

  @override
  Future<void> close() {
    _nodesSubscription?.cancel();
    return super.close();
  }
}

// ── Internal Events ──

class _NodesUpdated extends NodeListEvent {
  final List<Node> nodes;

  const _NodesUpdated(this.nodes);

  @override
  List<Object> get props => [nodes];
}

class _NodesUpdatedEmpty extends NodeListEvent {
  const _NodesUpdatedEmpty();
}

class _NodesLoadError extends NodeListEvent {
  final String message;

  const _NodesLoadError(this.message);

  @override
  List<Object> get props => [message];
}
