import 'dart:async';
import 'dart:typed_data';

import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

/// Mantiene y publica el snapshot del grafo BLE activo de esta instalación.
///
/// IMPORTANTE:
///
/// Este servicio NO utiliza la tabla `connections` como fuente del grafo.
///
/// `connections` representa enlaces persistentes/históricos.
///
/// Este servicio representa únicamente dispositivos cuya conexión BLE
/// se encuentra activa desde el punto de vista de Nodos.
///
/// Ejemplo:
///
/// A25 tiene enlazados históricamente:
///
/// - Watch
/// - Charge 3
/// - Auriculares
///
/// Pero actualmente solo están conectados:
///
/// - Watch
/// - Charge 3
///
/// Entonces el payload publicado contiene únicamente:
///
/// A25 -> Watch
/// A25 -> Charge 3
///
/// Los auriculares continúan persistidos localmente, pero no forman parte
/// del snapshot distribuido.
class ActiveGraphExchangeService {
  final NodeRepository _nodeRepository;
  final UserRepository _userRepository;
  final BleRepository _bleRepository;

  /// remoteId / dirección BLE de cada dispositivo cuya conexión está activa.
  ///
  /// No se transmite directamente a otros dispositivos.
  ///
  /// Se utiliza solamente como identidad local de transporte para resolver
  /// el [Node] correspondiente.
  final Set<String> _activeRemoteIds = <String>{};

  /// Serializa modificaciones/publicaciones del snapshot.
  ///
  /// Evita que dos cambios rápidos de conexión reconstruyan y publiquen
  /// snapshots fuera de orden.
  Future<void> _operationQueue = Future<void>.value();

  ActiveGraphExchangeService({
    required NodeRepository nodeRepository,
    required UserRepository userRepository,
    required BleRepository bleRepository,
  }) : _nodeRepository = nodeRepository,
       _userRepository = userRepository,
       _bleRepository = bleRepository;

  /// Snapshot local de remoteIds actualmente considerados activos.
  ///
  /// Se devuelve una copia inmutable para impedir modificaciones externas.
  Set<String> get activeRemoteIds => Set<String>.unmodifiable(_activeRemoteIds);

  /// Indica que [remoteId] pasó al estado conectado.
  ///
  /// Si ya estaba activo, simplemente vuelve a publicar el snapshot.
  Future<void> markConnected(String remoteId) {
    return _enqueue(() async {
      final normalizedRemoteId = remoteId.trim();

      if (normalizedRemoteId.isEmpty) {
        return;
      }

      _activeRemoteIds.add(normalizedRemoteId);

      await _publishCurrentSnapshot();
    });
  }

  /// Indica que [remoteId] dejó de estar conectado.
  ///
  /// Aunque el dispositivo siga existiendo en SQLite o conserve una
  /// relación persistente en `connections`, deja de aparecer inmediatamente
  /// en el snapshot activo.
  Future<void> markDisconnected(String remoteId) {
    return _enqueue(() async {
      final normalizedRemoteId = remoteId.trim();

      if (normalizedRemoteId.isEmpty) {
        return;
      }

      _activeRemoteIds.remove(normalizedRemoteId);

      await _publishCurrentSnapshot();
    });
  }

  /// Elimina todas las conexiones activas conocidas y publica un snapshot
  /// vacío.
  ///
  /// Puede utilizarse, por ejemplo, cuando Bluetooth se apaga o cuando el
  /// ciclo BLE completo se reinicia.
  Future<void> clear() {
    return _enqueue(() async {
      _activeRemoteIds.clear();

      await _publishCurrentSnapshot();
    });
  }

  /// Fuerza la publicación del estado actual sin modificar conexiones.
  ///
  /// Es útil al iniciar advertising para que la característica GATT del
  /// grafo tenga desde el principio un payload válido, incluso cuando el
  /// conjunto de conexiones sea vacío.
  Future<void> publishCurrentSnapshot() {
    return _enqueue(_publishCurrentSnapshot);
  }

