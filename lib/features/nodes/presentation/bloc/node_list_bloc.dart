import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/update_node_metadata.dart';

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
///
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

/// Limpia los nodos visibles de la sesión actual sin borrar persistencia.
///
/// QUÉ resuelve: cuando Bluetooth se apaga, la UI debe dejar de mostrar
/// dispositivos cercanos y el contador debe volver a 0.
///
/// IMPORTANTE:
/// Este evento NO elimina filas de la tabla nodes.
///
/// POR QUÉ:
/// Los nodos forman parte de relaciones persistentes almacenadas en
/// connections. Borrar nodes provocaría que las foreign keys con
/// ON DELETE CASCADE eliminaran también conexiones permanentes.
///
/// BUG-002:
/// ClearNodes representa una limpieza de estado de presentación,
/// no una operación destructiva sobre SQLite.
class ClearNodes extends NodeListEvent {
  const ClearNodes();
}

/// Actualiza el nombre de un nodo identificado por [nodeId].
///
/// QUÉ resuelve: persiste el nombre asignado manualmente por el usuario
/// desde el bottom sheet de metadata (R5.5).
///
/// Este evento se conserva para edición manual. La identidad obtenida
/// mediante el protocolo Nodos utiliza [UpdateNodeIdentity].
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
///
/// Este evento se conserva para edición manual. La identidad obtenida
/// mediante el protocolo Nodos utiliza [UpdateNodeIdentity].
class UpdateNodeColor extends NodeListEvent {
  final int nodeId;
  final String color;

  const UpdateNodeColor(this.nodeId, this.color);

  @override
  List<Object> get props => [nodeId, color];
}

/// Reconcilia la identidad estable de un nodo obtenida mediante
/// el protocolo Nodos.
///
/// A diferencia de [UpdateNodeName] y [UpdateNodeColor], este evento
/// representa una actualización atómica proveniente de BLE:
///
/// - [nodeId] identifica la fila detectada actualmente.
/// - [deviceUuid] identifica de forma estable al dispositivo Nodos.
/// - [name] contiene el nombre publicado por el dispositivo remoto.
/// - [color] contiene el color publicado por el dispositivo remoto.
///
/// El repositorio puede determinar que [nodeId] corresponde a una fila
/// temporal o duplicada de otro Node que ya posee [deviceUuid]. En ese
/// caso, [NodeRepository.reconcileNodeIdentity] es responsable de
/// reconciliar ambas filas preservando relaciones e historial.
class UpdateNodeIdentity extends NodeListEvent {
  final int nodeId;
  final String deviceUuid;
  final String name;
  final String color;

  const UpdateNodeIdentity({
    required this.nodeId,
    required this.deviceUuid,
    required this.name,
    required this.color,
  });

  @override
  List<Object> get props => [nodeId, deviceUuid, name, color];
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

/// BLoC que gestiona el estado de los nodos detectados.
///
/// Responsabilidades:
/// - Recibir [LoadNodes] y [RefreshNodes] para trabajar con el stream
///   reactivo de nodos.
/// - Procesar [SyncBleDevices] para convertir resultados de escaneo BLE
///   en entidades [Node] persistentes.
/// - Mantener un historial corto de RSSI entre ciclos de escaneo.
/// - Estabilizar la estimación de distancia mediante la mediana del RSSI.
/// - Procesar actualizaciones manuales de metadata.
/// - Procesar [UpdateNodeIdentity] para reconciliar la identidad estable
///   obtenida mediante el protocolo Nodos.
/// - Emitir [NodeListLoaded], [NodeListEmpty] y [NodeListError] según
///   las actualizaciones recibidas desde Drift.
///
/// Dependencias:
/// - [ObserveNodes]: expone el stream de nodos desde Drift.
/// - [UpdateNodeMetadata]: actualiza manualmente nombre/color.
/// - [NodeRepository]: persiste nodos BLE y reconcilia identidad Nodos.
class NodeListBloc extends Bloc<NodeListEvent, NodeListState> {
  static const int _maxRssiSamples = 20;

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
    on<UpdateNodeIdentity>(_onUpdateNodeIdentity);
    on<_NodesUpdated>(_onNodesUpdated);
    on<_NodesUpdatedEmpty>(_onNodesUpdatedEmpty);
    on<_NodesLoadError>(_onNodesLoadError);
  }

