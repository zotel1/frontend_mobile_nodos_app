import 'package:dartz/dartz.dart';

import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';

/// Garantiza que el perfil local tenga exactamente un Node persistente
/// que represente a este dispositivo dentro del grafo.
///
/// ARCH-001
///
/// Invariantes:
///
/// - User.id NO identifica un nodo.
/// - User.uuid es la identidad estable de esta instalación.
/// - User.localNodeId referencia al Node real del dispositivo local.
/// - El self-node usa un ID real de SQLite.
/// - El self-node se identifica mediante isSelf=true.
/// - No se utiliza id=-1.
/// - Ejecutar este caso de uso repetidas veces no debe duplicar el self-node.
class EnsureLocalNode {
  final NodeRepository _nodeRepository;
  final UserRepository _userRepository;

  const EnsureLocalNode({
    required NodeRepository nodeRepository,
    required UserRepository userRepository,
  }) : _nodeRepository = nodeRepository,
       _userRepository = userRepository;

  Future<Either<Failure, Node>> call(User user) async {
    try {
      // ──────────────────────────────────────────────────────
      // 1. Si User ya referencia un Node válido, reutilizarlo.
      // ──────────────────────────────────────────────────────
      if (user.localNodeId != null) {
        final referencedNode = await _nodeRepository.getNodeById(
          user.localNodeId!,
        );

        if (referencedNode != null && referencedNode.deviceUuid == user.uuid) {
          final synced = _syncFromUser(referencedNode, user);

          await _nodeRepository.upsertNode(synced);

          final persisted = await _nodeRepository.getNodeById(
            referencedNode.id!,
          );

          if (persisted == null) {
            return Left(
              CacheFailure(
                'No se pudo recuperar el nodo local después de actualizarlo.',
              ),
            );
          }

          return Right(persisted);
        }
      }

      // ──────────────────────────────────────────────────────
      // 2. Buscar un Node que ya tenga el UUID estable del User.
      // ──────────────────────────────────────────────────────
      final byUuid = await _nodeRepository.getNodeByDeviceUuid(user.uuid);

      if (byUuid != null) {
        if (byUuid.id == null) {
          return Left(
            CacheFailure(
              'El nodo local encontrado no tiene un ID persistente.',
            ),
          );
        }

        final synced = _syncFromUser(byUuid, user);

        await _nodeRepository.upsertNode(synced);
        await _userRepository.setLocalNodeId(byUuid.id!);

        final persisted = await _nodeRepository.getNodeById(byUuid.id!);

        if (persisted == null) {
          return Left(
            CacheFailure(
              'No se pudo recuperar el nodo local después de asociarlo.',
            ),
          );
        }

        return Right(persisted);
      }

      // ──────────────────────────────────────────────────────
      // 3. Si existe un self previo sin deviceUuid, adoptarlo.
      //
      // Este caso sirve principalmente para tolerar estados
      // intermedios o migraciones futuras.
      // ──────────────────────────────────────────────────────
      final existingSelf = await _nodeRepository.getSelfNode();

      if (existingSelf != null) {
        if (existingSelf.id == null) {
          return Left(
            CacheFailure('El self-node existente no tiene un ID persistente.'),
          );
        }

        // Si existe un self con OTRO UUID estable, la base está en
        // un estado inconsistente. No debemos secuestrar ese nodo.
        if (existingSelf.deviceUuid != null &&
            existingSelf.deviceUuid != user.uuid) {
          return Left(
            CacheFailure(
              'Existe un self-node asociado a una identidad distinta.',
            ),
          );
        }

        final adopted = existingSelf.copyWith(
          deviceUuid: user.uuid,
          isSelf: true,
          name: user.name,
          color: user.color,
          deviceType: user.deviceType,
          connectable: false,
        );

        await _nodeRepository.upsertNode(adopted);
        await _userRepository.setLocalNodeId(existingSelf.id!);

        final persisted = await _nodeRepository.getNodeById(existingSelf.id!);

        if (persisted == null) {
          return Left(
            CacheFailure('No se pudo recuperar el self-node adoptado.'),
          );
        }

        return Right(persisted);
      }

      // ──────────────────────────────────────────────────────
      // 4. No existe representación local → crear una.
      // ──────────────────────────────────────────────────────
      final now = DateTime.now();

      final selfNode = Node(
        deviceUuid: user.uuid,
        bleAddress: null,
        isSelf: true,
        name: user.name,
        color: user.color,
        firstSeen: user.createdAt,
        lastSeen: now,
        rssiHistory: const [],
        suggestedName: user.name,
        deviceType: user.deviceType,
        connectable: false,
        estimatedDistance: 0.0,
      );

      await _nodeRepository.upsertNode(selfNode);

      // Como el INSERT asigna el ID en Drift, recuperamos por UUID.
      final created = await _nodeRepository.getNodeByDeviceUuid(user.uuid);

      if (created == null || created.id == null) {
        return Left(
          CacheFailure('No se pudo crear el nodo local persistente.'),
        );
      }

      await _userRepository.setLocalNodeId(created.id!);

      return Right(created);
    } catch (e) {
      return Left(UnexpectedFailure('Error al asegurar el nodo local: $e'));
    }
  }

  /// Sincroniza metadata de perfil sin modificar la identidad técnica
  /// persistida del Node.
  Node _syncFromUser(Node node, User user) {
    return node.copyWith(
      deviceUuid: user.uuid,
      isSelf: true,
      name: user.name,
      color: user.color,
      deviceType: user.deviceType,
      connectable: false,
      estimatedDistance: 0.0,
      lastSeen: DateTime.now(),
    );
  }
}
