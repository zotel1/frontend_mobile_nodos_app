import 'package:drift/drift.dart' hide Column;
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/repositories/graph_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';

@GenerateNiceMocks([MockSpec<NodeRepository>()])
import 'graph_repository_impl_test.mocks.dart';

void main() {
  late AppDatabase db;
  late MockNodeRepository mockNodeRepository;
  late GraphRepositoryImpl repository;

  setUp(() async {
    db = AppDatabase.inMemory();
    mockNodeRepository = MockNodeRepository();
    repository = GraphRepositoryImpl(mockNodeRepository, db);
  });

  tearDown(() async {
    await db.close();
  });

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  Future<int> insertNode(String address, [String name = 'Desconocido']) async {
    return db
        .into(db.nodes)
        .insert(
          NodesCompanion(
            bleAddress: Value(address),
            name: Value(name),
            firstSeen: Value(DateTime(2026, 6, 1)),
            lastSeen: Value(DateTime(2026, 6, 19)),
            lastRssi: const Value(-60),
            proximityZone: const Value('medium'),
            rssiHistory: const Value('[-60]'),
          ),
        );
  }

  Future<int> insertSession() async {
    return db
        .into(db.scanSessions)
        .insert(
          ScanSessionsCompanion.insert(
            startedAt: DateTime(2026, 6, 19),
            nodesDetected: 0,
          ),
        );
  }

  Future<void> insertSessionNode(
    int sessionId,
    int nodeId, [
    int rssi = -60,
  ]) async {
    await db
        .into(db.scanSessionNodes)
        .insert(
          ScanSessionNodesCompanion.insert(
            sessionId: sessionId,
            nodeId: nodeId,
            rssi: rssi,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> insertConnection(int fromId, int toId) async {
    await db
        .into(db.connections)
        .insert(
          ConnectionsCompanion.insert(
            fromNodeId: fromId,
            toNodeId: toId,
            createdAt: DateTime(2026, 6, 19),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  void mockNodeLookup(int id, String address, [String name = 'Desconocido']) {
    when(mockNodeRepository.getNodeById(id)).thenAnswer(
      (_) async => Node(
        id: id,
        bleAddress: address,
        name: name,
        firstSeen: DateTime(2026, 6, 1),
        lastSeen: DateTime(2026, 6, 19),
        rssiHistory: const [-60],
      ),
    );
  }

  Node makePersistentSelf({
    int id = 99,
    String uuid = 'self-device-uuid',
    String name = 'Mi dispositivo',
  }) {
    return Node(
      id: id,
      deviceUuid: uuid,
      bleAddress: null,
      isSelf: true,
      name: name,
      color: '#2196F3',
      firstSeen: DateTime(2026, 6, 1),
      lastSeen: DateTime(2026, 6, 19),
      rssiHistory: const [],
      deviceType: 'android',
      connectable: false,
      estimatedDistance: 0.0,
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T2.1 — Co-detection counting query
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('T2.1: getCoDetectionCounts', () {
    test('retorna mapa vacío cuando no hay sesiones', () async {
      final counts = await repository.getCoDetectionCounts();

      expect(counts, isEmpty);
    });

    test('retorna mapa vacío cuando hay sesiones con un solo nodo', () async {
      final session = await insertSession();

      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      await insertSessionNode(session, nodeA);

      final counts = await repository.getCoDetectionCounts();

      expect(counts, isEmpty);
    });

    test(
      'cuenta una co-detección para un par en una sesión compartida',
      () async {
        final session = await insertSession();

        final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

        final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

        await insertSessionNode(session, nodeA);

        await insertSessionNode(session, nodeB);

        final counts = await repository.getCoDetectionCounts();

        final keyA = '$nodeA-$nodeB';
        final keyB = '$nodeB-$nodeA';

        expect(counts[keyA], equals(1));

        expect(counts.containsKey(keyB), isFalse);
      },
    );

    test(
      'cuenta múltiples co-detecciones entre dos nodos en varias sesiones',
      () async {
        final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

        final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

        final s1 = await insertSession();

        await insertSessionNode(s1, nodeA);

        await insertSessionNode(s1, nodeB);

        final s2 = await insertSession();

        await insertSessionNode(s2, nodeA);

        await insertSessionNode(s2, nodeB);

        final s3 = await insertSession();

        await insertSessionNode(s3, nodeA);

        final counts = await repository.getCoDetectionCounts();

        expect(counts['$nodeA-$nodeB'], equals(2));
      },
    );

    test(
      'cuenta pares correctamente con 3 nodos compartiendo sesiones',
      () async {
        final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

        final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

        final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

        final s1 = await insertSession();

        await insertSessionNode(s1, nodeA);

        await insertSessionNode(s1, nodeB);

        await insertSessionNode(s1, nodeC);

        final s2 = await insertSession();

        await insertSessionNode(s2, nodeA);

        await insertSessionNode(s2, nodeB);

        final counts = await repository.getCoDetectionCounts();

        expect(counts['$nodeA-$nodeB'], equals(2));

        expect(counts['$nodeA-$nodeC'], equals(1));

        expect(counts['$nodeB-$nodeC'], equals(1));

        expect(counts.containsKey('$nodeB-$nodeA'), isFalse);

        expect(counts.containsKey('$nodeC-$nodeB'), isFalse);
      },
    );
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Legacy co-detection
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('T2.2: buildGraph con co-detection edges reales (legacy)', () {
    test('sin co-detecciones → sin aristas en el layout (legacy)', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      await insertSessionNode(session, nodeB);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      final layout = await repository.buildGraphCoDetection(session);

      expect(layout.nodes.length, equals(2));

      expect(layout.edges.length, equals(1));

      expect(layout.edges.first.fromId, anyOf(nodeA, nodeB));

      expect(layout.edges.first.toId, anyOf(nodeA, nodeB));

      expect(layout.edges.first.fromId, isNot(equals(layout.edges.first.toId)));
    });

    test(
      'múltiples co-detecciones → todas las aristas entre pares (legacy)',
      () async {
        final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

        final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

        final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

        final s1 = await insertSession();

        await insertSessionNode(s1, nodeA);

        await insertSessionNode(s1, nodeB);

        await insertSessionNode(s1, nodeC);

        final s2 = await insertSession();

        await insertSessionNode(s2, nodeA);

        await insertSessionNode(s2, nodeB);

        mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

        mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

        mockNodeLookup(nodeC, 'AA:BB:CC:DD:EE:03', 'Node C');

        final layout = await repository.buildGraphCoDetection(s1);

        expect(layout.nodes.length, equals(3));

        expect(layout.edges.length, equals(3));

        final edgeAB = layout.edges.firstWhere(
          (edge) =>
              (edge.fromId == nodeA && edge.toId == nodeB) ||
              (edge.fromId == nodeB && edge.toId == nodeA),
          orElse: () => throw StateError('Arco A-B no encontrado'),
        );

        expect(edgeAB.thickness, equals(2.0));
      },
    );

    test('nodo detectado solo → sin aristas (legacy)', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      final layout = await repository.buildGraphCoDetection(session);

      expect(layout.nodes.length, equals(1));

      expect(layout.edges, isEmpty);
    });
  });

  group('T2.2: connectionCount en buildGraph (legacy)', () {
    test('nodo aislado tiene connectionCount=0', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      final layout = await repository.buildGraphCoDetection(session);

      expect(layout.nodes.length, equals(1));

      expect(layout.nodes.first.connectionCount, equals(0));
    });

    test('nodo con 1 arista tiene connectionCount=1', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      await insertSessionNode(session, nodeB);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      final layout = await repository.buildGraphCoDetection(session);

      for (final node in layout.nodes) {
        expect(node.connectionCount, equals(1));
      }
    });

    test(
      'nodo central entre dos tiene connectionCount=1 dentro de la sesión activa',
      () async {
        final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

        final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

        final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

        final s1 = await insertSession();

        await insertSessionNode(s1, nodeA);

        await insertSessionNode(s1, nodeB);

        final s2 = await insertSession();

        await insertSessionNode(s2, nodeB);

        await insertSessionNode(s2, nodeC);

        mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

        mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

        final layout = await repository.buildGraphCoDetection(s1);

        expect(layout.nodes.length, equals(2));

        final nodeAInGraph = layout.nodes.firstWhere(
          (node) => node.id == nodeA,
        );

        final nodeBInGraph = layout.nodes.firstWhere(
          (node) => node.id == nodeB,
        );

        expect(nodeAInGraph.connectionCount, equals(1));

        expect(nodeBInGraph.connectionCount, equals(1));
      },
    );

    test('tres nodos en clique → cada uno connectionCount=2', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

      final s1 = await insertSession();

      await insertSessionNode(s1, nodeA);

      await insertSessionNode(s1, nodeB);

      await insertSessionNode(s1, nodeC);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      mockNodeLookup(nodeC, 'AA:BB:CC:DD:EE:03', 'Node C');

      final layout = await repository.buildGraphCoDetection(s1);

      for (final node in layout.nodes) {
        expect(node.connectionCount, equals(2));
      }
    });
  });

  group('T2.3: Edge thickness from co-detection count (legacy)', () {
    test('thicknessFromCount devuelve 1.0 para 1 co-detección', () {
      expect(GraphEdge.thicknessFromCount(1), equals(1.0));
    });

    test('thicknessFromCount devuelve 2.0 para 2-3 co-detecciones', () {
      expect(GraphEdge.thicknessFromCount(2), equals(2.0));

      expect(GraphEdge.thicknessFromCount(3), equals(2.0));
    });

    test('thicknessFromCount devuelve 3.0 para 4+ co-detecciones', () {
      expect(GraphEdge.thicknessFromCount(4), equals(3.0));

      expect(GraphEdge.thicknessFromCount(10), equals(3.0));
    });

    test('thicknessFromCount para casos borde: 0', () {
      expect(GraphEdge.thicknessFromCount(0), equals(1.0));
    });

    test(
      'arista en buildGraph usa thicknessFromCount con conteo real',
      () async {
        final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

        final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

        final s1 = await insertSession();

        await insertSessionNode(s1, nodeA);

        await insertSessionNode(s1, nodeB);

        final s2 = await insertSession();

        await insertSessionNode(s2, nodeA);

        await insertSessionNode(s2, nodeB);

        final s3 = await insertSession();

        await insertSessionNode(s3, nodeA);

        await insertSessionNode(s3, nodeB);

        mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

        mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

        final layout = await repository.buildGraphCoDetection(s1);

        expect(layout.edges.length, equals(1));

        expect(layout.edges.first.thickness, equals(2.0));
      },
    );

    test(
      'PR6b: propaga Node.connectable=false a GraphNode en legacy',
      () async {
        final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

        final session = await insertSession();

        await insertSessionNode(session, nodeA);

        when(mockNodeRepository.getNodeById(nodeA)).thenAnswer(
          (_) async => Node(
            id: nodeA,
            bleAddress: 'AA:BB:CC:DD:EE:01',
            name: 'Node A',
            firstSeen: DateTime(2026, 6, 1),
            lastSeen: DateTime(2026, 6, 19),
            rssiHistory: const [-60],
            connectable: false,
          ),
        );

        final layout = await repository.buildGraphCoDetection(session);

        expect(layout.nodes, hasLength(1));

        expect(layout.nodes.first.connectable, isFalse);
      },
    );

    test('PR6b: propaga Node.connectable=true a GraphNode en legacy', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      when(mockNodeRepository.getNodeById(nodeA)).thenAnswer(
        (_) async => Node(
          id: nodeA,
          bleAddress: 'AA:BB:CC:DD:EE:01',
          name: 'Node A',
          firstSeen: DateTime(2026, 6, 1),
          lastSeen: DateTime(2026, 6, 19),
          rssiHistory: const [-60],
          connectable: true,
        ),
      );

      final layout = await repository.buildGraphCoDetection(session);

      expect(layout.nodes, hasLength(1));

      expect(layout.nodes.first.connectable, isTrue);
    });
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // ARCH-001 — persistent self-node
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('ARCH-001: persistent self-node en buildGraph', () {
    test('sin self persistente, ningún nodo externo se marca isSelf', () async {
      when(mockNodeRepository.getSelfNode()).thenAnswer((_) async => null);

      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      final layout = await repository.buildGraph(session);

      expect(layout.nodes, hasLength(1));

      expect(layout.nodes.single.isSelf, isFalse);
    });

    test(
      'self persistente se agrega con ID real aunque no esté en la sesión',
      () async {
        final self = makePersistentSelf();

        when(mockNodeRepository.getSelfNode()).thenAnswer((_) async => self);

        final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

        final session = await insertSession();

        await insertSessionNode(session, nodeA);

        mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

        final layout = await repository.buildGraph(session);

        expect(layout.nodes, hasLength(2));

        final graphSelf = layout.nodes.firstWhere((node) => node.id == self.id);

        expect(graphSelf.id, 99);

        expect(graphSelf.id, isNot(-1));

        expect(graphSelf.isSelf, isTrue);

        expect(graphSelf.name, 'Mi dispositivo');

        final external = layout.nodes.firstWhere((node) => node.id == nodeA);

        expect(external.isSelf, isFalse);
      },
    );

    test('myDeviceUuid ya no convierte un nodo externo en self', () async {
      when(mockNodeRepository.getSelfNode()).thenAnswer((_) async => null);

      const uuid = '550e8400-e29b-41d4-a716-446655440000';

      final nodeA = await insertNode(uuid, 'Nodo externo');

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      mockNodeLookup(nodeA, uuid, 'Nodo externo');

      final layout = await repository.buildGraph(session, myDeviceUuid: uuid);

      final graphNode = layout.nodes.firstWhere((node) => node.id == nodeA);

      expect(
        graphNode.isSelf,
        isFalse,
        reason:
            'ARCH-001: isSelf debe provenir del Node persistente, no de comparar bleAddress con UUID',
      );
    });

    test('existe como máximo un self-node visible', () async {
      final self = makePersistentSelf(id: 50);

      when(mockNodeRepository.getSelfNode()).thenAnswer((_) async => self);

      final externalA = await insertNode('AA:01', 'A');

      final externalB = await insertNode('AA:02', 'B');

      final session = await insertSession();

      await insertSessionNode(session, externalA);

      await insertSessionNode(session, externalB);

      mockNodeLookup(externalA, 'AA:01', 'A');

      mockNodeLookup(externalB, 'AA:02', 'B');

      final layout = await repository.buildGraph(session);

      final selfNodes = layout.nodes.where((node) => node.isSelf).toList();

      expect(selfNodes, hasLength(1));

      expect(selfNodes.single.id, self.id);
    });
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // PR2 — connections
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('PR2 T2.3: buildGraph con connections', () {
    setUp(() {
      when(mockNodeRepository.getSelfNode()).thenAnswer((_) async => null);
    });

    test('buildGraph usa tabla connections en vez de co-detección', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      await insertConnection(nodeA, nodeB);

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      await insertSessionNode(session, nodeB);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      final layout = await repository.buildGraph(session);

      expect(layout.nodes.length, equals(2));

      expect(layout.edges.length, equals(1));

      expect(layout.edges.first.edgeType, equals(EdgeType.direct));
    });

    test('sin conexiones en tabla → sin aristas en el layout', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      await insertSessionNode(session, nodeB);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      final layout = await repository.buildGraph(session);

      expect(layout.nodes.length, equals(2));

      expect(layout.edges, isEmpty);
    });

    test('arista transitiva: A→B + B→C ⇒ A—C dashed', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

      await insertConnection(nodeA, nodeB);

      await insertConnection(nodeB, nodeC);

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      await insertSessionNode(session, nodeB);

      await insertSessionNode(session, nodeC);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      mockNodeLookup(nodeC, 'AA:BB:CC:DD:EE:03', 'Node C');

      final layout = await repository.buildGraph(session);

      expect(layout.nodes.length, equals(3));

      expect(layout.edges.length, equals(3));

      final transitiveEdge = layout.edges.firstWhere(
        (edge) =>
            (edge.fromId == nodeA && edge.toId == nodeC) ||
            (edge.fromId == nodeC && edge.toId == nodeA),
        orElse: () => throw StateError('Arista transitiva A-C no encontrada'),
      );

      expect(transitiveEdge.edgeType, equals(EdgeType.transitive));

      final directAB = layout.edges.firstWhere(
        (edge) =>
            (edge.fromId == nodeA && edge.toId == nodeB) ||
            (edge.fromId == nodeB && edge.toId == nodeA),
      );

      final directBC = layout.edges.firstWhere(
        (edge) =>
            (edge.fromId == nodeB && edge.toId == nodeC) ||
            (edge.fromId == nodeC && edge.toId == nodeB),
      );

      expect(directAB.edgeType, equals(EdgeType.direct));

      expect(directBC.edgeType, equals(EdgeType.direct));
    });

    test('no genera arista transitiva cuando no hay 1-hop', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

      await insertConnection(nodeA, nodeB);

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      await insertSessionNode(session, nodeB);

      await insertSessionNode(session, nodeC);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      mockNodeLookup(nodeC, 'AA:BB:CC:DD:EE:03', 'Node C');

      final layout = await repository.buildGraph(session);

      expect(layout.nodes.length, equals(3));

      expect(layout.edges.length, equals(1));

      expect(layout.edges.first.edgeType, equals(EdgeType.direct));
    });

    test('getEdges también usa connections en vez de co-detección', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      await insertConnection(nodeA, nodeB);

      final session = await insertSession();

      await insertSessionNode(session, nodeA);

      await insertSessionNode(session, nodeB);

      final edges = await repository.getEdges(session);

      expect(edges.length, equals(1));

      expect(edges.first.edgeType, equals(EdgeType.direct));
    });

    test(
      'ARCH-001: conexión self-remoto se renderiza aunque self no esté en scan_session_nodes',
      () async {
        final now = DateTime(2026, 6, 19);

        final selfId = await db
            .into(db.nodes)
            .insert(
              NodesCompanion(
                deviceUuid: const Value('local-installation-uuid'),
                bleAddress: const Value(null),
                isSelf: const Value(true),
                name: const Value('Mi dispositivo'),
                color: const Value('#2196F3'),
                firstSeen: Value(now),
                lastSeen: Value(now),
                connectable: const Value(false),
              ),
            );

        final remoteId = await insertNode('AA:BB:CC:DD:EE:99', 'Reloj');

        final session = await insertSession();

        await insertSessionNode(session, remoteId);

        when(mockNodeRepository.getSelfNode()).thenAnswer(
          (_) async => Node(
            id: selfId,
            deviceUuid: 'local-installation-uuid',
            bleAddress: null,
            isSelf: true,
            name: 'Mi dispositivo',
            color: '#2196F3',
            firstSeen: now,
            lastSeen: now,
            deviceType: 'android',
            connectable: false,
            estimatedDistance: 0.0,
          ),
        );

        when(mockNodeRepository.getNodeById(remoteId)).thenAnswer(
          (_) async => Node(
            id: remoteId,
            bleAddress: 'AA:BB:CC:DD:EE:99',
            isSelf: false,
            name: 'Reloj',
            firstSeen: now,
            lastSeen: now,
            rssiHistory: const [-50],
            connectable: true,
          ),
        );

        await db
            .into(db.connections)
            .insert(
              ConnectionsCompanion.insert(
                fromNodeId: selfId,
                toNodeId: remoteId,
                createdAt: now,
              ),
            );

        final layout = await repository.buildGraph(session);

        expect(layout.nodes, hasLength(2));

        final selfGraphNode = layout.nodes.firstWhere(
          (node) => node.id == selfId,
        );

        final remoteGraphNode = layout.nodes.firstWhere(
          (node) => node.id == remoteId,
        );

        expect(selfGraphNode.isSelf, isTrue);

        expect(remoteGraphNode.isSelf, isFalse);

        expect(layout.edges, hasLength(1));

        final edge = layout.edges.single;

        expect(edge.fromId, selfId);

        expect(edge.toId, remoteId);

        expect(edge.edgeType, EdgeType.direct);
      },
    );
  });
}