  Future<void> _onLoadNodes(
    LoadNodes event,
    Emitter<NodeListState> emit,
  ) async {
    _ensureSubscription();
  }

  void _onNodeDetected(NodeDetected event, Emitter<NodeListState> emit) {
    emit(NodeListLoaded([event.node]));
  }

  /// El stream Drift .watch() ya es reactivo — los cambios en la BD
  /// se emiten automáticamente sin necesidad de cancelar y recrear
  /// la suscripción.
  ///
  /// Este handler es un no-op intencional.
  Future<void> _onRefreshNodes(
    RefreshNodes event,
    Emitter<NodeListState> emit,
  ) async {}

  /// Convierte dispositivos BLE detectados en entidades [Node] y las persiste.
  ///
  /// Para cada dispositivo:
  ///
  /// 1. recupera el Node persistido por bleAddress;
  /// 2. conserva su historial RSSI anterior;
  /// 3. agrega las nuevas muestras del batch;
  /// 4. conserva solamente las últimas [_maxRssiSamples];
  /// 5. obtiene un RSSI representativo mediante la mediana;
  /// 6. calcula la distancia estimada a partir de esa señal estabilizada;
  /// 7. persiste el Node actualizado.
  ///
  /// La mediana reduce especialmente bien el efecto de muestras BLE
  /// aberrantes aisladas.
  Future<void> _onSyncBleDevices(
    SyncBleDevices event,
    Emitter<NodeListState> emit,
  ) async {
    if (event.devices.isEmpty) return;

    // Agrupar primero las lecturas válidas por deviceId.
    //
    // Esto permite consultar Drift una sola vez por dispositivo dentro
    // de este evento y combinar todas las muestras recibidas en el batch.
    final devicesById = <String, List<BleDevice>>{};

    for (final device in event.devices) {
      if (device.rssi >= 0) continue;

      devicesById.putIfAbsent(device.deviceId, () => []).add(device);
    }

    if (devicesById.isEmpty) return;

    for (final entry in devicesById.entries) {
      final deviceId = entry.key;
      final samples = entry.value;

      if (samples.isEmpty) continue;

      final latestDevice = samples.last;

      // Recuperamos el Node persistido para no perder el historial RSSI
      // acumulado durante ciclos anteriores de escaneo.
      final persisted = await _nodeRepository.getNodeByBleAddress(deviceId);

      final combinedHistory = <int>[
        ...?persisted?.rssiHistory,
        ...samples.map((device) => device.rssi),
      ];

      // Conservamos solamente una ventana reciente.
      final rssiHistory = combinedHistory.length <= _maxRssiSamples
          ? List<int>.from(combinedHistory)
          : combinedHistory.sublist(combinedHistory.length - _maxRssiSamples);

      final filteredRssi = _medianRssi(rssiHistory);

      final estimatedDistance = filteredRssi != null
          ? rssiToDistance(filteredRssi)
          : null;

      final now = DateTime.now();

      Node node;

      if (persisted != null) {
        // Nodo ya conocido:
        // preservamos identidad y metadata persistentes, actualizando
        // únicamente la información proveniente del escaneo actual.
        node = persisted.copyWith(
          bleAddress: deviceId,
          lastSeen: now,
          rssiHistory: rssiHistory,
          deviceType: latestDevice.deviceType,
          connectable: latestDevice.connectable,
          estimatedDistance: estimatedDistance,
        );
      } else {
        // Primera aparición del dispositivo.
        //
        // deviceUuid permanece null hasta que el protocolo de identidad
        // Nodos pueda obtenerlo mediante GATT.
        node = Node(
          bleAddress: deviceId,
          name: null,
          color: null,
          firstSeen: now,
          lastSeen: now,
          rssiHistory: rssiHistory,
          suggestedName:
              latestDevice.advName != null && latestDevice.advName!.isNotEmpty
              ? latestDevice.advName
              : null,
          deviceType: latestDevice.deviceType,
          connectable: latestDevice.connectable,
          estimatedDistance: estimatedDistance,
        );
      }

      await _nodeRepository.upsertNode(node);
    }

    // Drift notificará las modificaciones mediante su stream reactivo.
    _ensureSubscription();
  }

