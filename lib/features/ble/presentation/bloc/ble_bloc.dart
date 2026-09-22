import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_link_request.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_link_response.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

class BleBloc extends Bloc<BleEvent, BleState> {
  final BleRepository repository;
  final UserRepository userRepository;
  final RemoteRelationRepository remoteRelationRepository;
  final NodeRepository nodeRepository;
  final BleConnectionRepository connectionRepository;

  StreamSubscription<List<BleDevice>>? _scanSubscription;
  StreamSubscription<bool>? _btSubscription;
  StreamSubscription<BleIncomingGattWrite>? _linkRequestSubscription;
  StreamSubscription<BleIncomingGattWrite>? _peerGraphSubscription;

  /// Solicitud de enlace Nodos actualmente pendiente de decisión local.
  ///
  /// En esta versión del protocolo solamente se permite una solicitud
  /// pendiente a la vez.
  NodosLinkRequest? _pendingLinkRequest;

  /// UUID del peer cuyo NodosGraphPayload esperamos después de haber
  /// aceptado explícitamente su LinkRequest.
  ///
  /// El datasource peripheral no informa qué central originó una escritura
  /// GATT. Por eso correlacionamos el siguiente payload mediante ownerUuid.
  ///
  /// Una vez recibido y persistido un payload válido, esta autorización
  /// transitoria se elimina.
  String? _awaitingPeerGraphUuid;

  /// Stream utilizado exclusivamente para avisar a la UI que debe mostrar
  /// una solicitud de enlace.
  ///
  /// No forma parte de [BleState] porque una solicitud de enlace es un
  /// efecto puntual y no reemplaza el estado operativo de escaneo/publicidad.
  final StreamController<NodosLinkRequest> _linkRequestController =
      StreamController<NodosLinkRequest>.broadcast();

  /// Solicitudes de enlace válidas que requieren decisión del usuario.
  Stream<NodosLinkRequest> get linkRequests => _linkRequestController.stream;

  /// Solicitud pendiente actual.
  ///
  /// Expuesto principalmente para inspección y testing.
  @visibleForTesting
  NodosLinkRequest? get pendingLinkRequest => _pendingLinkRequest;

  /// UUID del peer cuyo grafo esperamos actualmente.
  @visibleForTesting
  String? get awaitingPeerGraphUuid => _awaitingPeerGraphUuid;

  /// Período entre reinicios del escaneo para duty cycling.
  ///
  /// Valor por defecto: [dutyCycleScanDuration] + [dutyCyclePauseDuration]
  /// de app_config. En tests se puede inyectar un período más corto.
  final Duration _dutyCyclePeriod;

  /// Acumulador de dispositivos detectados durante el escaneo.
  ///
  /// Clave: [BleDevice.deviceId] (dirección MAC o remoteId).
  /// Valor: [BleDevice] más reciente visto para ese ID.
  ///
  /// QUÉ resuelve: antes cada batch de scanResults reemplazaba el estado
  /// completo, perdiendo dispositivos de batches anteriores (bug B1).
  /// Ahora se acumulan — un dispositivo aparece si fue visto en
  /// CUALQUIER ciclo de escaneo en los últimos 30s.
  final Map<String, BleDevice> _accumulatedDevices = {};

  /// Timer periódico para evicción de dispositivos stale.
  ///
  /// Cada 30 segundos dispara [EvictStaleDevices] que limpia del
  /// [_accumulatedDevices] cualquier dispositivo con timestamp mayor
  /// a 30s de antigüedad.
  Timer? _evictionTimer;

  /// Timer para duty cycling de escaneo BLE.
  Timer? _dutyCycleTimer;

  /// Duración máxima desde el último avistamiento antes de evicción.
  static const _staleThreshold = Duration(seconds: 30);

  /// Cantidad máxima de dispositivos acumulados en el mapa.
  static const _maxDevices = 50;

  /// ID de la sesión de escaneo activa.
  @visibleForTesting
  int? get scanSessionId => _scanSessionId;
  int? _scanSessionId;

