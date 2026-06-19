import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/repositories/node_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';

@GenerateNiceMocks([MockSpec<NodeLocalDataSource>()])
import 'node_repository_impl_test.mocks.dart';

void main() {
  late MockNodeLocalDataSource mockDataSource;
  late NodeRepository repository;

  final now = DateTime(2026, 6, 18, 12, 0, 0);

  setUp(() {
    mockDataSource = MockNodeLocalDataSource();
    repository = NodeRepositoryImpl(mockDataSource);
  });

  group('NodeRepositoryImpl', () {
    test('implements NodeRepository', () {
      expect(repository, isA<NodeRepository>());
    });

    test('observeNodes delegates to data source watchNodes', () async {
      final nodesCtrl = StreamController<List<Node>>.broadcast();
      when(mockDataSource.watchNodes()).thenAnswer((_) => nodesCtrl.stream);

      final emitted = <List<Node>>[];
      final sub = repository.observeNodes().listen(emitted.add);

      final node = Node(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Test Node',
        firstSeen: now,
        lastSeen: now,
      );
      nodesCtrl.add([node]);

      await Future.delayed(Duration.zero);

      expect(emitted.length, 1);
      expect(emitted.first.length, 1);
      expect(emitted.first.first.bleAddress, 'AA:BB:CC:DD:EE:FF');

      await sub.cancel();
      await nodesCtrl.close();
    });

    test('getNodeById delegates to data source', () async {
      final node = Node(
        id: 42,
        bleAddress: 'BB:CC:DD:EE:FF:00',
        firstSeen: now,
        lastSeen: now,
      );
      when(mockDataSource.getNodeById(42))
          .thenAnswer((_) async => node);

      final result = await repository.getNodeById(42);

      expect(result, node);
      verify(mockDataSource.getNodeById(42)).called(1);
    });

    test('getNodeById returns null when not found', () async {
      when(mockDataSource.getNodeById(999))
          .thenAnswer((_) async => null);

      final result = await repository.getNodeById(999);

      expect(result, isNull);
    });

    test('upsertNode delegates to data source', () async {
      when(mockDataSource.upsertNode(any)).thenAnswer((_) async {});

      final node = Node(
        bleAddress: 'CC:DD:EE:FF:00:11',
        firstSeen: now,
        lastSeen: now,
      );
      await repository.upsertNode(node);

      verify(mockDataSource.upsertNode(node)).called(1);
    });

    test('updateNodeMetadata delegates to data source', () async {
      // Setup: upsert then update
      final existing = Node(
        id: 1,
        bleAddress: 'DD:EE:FF:00:11:22',
        firstSeen: now,
        lastSeen: now,
      );
      when(mockDataSource.getNodeById(1)).thenAnswer((_) async => existing);
      when(mockDataSource.upsertNode(any)).thenAnswer((_) async {});

      await repository.updateNodeMetadata(1, name: 'Updated', color: '#FFF');

      // Should have retrieved, modified and upserted
      verify(mockDataSource.getNodeById(1)).called(1);
      final captured = verify(mockDataSource.upsertNode(captureAny)).captured;
      expect(captured.length, 1);
      expect((captured.first as Node).name, 'Updated');
      expect((captured.first as Node).color, '#FFF');
    });

    test('updateNodeMetadata with only name leaves color unchanged', () async {
      final existing = Node(
        id: 1,
        bleAddress: 'EE:FF:00:11:22:33',
        name: 'Old Name',
        color: '#FF0000',
        firstSeen: now,
        lastSeen: now,
      );
      when(mockDataSource.getNodeById(1)).thenAnswer((_) async => existing);
      when(mockDataSource.upsertNode(any)).thenAnswer((_) async {});

      await repository.updateNodeMetadata(1, name: 'New Name');

      final captured = verify(mockDataSource.upsertNode(captureAny)).captured;
      final updatedNode = captured.first as Node;
      expect(updatedNode.name, 'New Name');
      expect(updatedNode.color, '#FF0000');
    });
  });
}
