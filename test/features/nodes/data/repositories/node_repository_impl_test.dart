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

    // ──────────────────────────────────────────────────────────
    // T-PR2-001 RED: Metadata preservation — suggestedName y deviceType
    // se preservan del nodo original al actualizar metadata.
    //
    // QUÉ: cuando updateNodeMetadata modifica name o color, los campos
    // suggestedName y deviceType del nodo existente deben preservarse
    // en el nodo actualizado.
    //
    // POR QUÉ problema existe: el método actual construye un nuevo Node
    // sin incluir suggestedName ni deviceType del nodo existente → estos
    // campos se pierden silenciosamente tras cualquier llamada a
    // updateNodeMetadata.
    //
    // Estado RED esperado: los expects de suggestedName y deviceType
    // fallan porque el código actual no los preserva.
    // ──────────────────────────────────────────────────────────
    test(
        'T-PR2-001 RED: updateNodeMetadata preserva suggestedName y deviceType del nodo original',
        () async {
      final existing = Node(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Nodo Original',
        color: '#808080',
        suggestedName: 'MiDispositivo',
        deviceType: 'Reloj/Fitness',
        firstSeen: now,
        lastSeen: now,
        rssiHistory: const [-50, -60],
      );
      when(mockDataSource.getNodeById(1)).thenAnswer((_) async => existing);
      when(mockDataSource.upsertNode(any)).thenAnswer((_) async {});

      await repository.updateNodeMetadata(1, name: 'Nodo Renombrado');

      final captured = verify(mockDataSource.upsertNode(captureAny)).captured;
      final updatedNode = captured.first as Node;

      // Verificar que el nombre se actualizó
      expect(updatedNode.name, 'Nodo Renombrado');
      // Verificar que el color original se preservó (no se pasó en la llamada)
      expect(updatedNode.color, '#808080');
      // CRÍTICO: suggestedName y deviceType deben preservarse del original
      expect(updatedNode.suggestedName, 'MiDispositivo');
      expect(updatedNode.deviceType, 'Reloj/Fitness');
    });

    test(
        'T-PR2-001 RED: updateNodeMetadata preserva suggestedName/deviceType cuando solo se actualiza color',
        () async {
      final existing = Node(
        id: 2,
        bleAddress: 'BB:CC:DD:EE:FF:00',
        name: 'Nodo Beta',
        color: '#333333',
        suggestedName: 'TV Samsung',
        deviceType: 'TV/Display',
        firstSeen: now,
        lastSeen: now,
      );
      when(mockDataSource.getNodeById(2)).thenAnswer((_) async => existing);
      when(mockDataSource.upsertNode(any)).thenAnswer((_) async {});

      await repository.updateNodeMetadata(2, color: '#FF5722');

      final captured = verify(mockDataSource.upsertNode(captureAny)).captured;
      final updatedNode = captured.first as Node;

      expect(updatedNode.name, 'Nodo Beta');
      expect(updatedNode.color, '#FF5722');
      expect(updatedNode.suggestedName, 'TV Samsung');
      expect(updatedNode.deviceType, 'TV/Display');
    });
  });
}
