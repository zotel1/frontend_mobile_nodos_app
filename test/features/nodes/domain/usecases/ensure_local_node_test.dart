import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/repositories/node_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/ensure_local_node.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/repositories/user_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart'
    as domain;

void main() {
  late AppDatabase db;
  late NodeRepositoryImpl nodeRepository;
  late UserRepositoryImpl userRepository;
  late EnsureLocalNode ensureLocalNode;

  const userUuid = 'local-device-uuid-001';

  domain.User makeUser({
    String name = 'Nodo-cris',
    String color = '#2196F3',
    int? localNodeId,
  }) {
    return domain.User(
      uuid: userUuid,
      name: name,
      color: color,
      deviceType: 'android',
      createdAt: DateTime(2026, 9, 11),
      localNodeId: localNodeId,
    );
  }

  setUp(() {
    db = AppDatabase.inMemory();

    nodeRepository = NodeRepositoryImpl(NodeDriftDataSource(db));

    userRepository = UserRepositoryImpl(UserDriftDataSource(db));

    ensureLocalNode = EnsureLocalNode(
      nodeRepository: nodeRepository,
      userRepository: userRepository,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('ARCH001-T1: crea un self-node persistente con ID real', () async {
    final user = makeUser();

    await userRepository.createUser(user);

    final persistedUser = await userRepository.getUserProfile();

    expect(persistedUser, isNotNull);

    final result = await ensureLocalNode(persistedUser!);

    expect(result.isRight(), isTrue);

    final node = result.getOrElse(() => throw StateError('Expected self-node'));

    expect(node.id, isNotNull);
    expect(node.id, isNot(-1));

    expect(node.isSelf, isTrue);
    expect(node.deviceUuid, userUuid);
    expect(node.bleAddress, isNull);

    expect(node.name, 'Nodo-cris');
    expect(node.color, '#2196F3');

    final updatedUser = await userRepository.getUserProfile();

    expect(updatedUser, isNotNull);
    expect(updatedUser!.localNodeId, node.id);
  });

  test(
    'ARCH001-T2: ejecutar EnsureLocalNode dos veces no duplica el self-node',
    () async {
      await userRepository.createUser(makeUser());

      var user = await userRepository.getUserProfile();

      expect(user, isNotNull);

      final firstResult = await ensureLocalNode(user!);

      expect(firstResult.isRight(), isTrue);

      user = await userRepository.getUserProfile();

      expect(user, isNotNull);

      final secondResult = await ensureLocalNode(user!);

      expect(secondResult.isRight(), isTrue);

      final first = firstResult.getOrElse(
        () => throw StateError('Expected first node'),
      );

      final second = secondResult.getOrElse(
        () => throw StateError('Expected second node'),
      );

      expect(second.id, first.id);

      final allNodes = await nodeRepository.observeNodes().first;

      final selfNodes = allNodes.where((node) => node.isSelf).toList();

      expect(selfNodes, hasLength(1));
    },
  );

  test(
    'ARCH001-T3: adopta un Node existente con el mismo deviceUuid',
    () async {
      await userRepository.createUser(makeUser());

      final now = DateTime(2026, 9, 11);

      await nodeRepository.upsertNode(
        Node(
          deviceUuid: userUuid,
          bleAddress: 'AA:BB:CC:DD:EE:FF',
          isSelf: false,
          name: 'Nombre anterior',
          color: '#000000',
          firstSeen: now,
          lastSeen: now,
          deviceType: 'android',
        ),
      );

      final existing = await nodeRepository.getNodeByDeviceUuid(userUuid);

      expect(existing, isNotNull);
      expect(existing!.isSelf, isFalse);

      final user = await userRepository.getUserProfile();

      final result = await ensureLocalNode(user!);

      expect(result.isRight(), isTrue);

      final self = result.getOrElse(
        () => throw StateError('Expected self-node'),
      );

      expect(self.id, existing.id);
      expect(self.isSelf, isTrue);
      expect(self.name, 'Nodo-cris');
      expect(self.color, '#2196F3');

      // No debe perder una BLE address previamente conocida.
      expect(self.bleAddress, 'AA:BB:CC:DD:EE:FF');

      final updatedUser = await userRepository.getUserProfile();

      expect(updatedUser!.localNodeId, existing.id);
    },
  );

  test('ARCH001-T4: User.localNodeId apunta al self-node real', () async {
    await userRepository.createUser(makeUser());

    final user = await userRepository.getUserProfile();

    final result = await ensureLocalNode(user!);

    final self = result.getOrElse(() => throw StateError('Expected self-node'));

    final updatedUser = await userRepository.getUserProfile();

    expect(updatedUser, isNotNull);
    expect(updatedUser!.localNodeId, isNotNull);

    final referencedNode = await nodeRepository.getNodeById(
      updatedUser.localNodeId!,
    );

    expect(referencedNode, isNotNull);
    expect(referencedNode!.id, self.id);
    expect(referencedNode.isSelf, isTrue);
    expect(referencedNode.deviceUuid, userUuid);
  });

  test(
    'ARCH001-T5: cambios de nombre y color se sincronizan al self-node',
    () async {
      await userRepository.createUser(makeUser());

      var user = await userRepository.getUserProfile();

      await ensureLocalNode(user!);

      await userRepository.updateName('Cristian');

      await userRepository.updateColor('#E91E63');

      user = await userRepository.getUserProfile();

      expect(user, isNotNull);

      final result = await ensureLocalNode(user!);

      expect(result.isRight(), isTrue);

      final self = result.getOrElse(
        () => throw StateError('Expected self-node'),
      );

      expect(self.name, 'Cristian');
      expect(self.color, '#E91E63');

      final allNodes = await nodeRepository.observeNodes().first;

      expect(allNodes.where((node) => node.isSelf), hasLength(1));
    },
  );
}