  BleBloc({
    required this.repository,
    required this.userRepository,
    required this.remoteRelationRepository,
    required this.nodeRepository,
    required this.connectionRepository,
    Duration? dutyCyclePeriod,
  }) : _dutyCyclePeriod =
           dutyCyclePeriod ?? dutyCycleScanDuration + dutyCyclePauseDuration,
       super(const BleInitial()) {
    on<StartScan>(_onStartScan);
    on<StopScan>(_onStopScan);
    on<StartAdvertise>(_onStartAdvertise);
    on<StopAdvertise>(_onStopAdvertise);
    on<BluetoothStateChanged>(_onBluetoothStateChanged);
    on<LinkRequestReceived>(_onLinkRequestReceived);
    on<AcceptLinkRequest>(_onAcceptLinkRequest);
    on<RejectLinkRequest>(_onRejectLinkRequest);
    on<_PeerGraphReceived>(_onPeerGraphReceived);
    on<_ScanResultsUpdated>(_onScanResultsUpdated);
    on<_ScanError>(_onScanError);
    on<EvictStaleDevices>(_onEvictStaleDevices);

    /// Timer de evicción periódica.
    _evictionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!isClosed) {
        add(const EvictStaleDevices());
      }
    });

    /// Suscripción al estado real del adaptador Bluetooth.
    _btSubscription = repository.bluetoothState.listen((isOn) {
      if (!isClosed) {
        add(BluetoothStateChanged(isOn));
      }
    });

    /// Escucha las escrituras recibidas en la característica GATT destinada
    /// a LinkRequest.
    ///
    /// El datasource entrega únicamente bytes. El protocolo se interpreta
    /// recién en esta capa.
    _linkRequestSubscription = repository.incomingLinkRequests.listen(
      (write) {
        if (isClosed) {
          return;
        }

        try {
          final request = NodosLinkRequest.fromBytes(write.payload);
          add(LinkRequestReceived(request));
        } catch (error) {
          debugPrint('[BleBloc] LinkRequest inválido ignorado: $error');
        }
      },
      onError: (Object error) {
        debugPrint('[BleBloc] Error recibiendo LinkRequest: $error');
      },
    );

    /// Escucha los snapshots activos escritos por un peer Nodos en la
    /// característica peerGraph (205).
    ///
    /// El callback del stream solamente transporta el evento al BLoC.
    /// La validación del protocolo y la persistencia se realizan dentro
    /// de [_onPeerGraphReceived].
    _peerGraphSubscription = repository.incomingPeerGraphPayloads.listen(
      (write) {
        if (!isClosed) {
          add(_PeerGraphReceived(write.payload));
        }
      },
      onError: (Object error) {
        debugPrint('[BleBloc] Error recibiendo peer graph: $error');
      },
    );
  }

  Future<void> _onStartScan(StartScan event, Emitter<BleState> emit) async {
    if (state is BluetoothOff) {
      emit(
        const BleError(
          'Bluetooth está apagado. Enciéndelo desde Ajustes para escanear.',
        ),
      );
      return;
    }

    _dutyCycleTimer?.cancel();

    try {
      await _scanSubscription?.cancel();

      _accumulatedDevices.clear();

      _scanSubscription = repository.scanResults.listen(
        (devices) {
          if (!isClosed) {
            add(_ScanResultsUpdated(devices));
          }
        },
        onError: (Object error) {
          if (!isClosed) {
            add(_ScanError(error.toString()));
          }
        },
      );

      await repository.startScan();

      emit(const BleScanning());

      _dutyCycleTimer = Timer.periodic(_dutyCyclePeriod, (_) {
        if (!isClosed) {
          repository.startScan();
        }
      });
    } catch (e) {
      emit(BleError(e.toString()));
    }
  }

  Future<void> _onStopScan(StopScan event, Emitter<BleState> emit) async {
    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;

    await _scanSubscription?.cancel();
    _scanSubscription = null;

    await repository.stopScan();

    await repository.endScanSession();

    _scanSessionId = null;

    emit(const BleStopped());
  }

  Future<void> _onStartAdvertise(
    StartAdvertise event,
    Emitter<BleState> emit,
  ) async {
    await repository.startAdvertise(event.deviceUuid, event.name, event.color);

    emit(const BleAdvertising());
  }

  Future<void> _onStopAdvertise(
    StopAdvertise event,
    Emitter<BleState> emit,
  ) async {
    await repository.stopAdvertise();

    _pendingLinkRequest = null;
    _awaitingPeerGraphUuid = null;

    emit(const BleStopped());
  }

  void _onBluetoothStateChanged(
    BluetoothStateChanged event,
    Emitter<BleState> emit,
  ) {
    if (event.isOn) {
      emit(const BleStopped());
    } else {
      _pendingLinkRequest = null;
      _awaitingPeerGraphUuid = null;
      emit(const BluetoothOff());
    }
  }

  /// Procesa una solicitud Nodos recibida mediante GATT.
  ///
  /// Solo puede existir una solicitud pendiente a la vez.
  ///
  /// Si llega nuevamente la misma solicitud mientras todavía está pendiente,
  /// se ignora como duplicado.
  ///
  /// Si llega una solicitud de otro dispositivo mientras existe una pendiente,
  /// se responde automáticamente con rechazo para no reemplazar silenciosamente
  /// la decisión que el usuario ya tiene en pantalla.
  Future<void> _onLinkRequestReceived(
    LinkRequestReceived event,
    Emitter<BleState> emit,
  ) async {
    final request = event.request;

    final localUser = await userRepository.getUserProfile();

    if (localUser == null) {
      debugPrint('[BleBloc] LinkRequest ignorado: no existe perfil local.');
      return;
    }

    if (request.deviceUuid == localUser.uuid) {
      debugPrint(
        '[BleBloc] LinkRequest ignorado: solicitud proveniente '
        'de la propia instalación.',
      );
      return;
    }

    final pending = _pendingLinkRequest;

    if (pending != null) {
      if (pending.deviceUuid == request.deviceUuid) {
        debugPrint(
          '[BleBloc] LinkRequest duplicado ignorado: '
          '${request.deviceUuid}',
        );
        return;
      }

      final rejection = NodosLinkResponse(
        requesterUuid: request.deviceUuid,
        responderUuid: localUser.uuid,
        accepted: false,
      );

      try {
        await repository.sendLinkResponse(rejection.toBytes());
      } catch (error) {
        debugPrint(
          '[BleBloc] No se pudo rechazar automáticamente '
          'LinkRequest concurrente: $error',
        );
      }

      return;
    }

    /// Si todavía esperamos el grafo de un peer previamente aceptado,
    /// no reemplazamos esa autorización transitoria con otra solicitud.
    if (_awaitingPeerGraphUuid != null) {
      final rejection = NodosLinkResponse(
        requesterUuid: request.deviceUuid,
        responderUuid: localUser.uuid,
        accepted: false,
      );

      try {
        await repository.sendLinkResponse(rejection.toBytes());
      } catch (error) {
        debugPrint(
          '[BleBloc] No se pudo rechazar LinkRequest mientras '
          'se esperaba un peer graph: $error',
        );
      }

      return;
    }

    _pendingLinkRequest = request;

    if (!_linkRequestController.isClosed) {
      _linkRequestController.add(request);
    }
  }

  /// Acepta una solicitud de enlace Nodos.
  ///
  /// Antes de responder `accepted: true`:
  ///
  /// 1. resuelve o materializa el Node estable del requester;
  /// 2. obtiene el Node local;
  /// 3. persiste la relación local self -> requester.
  ///
  /// Solamente después de completar esos pasos se envía la aceptación.
  Future<void> _onAcceptLinkRequest(
    AcceptLinkRequest event,
    Emitter<BleState> emit,
  ) async {
    final pending = _pendingLinkRequest;

    if (pending == null || pending.deviceUuid != event.requesterUuid) {
      debugPrint(
        '[BleBloc] AcceptLinkRequest ignorado: '
        'la solicitud ya no está pendiente.',
      );
      return;
    }

    final localUser = await userRepository.getUserProfile();

    if (localUser == null || localUser.uuid.trim().isEmpty) {
      debugPrint(
        '[BleBloc] No se puede aceptar LinkRequest: '
        'no existe una identidad local válida.',
      );
      return;
    }

    try {
      final peerNode = await _resolveOrCreatePeerNode(pending);

      final peerNodeId = peerNode.id;

      if (peerNodeId == null) {
        throw StateError('El Node del requester no posee un id persistente.');
      }

      final selfNode = await nodeRepository.getSelfNode();
      final selfNodeId = selfNode?.id;

      if (selfNode == null || selfNodeId == null) {
        throw StateError('No existe un Node local persistente válido.');
      }

      if (selfNode.deviceUuid == pending.deviceUuid ||
          selfNodeId == peerNodeId) {
        throw StateError('El requester coincide con el Node local.');
      }

      await connectionRepository.saveConnection(selfNodeId, peerNodeId);

      final response = NodosLinkResponse(
        requesterUuid: pending.deviceUuid,
        responderUuid: localUser.uuid,
        accepted: true,
      );

      await repository.sendLinkResponse(response.toBytes());

      _awaitingPeerGraphUuid = pending.deviceUuid;
      _pendingLinkRequest = null;

      debugPrint(
        '[BleBloc] Enlace local persistido y LinkRequest aceptado: '
        '${pending.deviceUuid}.',
      );
    } catch (error) {
      debugPrint(
        '[BleBloc] No se pudo completar la aceptación '
        'de LinkRequest: $error',
      );
    }
  }

  /// Resuelve el Node canónico de un requester Nodos.
  ///
  /// Si ya existe por deviceUuid, actualiza sus metadatos conservando
  /// cualquier información de transporte previamente conocida.
  ///
  /// Si todavía no existe, crea un Node estable sin inventar bleAddress.
  ///
  /// No se intenta reconciliar por nombre o color porque esos valores
  /// no constituyen identidad.
  Future<Node> _resolveOrCreatePeerNode(NodosLinkRequest request) async {
    final existing = await nodeRepository.getNodeByDeviceUuid(
      request.deviceUuid,
    );

    final now = DateTime.now();

    if (existing != null) {
      final updated = existing.copyWith(
        deviceUuid: request.deviceUuid,
        name: request.name,
        color: request.color,
        lastSeen: now,
      );

      await nodeRepository.upsertNode(updated);

      final persisted = await nodeRepository.getNodeByDeviceUuid(
        request.deviceUuid,
      );

      if (persisted == null) {
        throw StateError('No se pudo recuperar el Node Nodos actualizado.');
      }

      return persisted;
    }

    final peer = Node(
      deviceUuid: request.deviceUuid,
      bleAddress: null,
      remoteRef: null,
      isSelf: false,
      name: request.name,
      color: request.color,
      firstSeen: now,
      lastSeen: now,
      connectable: false,
    );

    await nodeRepository.upsertNode(peer);

    final persisted = await nodeRepository.getNodeByDeviceUuid(
      request.deviceUuid,
    );

    if (persisted == null) {
      throw StateError('No se pudo recuperar el Node Nodos recién creado.');
    }

    return persisted;
  }

  /// Rechaza la solicitud pendiente indicada por [RejectLinkRequest].
  Future<void> _onRejectLinkRequest(
    RejectLinkRequest event,
    Emitter<BleState> emit,
  ) async {
    final pending = _pendingLinkRequest;

    if (pending == null || pending.deviceUuid != event.requesterUuid) {
      debugPrint(
        '[BleBloc] RejectLinkRequest ignorado: '
        'la solicitud ya no está pendiente.',
      );
      return;
    }

    final localUser = await userRepository.getUserProfile();

    if (localUser == null) {
      debugPrint(
        '[BleBloc] No se puede rechazar LinkRequest: '
        'no existe perfil local.',
      );
      return;
    }

    final response = NodosLinkResponse(
      requesterUuid: pending.deviceUuid,
      responderUuid: localUser.uuid,
      accepted: false,
    );

    try {
      await repository.sendLinkResponse(response.toBytes());

      _pendingLinkRequest = null;
    } catch (error) {
      debugPrint('[BleBloc] Error enviando rechazo de LinkRequest: $error');
    }
  }

  /// Procesa un NodosGraphPayload recibido mediante WRITE en la
  /// característica peerGraph (205).
  ///
  /// La escritura solamente se acepta si:
  ///
  /// 1. existe un peer cuyo grafo estamos esperando;
  /// 2. el payload es válido;
  /// 3. ownerUuid coincide exactamente con el UUID del requester aceptado.
  ///
  /// Una vez persistido correctamente el snapshot, la autorización
  /// transitoria se consume.
  Future<void> _onPeerGraphReceived(
    _PeerGraphReceived event,
    Emitter<BleState> emit,
  ) async {
    final expectedUuid = _awaitingPeerGraphUuid;

    if (expectedUuid == null) {
      debugPrint(
        '[BleBloc] Peer graph ignorado: '
        'no existe un enlace aceptado esperando snapshot.',
      );
      return;
    }

    final NodosGraphPayload payload;

    try {
      payload = NodosGraphPayload.fromBytes(event.payload);
    } catch (error) {
      debugPrint('[BleBloc] Peer graph inválido ignorado: $error');
      return;
    }

    if (payload.ownerUuid != expectedUuid) {
      debugPrint(
        '[BleBloc] Peer graph ignorado: ownerUuid inesperado '
        '(${payload.ownerUuid}). Esperado: $expectedUuid.',
      );
      return;
    }

    try {
      await remoteRelationRepository.replaceSnapshot(
        reporterUuid: payload.ownerUuid,
        connections: payload.connections,
      );

      _awaitingPeerGraphUuid = null;

      debugPrint(
        '[BleBloc] Peer graph persistido: '
        '${payload.ownerUuid} '
        '(${payload.connections.length} relaciones activas).',
      );
    } catch (error) {
      debugPrint(
        '[BleBloc] Error persistiendo peer graph '
        '${payload.ownerUuid}: $error',
      );
    }
  }

  /// Fusión, evicción y capping de dispositivos BLE (función pura).
  @visibleForTesting
  static List<BleDevice> accumulateDevices(
    Map<String, BleDevice> current,
    List<BleDevice> incoming, {
    Duration staleThreshold = _staleThreshold,
    int maxDevices = _maxDevices,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final merged = Map<String, BleDevice>.from(current);

    // Paso 1: Fusionar.
    for (final device in incoming) {
      final existing = merged[device.deviceId];

      if (existing == null || device.timestamp.isAfter(existing.timestamp)) {
        merged[device.deviceId] = device;
      }
    }

    // Paso 2: Evicción por antigüedad.
    merged.removeWhere((_, device) {
      final age = effectiveNow.difference(device.timestamp);
      return age > staleThreshold;
    });

    // Paso 3: Capping.
    if (merged.length > maxDevices) {
      final sorted = merged.entries.toList()
        ..sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));

      return sorted.take(maxDevices).map((e) => e.value).toList();
    }

    return merged.values.toList();
  }

  /// Fusiona dispositivos del batch actual en el acumulador.
  void _onScanResultsUpdated(
    _ScanResultsUpdated event,
    Emitter<BleState> emit,
  ) {
    final accumulated = accumulateDevices(_accumulatedDevices, event.devices);

    _accumulatedDevices.clear();

    for (final device in accumulated) {
      _accumulatedDevices[device.deviceId] = device;
    }

    emit(BleScanning(devices: accumulated));
  }

  /// Limpia dispositivos stale del acumulador sin nuevos datos BLE.
  void _onEvictStaleDevices(EvictStaleDevices event, Emitter<BleState> emit) {
    if (_accumulatedDevices.isEmpty) {
      return;
    }

    final before = _accumulatedDevices.length;
    final now = DateTime.now();

    _accumulatedDevices.removeWhere((_, device) {
      final age = now.difference(device.timestamp);
      return age > _staleThreshold;
    });

    if (_accumulatedDevices.length < before) {
      emit(BleScanning(devices: _accumulatedDevices.values.toList()));
    }
  }

  void _onScanError(_ScanError event, Emitter<BleState> emit) {
    emit(BleError(event.message));
  }

  @override
  Future<void> close() async {
    _scanSessionId = null;

    await _scanSubscription?.cancel();
    await _btSubscription?.cancel();
    await _linkRequestSubscription?.cancel();
    await _peerGraphSubscription?.cancel();

    _evictionTimer?.cancel();
    _evictionTimer = null;

    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;

    _pendingLinkRequest = null;
    _awaitingPeerGraphUuid = null;

    await _linkRequestController.close();

    return super.close();
  }
}

/// Evento interno para resultados de escaneo.
class _ScanResultsUpdated extends BleEvent {
  final List<BleDevice> devices;

  const _ScanResultsUpdated(this.devices);

  @override
  List<Object> get props => [devices];
}

/// Evento interno para errores del stream de escaneo.
class _ScanError extends BleEvent {
  final String message;

  const _ScanError(this.message);

  @override
  List<Object> get props => [message];
}

/// Evento interno para transportar al BLoC un payload escrito por un peer
/// Nodos en la característica GATT peerGraph (205).
class _PeerGraphReceived extends BleEvent {
  final List<int> payload;

  const _PeerGraphReceived(this.payload);

  @override
  List<Object> get props => [payload];
}