  /// Obtiene un RSSI representativo a partir de un historial de muestras.
  ///
  /// Se utiliza la mediana porque es mucho menos sensible que la media
  /// aritmética a lecturas BLE aberrantes aisladas.
  ///
  /// Ejemplo:
  ///
  /// [-52, -51, -53, -82, -52]
  ///
  /// La media se desplaza por -82.
  /// La mediana permanece en -52.
  ///
  /// Para una cantidad par de muestras se utiliza el promedio de las
  /// dos muestras centrales, redondeado al entero más cercano.
  int? _medianRssi(List<int> samples) {
    if (samples.isEmpty) return null;

    final sorted = List<int>.from(samples)..sort();
    final middle = sorted.length ~/ 2;

    if (sorted.length.isOdd) {
      return sorted[middle];
    }

    final lower = sorted[middle - 1];
    final upper = sorted[middle];

    return ((lower + upper) / 2).round();
  }

  /// Limpia el estado visible de nodos sin destruir datos persistentes.
  ///
  /// QUÉ hace:
  /// 1. cancela el watcher Drift activo;
  /// 2. elimina la referencia a la suscripción;
  /// 3. emite [NodeListEmpty].
  ///
  /// NO llama clearAllNodes() porque los nodos pueden participar en
  /// relaciones persistentes almacenadas en connections.
  Future<void> _onClearNodes(
    ClearNodes event,
    Emitter<NodeListState> emit,
  ) async {
    await _nodesSubscription?.cancel();
    _nodesSubscription = null;

    emit(const NodeListEmpty());
  }

  /// Actualiza manualmente el nombre de un nodo.
  ///
  /// Drift notificará automáticamente el cambio mediante watchNodes().
  Future<void> _onUpdateNodeName(
    UpdateNodeName event,
    Emitter<NodeListState> emit,
  ) async {
    await updateNodeMetadata(
      UpdateNodeMetadataParams(id: event.nodeId, name: event.name),
    );
  }

  /// Actualiza manualmente el color de un nodo.
  ///
  /// Drift notificará automáticamente el cambio mediante watchNodes().
  Future<void> _onUpdateNodeColor(
    UpdateNodeColor event,
    Emitter<NodeListState> emit,
  ) async {
    await updateNodeMetadata(
      UpdateNodeMetadataParams(id: event.nodeId, color: event.color),
    );
  }

  /// Reconcilia atómicamente la identidad estable de un nodo remoto.
  ///
  /// Este flujo se utiliza cuando la característica GATT de identidad
  /// devuelve uuid, nombre y color del dispositivo Nodos.
  ///
  /// Los tres valores se envían al repositorio en una única operación.
  /// Esto es importante porque el repositorio puede descubrir que el nodo
  /// identificado temporalmente por [UpdateNodeIdentity.nodeId] es un
  /// duplicado de otro nodo que ya posee el mismo deviceUuid.
  ///
  /// En ese caso, [NodeRepository.reconcileNodeIdentity] puede fusionar
  /// ambas filas preservando conexiones e historial de sesiones.
  ///
  /// No se emite manualmente un nuevo estado: Drift notificará los cambios
  /// mediante el stream observado por [_ensureSubscription].
  Future<void> _onUpdateNodeIdentity(
    UpdateNodeIdentity event,
    Emitter<NodeListState> emit,
  ) async {
    await _nodeRepository.reconcileNodeIdentity(
      event.nodeId,
      deviceUuid: event.deviceUuid,
      name: event.name,
      color: event.color,
    );
  }

  /// Crea la suscripción al stream Drift exactamente UNA vez.
  ///
  /// Drift .watch() emite reactivamente ante cualquier modificación de
  /// nodes. Si la suscripción ya existe, este método es un no-op.
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
    _NodesUpdatedEmpty event,
    Emitter<NodeListState> emit,
  ) {
    emit(const NodeListEmpty());
  }

  void _onNodesLoadError(_NodesLoadError event, Emitter<NodeListState> emit) {
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
