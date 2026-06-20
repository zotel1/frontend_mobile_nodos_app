import 'package:drift/drift.dart' hide Column;
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
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

  // ── Helpers ──

  /// Inserta un nodo en la tabla nodes.
  Future<int> insertNode(String address, [String name = 'Desconocido']) async {
    return db.into(db.nodes).insert(
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

  /// Inserta una sesión de escaneo.
  Future<int> insertSession() async {
    return db.into(db.scanSessions).insert(
          ScanSessionsCompanion.insert(
            startedAt: DateTime(2026, 6, 19),
            nodesDetected: 0,
          ),
        );
  }

  /// Inserta un registro en scan_session_nodes.
  Future<void> insertSessionNode(int sessionId, int nodeId,
      [int rssi = -60]) async {
    await db.into(db.scanSessionNodes).insert(
          ScanSessionNodesCompanion.insert(
            sessionId: sessionId,
            nodeId: nodeId,
            rssi: rssi,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T2.1 — Co-deteccion counting query
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

    test('cuenta una co-detección para un par en una sesión compartida',
        () async {
      final session = await insertSession();
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');
      await insertSessionNode(session, nodeA);
      await insertSessionNode(session, nodeB);

      final counts = await repository.getCoDetectionCounts();

      // El par (nodeA, nodeB) debe tener count=1
      final keyA = '$nodeA-$nodeB';
      final keyB = '$nodeB-$nodeA'; // no debería existir
      expect(counts[keyA], equals(1));
      expect(counts.containsKey(keyB), isFalse);
    });

    test('cuenta múltiples co-detecciones entre dos nodos en varias sesiones',
        () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      // Sesión 1: ambos nodos juntos
      final s1 = await insertSession();
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);

      // Sesión 2: ambos nodos juntos nuevamente
      final s2 = await insertSession();
      await insertSessionNode(s2, nodeA);
      await insertSessionNode(s2, nodeB);

      // Sesión 3: solo nodeA
      final s3 = await insertSession();
      await insertSessionNode(s3, nodeA);

      final counts = await repository.getCoDetectionCounts();

      final key = '$nodeA-$nodeB';
      expect(counts[key], equals(2));
    });

    test('cuenta pares correctamente con 3 nodos compartiendo sesiones',
        () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');
      final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

      // Sesión: A, B, C juntos
      final s1 = await insertSession();
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);
      await insertSessionNode(s1, nodeC);

      // Otra sesión: solo A y B
      final s2 = await insertSession();
      await insertSessionNode(s2, nodeA);
      await insertSessionNode(s2, nodeB);

      final counts = await repository.getCoDetectionCounts();

      // A-B: 2 co-detecciones (s1 + s2)
      expect(counts['$nodeA-$nodeB'], equals(2));
      // A-C: 1 co-detección (s1)
      expect(counts['$nodeA-$nodeC'], equals(1));
      // B-C: 1 co-detección (s1)
      expect(counts['$nodeB-$nodeC'], equals(1));
      // Pares invertidos no deben existir
      expect(counts.containsKey('$nodeB-$nodeA'), isFalse);
      expect(counts.containsKey('$nodeC-$nodeB'), isFalse);
    });
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T2.2 — Reemplazar clique edges con co-detection edges reales
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('T2.2: buildGraph con co-detection edges reales (legacy)', () {
    /// Helper para mockear NodeRepository.getNodeById
    void mockNodeLookup(int id, String address, [String name = 'Desconocido']) {
      when(mockNodeRepository.getNodeById(id)).thenAnswer((_) async => Node(
            id: id,
            bleAddress: address,
            name: name,
            firstSeen: DateTime(2026, 6, 1),
            lastSeen: DateTime(2026, 6, 19),
            rssiHistory: const [-60],
          ));
    }

    test('sin co-detecciones → sin aristas en el layout (legacy)', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      // Sesión con ambos nodos: crea registros scan_session_nodes
      final session = await insertSession();
      await insertSessionNode(session, nodeA);
      await insertSessionNode(session, nodeB);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');
      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      final layout = await repository.buildGraphCoDetection(session);

      // Hay 2 nodos en la sesión y 1 co-detección → 2 nodos + 1 arista
      expect(layout.nodes.length, equals(2));
      expect(layout.edges.length, equals(1));
      expect(layout.edges.first.fromId, anyOf(nodeA, nodeB));
      expect(layout.edges.first.toId, anyOf(nodeA, nodeB));
      expect(layout.edges.first.fromId, isNot(equals(layout.edges.first.toId)));
    });

    test('múltiples co-detecciones → todas las aristas entre pares (legacy)',
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
        (e) => (e.fromId == nodeA && e.toId == nodeB) ||
            (e.fromId == nodeB && e.toId == nodeA),
        orElse: () => throw StateError('Arco A-B no encontrado'),
      );
      expect(edgeAB.thickness, equals(2.0));
    });

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

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T2.2 — Computar connectionCount durante buildGraph
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('T2.2: connectionCount en buildGraph (legacy)', () {
    /// Helper para mockear NodeRepository.getNodeById
    void mockNodeLookup(int id, String address, [String name = 'Desconocido']) {
      when(mockNodeRepository.getNodeById(id)).thenAnswer((_) async => Node(
            id: id,
            bleAddress: address,
            name: name,
            firstSeen: DateTime(2026, 6, 1),
            lastSeen: DateTime(2026, 6, 19),
            rssiHistory: const [-60],
          ));
    }

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

      // Ambos nodos deben tener connectionCount=1 (1 arista entre ellos)
      for (final node in layout.nodes) {
        expect(node.connectionCount, equals(1));
      }
    });

    test('nodo central entre dos tiene connectionCount=2', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');
      final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

      // Dos sesiones: (A,B) y (B,C). B es el nodo central.
      final s1 = await insertSession();
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);

      final s2 = await insertSession();
      await insertSessionNode(s2, nodeB);
      await insertSessionNode(s2, nodeC);

      // Para s1: A y B aparecen. A tiene 1 conexión (A-B), B tiene 1 (A-B).
      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');
      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      final layout = await repository.buildGraphCoDetection(s1);

      expect(layout.nodes.length, equals(2));
      final nodeAInGraph =
          layout.nodes.firstWhere((n) => n.id == nodeA);
      final nodeBInGraph =
          layout.nodes.firstWhere((n) => n.id == nodeB);
      expect(nodeAInGraph.connectionCount, equals(1));
      expect(nodeBInGraph.connectionCount, equals(1));
    });

    test('tres nodos en clique → cada uno connectionCount=2', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');
      final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

      // Sesión con los 3 juntos
      final s1 = await insertSession();
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);
      await insertSessionNode(s1, nodeC);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');
      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');
      mockNodeLookup(nodeC, 'AA:BB:CC:DD:EE:03', 'Node C');

      final layout = await repository.buildGraphCoDetection(s1);

      // 3 nodos, 3 aristas (A-B, A-C, B-C). Cada nodo en 2 aristas.
      for (final node in layout.nodes) {
        expect(node.connectionCount, equals(2));
      }
    });
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T2.3 — Grosor de arista desde co-detecciones
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('T2.3: Edge thickness from co-detection count (legacy)', () {
    // thicknessFromCount ya existe en GraphEdge, verificamos que se use
    // correctamente al construir aristas en buildGraph.

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
      // Si count es 0, debería devolver el mínimo (1.0)
      expect(GraphEdge.thicknessFromCount(0), equals(1.0));
    });

    test('arista en buildGraph usa thicknessFromCount con conteo real',
        () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      // 3 sesiones con ambos nodos → 3 co-detecciones
      final s1 = await insertSession();
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);

      final s2 = await insertSession();
      await insertSessionNode(s2, nodeA);
      await insertSessionNode(s2, nodeB);

      final s3 = await insertSession();
      await insertSessionNode(s3, nodeA);
      await insertSessionNode(s3, nodeB);

      when(mockNodeRepository.getNodeById(nodeA)).thenAnswer((_) async => Node(
            id: nodeA,
            bleAddress: 'AA:BB:CC:DD:EE:01',
            name: 'Node A',
            firstSeen: DateTime(2026, 6, 1),
            lastSeen: DateTime(2026, 6, 19),
            rssiHistory: const [-60],
          ));
      when(mockNodeRepository.getNodeById(nodeB)).thenAnswer((_) async => Node(
            id: nodeB,
            bleAddress: 'AA:BB:CC:DD:EE:02',
            name: 'Node B',
            firstSeen: DateTime(2026, 6, 1),
            lastSeen: DateTime(2026, 6, 19),
            rssiHistory: const [-60],
          ));

      final layout = await repository.buildGraphCoDetection(s1);

      expect(layout.edges.length, equals(1));
      // 3 co-detecciones → grosor debe ser 2.0
      expect(layout.edges.first.thickness, equals(2.0));
    });
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T2.3 — Identificar nodo propio por UUID (isSelf)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('T2.3: isSelf marking en buildGraph', () {
    void mockNodeWithAddress(int id, String address, [String name = 'Desconocido']) {
      when(mockNodeRepository.getNodeById(id)).thenAnswer((_) async => Node(
            id: id,
            bleAddress: address,
            name: name,
            firstSeen: DateTime(2026, 6, 1),
            lastSeen: DateTime(2026, 6, 19),
            rssiHistory: const [-60],
          ));
    }

    test('ningún nodo es self cuando myDeviceUuid es null', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final session = await insertSession();
      await insertSessionNode(session, nodeA);
      mockNodeWithAddress(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      final layout = await repository.buildGraph(session);
      // Sin myDeviceUuid, ningún nodo debe ser self
      for (final node in layout.nodes) {
        expect(node.isSelf, isFalse);
      }
    });

    test('ningún nodo es self cuando myDeviceUuid no coincide', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');
      final session = await insertSession();
      await insertSessionNode(session, nodeA);
      await insertSessionNode(session, nodeB);
      mockNodeWithAddress(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');
      mockNodeWithAddress(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      final layout = await repository.buildGraph(session,
          myDeviceUuid: 'completely-different-uuid');

      for (final node in layout.nodes) {
        expect(node.isSelf, isFalse);
      }
    });

    test('nodo con bleAddress igual a myDeviceUuid se marca isSelf=true',
        () async {
      const myUuid = '550e8400-e29b-41d4-a716-446655440000';
      final nodeA = await insertNode(myUuid, 'Mi Dispositivo');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');
      final session = await insertSession();
      await insertSessionNode(session, nodeA);
      await insertSessionNode(session, nodeB);
      mockNodeWithAddress(nodeA, myUuid, 'Mi Dispositivo');
      mockNodeWithAddress(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      final layout =
          await repository.buildGraph(session, myDeviceUuid: myUuid);

      final selfNode = layout.nodes.firstWhere((n) => n.id == nodeA);
      final otherNode = layout.nodes.firstWhere((n) => n.id == nodeB);
      expect(selfNode.isSelf, isTrue);
      expect(otherNode.isSelf, isFalse);
    });

    test('isSelf solo se marca en el nodo cuyo bleAddress coincide', () async {
      const myUuid = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode(myUuid, 'Self Node');
      final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

      final s1 = await insertSession();
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);
      await insertSessionNode(s1, nodeC);

      mockNodeWithAddress(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');
      mockNodeWithAddress(nodeB, myUuid, 'Self Node');
      mockNodeWithAddress(nodeC, 'AA:BB:CC:DD:EE:03', 'Node C');

      final layout =
          await repository.buildGraph(s1, myDeviceUuid: myUuid);

      // Solo nodeB debe ser self
      expect(
          layout.nodes.firstWhere((n) => n.id == nodeA).isSelf, isFalse);
      expect(
          layout.nodes.firstWhere((n) => n.id == nodeB).isSelf, isTrue);
      expect(
          layout.nodes.firstWhere((n) => n.id == nodeC).isSelf, isFalse);
    });
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // PR2 T2.3: buildGraph con tabla connections + aristas transitivas
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // QUÉ: el nuevo buildGraph deriva aristas desde la tabla connections
  // (ya no desde co-detecciones en scan_session_nodes).
  // Además, _getTransitiveEdges() infiere aristas 1-hop (A→B, B→C ⇒ A—C)
  // marcadas con EdgeType.transitive.

  group('PR2 T2.3: buildGraph con connections', () {
    /// Helper para insertar una conexión directa en la tabla connections.
    Future<void> insertConnection(int fromId, int toId) async {
      await db.into(db.connections).insert(
            ConnectionsCompanion.insert(
              fromNodeId: fromId,
              toNodeId: toId,
              createdAt: DateTime(2026, 6, 19),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }

    void mockNodeLookup(int id, String address, [String name = 'Desconocido']) {
      when(mockNodeRepository.getNodeById(id)).thenAnswer((_) async => Node(
            id: id,
            bleAddress: address,
            name: name,
            firstSeen: DateTime(2026, 6, 1),
            lastSeen: DateTime(2026, 6, 19),
            rssiHistory: const [-60],
          ));
    }

    test('buildGraph usa tabla connections en vez de co-detección', () async {
      // Arrange: dos nodos conectados vía connections, sin registros en
      // scan_session_nodes para esos nodos.
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');
      await insertConnection(nodeA, nodeB);

      // Crear una sesión con ambos nodos (para que buildGraph los encuentre)
      final session = await insertSession();
      await insertSessionNode(session, nodeA);
      await insertSessionNode(session, nodeB);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');
      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      // Act
      final layout = await repository.buildGraph(session);

      // Assert: debe haber 2 nodos y 1 arista directa (desde connections)
      expect(layout.nodes.length, equals(2));
      expect(layout.edges.length, equals(1));
      expect(layout.edges.first.edgeType, equals(EdgeType.direct));
    });

    test('sin conexiones en tabla → sin aristas en el layout', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      // Ambos en la misma sesión pero SIN registro en connections
      final session = await insertSession();
      await insertSessionNode(session, nodeA);
      await insertSessionNode(session, nodeB);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');
      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      final layout = await repository.buildGraph(session);

      expect(layout.nodes.length, equals(2));
      // Sin conexiones → sin aristas (a diferencia del viejo buildGraph
      // que usaba co-detección de scan_session_nodes)
      expect(layout.edges, isEmpty);
    });

    test('arista transitiva: A→B + B→C ⇒ A—C dashed', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');
      final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

      // Conexiones: A→B, B→C (NO A→C directamente)
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

      // 3 nodos, 3 aristas: 2 directas (A-B, B-C) + 1 transitiva (A-C)
      expect(layout.nodes.length, equals(3));
      expect(layout.edges.length, equals(3));

      // La arista A-C debe ser transitiva
      final transitiveEdge = layout.edges.firstWhere(
        (e) => (e.fromId == nodeA && e.toId == nodeC) ||
                (e.fromId == nodeC && e.toId == nodeA),
        orElse: () => throw StateError('Arista transitiva A-C no encontrada'),
      );
      expect(transitiveEdge.edgeType, equals(EdgeType.transitive));

      // Las aristas directas deben ser direct
      final directAB = layout.edges.firstWhere(
        (e) => (e.fromId == nodeA && e.toId == nodeB) ||
                (e.fromId == nodeB && e.toId == nodeA),
      );
      final directBC = layout.edges.firstWhere(
        (e) => (e.fromId == nodeB && e.toId == nodeC) ||
                (e.fromId == nodeC && e.toId == nodeB),
      );
      expect(directAB.edgeType, equals(EdgeType.direct));
      expect(directBC.edgeType, equals(EdgeType.direct));
    });

    test('no genera arista transitiva cuando no hay 1-hop', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');
      final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

      // Solo una conexión: A→B (C está aislado)
      await insertConnection(nodeA, nodeB);

      final session = await insertSession();
      await insertSessionNode(session, nodeA);
      await insertSessionNode(session, nodeB);
      await insertSessionNode(session, nodeC);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');
      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');
      mockNodeLookup(nodeC, 'AA:BB:CC:DD:EE:03', 'Node C');

      final layout = await repository.buildGraph(session);

      // 3 nodos, solo 1 arista directa (A-B). Sin aristas transitivas.
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
  });
}