  /// Construye el payload correspondiente al grafo BLE activo actual.
  ///
  /// Este método es la única fuente de verdad para serializar las relaciones
  /// activas que esta instalación puede compartir con otro nodo Nodos.
  ///
  /// Se utiliza tanto para:
  ///
  /// - publicar el snapshot mediante la característica GATT normal del
  ///   peripheral;
  /// - enviar el mismo snapshot desde el central hacia otro Nodos después
  ///   de que un LinkRequest haya sido aceptado.
  ///
  /// No modifica [_activeRemoteIds] ni publica nada por sí mismo.
  Future<NodosGraphPayload> buildCurrentPayload() async {
    final user = await _userRepository.getUserProfile();

    if (user == null) {
      throw StateError(
        'No se puede construir el grafo activo: '
        'no existe un perfil local.',
      );
    }

    final ownerUuid = user.uuid.trim();

    if (ownerUuid.isEmpty) {
      throw StateError(
        'No se puede construir el grafo activo: '
        'el UUID local está vacío.',
      );
    }

    final connections = <NodosGraphConnection>[];

    // Copia defensiva porque las consultas siguientes son async.
    final remoteIds = List<String>.from(_activeRemoteIds);

    for (final remoteId in remoteIds) {
      final node = await _nodeRepository.getNodeByBleAddress(remoteId);

      if (node == null) {
        // La conexión puede haberse establecido antes de que el scan haya
        // persistido completamente el Node.
        //
        // No inventamos identidad ni transmitimos el remoteId.
        continue;
      }

      final connection = _buildConnection(ownerUuid: ownerUuid, node: node);

      if (connection != null) {
        connections.add(connection);
      }
    }

    return NodosGraphPayload(ownerUuid: ownerUuid, connections: connections);
  }

  /// Ejecuta las operaciones secuencialmente.
  ///
  /// Es importante porque una conexión y una desconexión pueden ocurrir
  /// prácticamente al mismo tiempo. Sin serialización podría terminar
  /// publicándose después un snapshot construido con estado anterior.
  Future<void> _enqueue(Future<void> Function() operation) {
    final completer = Completer<void>();

    _operationQueue = _operationQueue.then((_) async {
      try {
        await operation();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  /// Construye y publica el snapshot activo actual.
  ///
  /// La construcción real está centralizada en [buildCurrentPayload] para
  /// garantizar que las características 203 y 205 utilicen exactamente
  /// las mismas reglas de identidad y filtrado.
  Future<void> _publishCurrentSnapshot() async {
    final payload = await buildCurrentPayload();

    await _bleRepository.updateGraphPayload(
      Uint8List.fromList(payload.toBytes()),
    );
  }

  /// Convierte un Node local en una referencia segura para intercambio.
  ///
  /// Nodos:
  ///   `nodos:<deviceUuid>`
  ///
  /// BLE genérico:
  ///   `local:<ownerUuid>:<Node.id>`
  ///
  /// Nunca se transmite [Node.bleAddress] como identidad global.
  NodosGraphConnection? _buildConnection({
    required String ownerUuid,
    required Node node,
  }) {
    if (node.isSelf) {
      return null;
    }

    final deviceUuid = node.deviceUuid?.trim();

    if (deviceUuid != null && deviceUuid.isNotEmpty) {
      // Evita publicar accidentalmente al propio dispositivo como vecino.
      if (deviceUuid == ownerUuid) {
        return null;
      }

      return NodosGraphConnection.nodos(
        deviceUuid: deviceUuid,
        name: _effectiveName(node),
        color: node.color,
        deviceType: node.deviceType,
      );
    }

    final nodeId = node.id;

    if (nodeId == null || nodeId <= 0) {
      // Un dispositivo genérico necesita un Node.id local persistente para
      // poder construir la referencia namespaced.
      return null;
    }

    return NodosGraphConnection.generic(
      ownerUuid: ownerUuid,
      localNodeId: nodeId,
      name: _effectiveName(node),
      deviceType: node.deviceType,
    );
  }

  String? _effectiveName(Node node) {
    final explicitName = node.name?.trim();

    if (explicitName != null && explicitName.isNotEmpty) {
      return explicitName;
    }

    final suggestedName = node.suggestedName?.trim();

    if (suggestedName != null && suggestedName.isNotEmpty) {
      return suggestedName;
    }

    return null;
  }
}
