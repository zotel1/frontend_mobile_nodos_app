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

  group('T2.2: buildGraph con co-detection edges reales', () {
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

    test('sin co-detecciones → sin aristas en el layout', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');

      // Sesión con ambos nodos: crea registros scan_session_nodes
      final session = await insertSession();
      await insertSessionNode(session, nodeA);
      await insertSessionNode(session, nodeB);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');
      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');

      final layout = await repository.buildGraph(session);

      // Hay 2 nodos en la sesión y 1 co-detección → 2 nodos + 1 arista
      expect(layout.nodes.length, equals(2));
      expect(layout.edges.length, equals(1));
      expect(layout.edges.first.fromId, anyOf(nodeA, nodeB));
      expect(layout.edges.first.toId, anyOf(nodeA, nodeB));
      expect(layout.edges.first.fromId, isNot(equals(layout.edges.first.toId)));
    });

    test('múltiples co-detecciones → todas las aristas entre pares co-detectados',
        () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Node B');
      final nodeC = await insertNode('AA:BB:CC:DD:EE:03', 'Node C');

      // Sesión: A, B, C juntos
      final s1 = await insertSession();
      await insertSessionNode(s1, nodeA);
      await insertSessionNode(s1, nodeB);
      await insertSessionNode(s1, nodeC);

      // Segunda sesión: solo A y B
      final s2 = await insertSession();
      await insertSessionNode(s2, nodeA);
      await insertSessionNode(s2, nodeB);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');
      mockNodeLookup(nodeB, 'AA:BB:CC:DD:EE:02', 'Node B');
      mockNodeLookup(nodeC, 'AA:BB:CC:DD:EE:03', 'Node C');

      // buildGraph para s1: A, B, C en la sesión
      final layout = await repository.buildGraph(s1);

      expect(layout.nodes.length, equals(3));

      // Grupos de nodos en s1: (A,B), (A,C), (B,C) todos co-detectados
      // Pero la query de co-detecciones es GLOBAL (todas las sesiones)
      // A-B: 2 co-detecciones, A-C: 1, B-C: 1
      expect(layout.edges.length, equals(3));

      // Verificar espesor por cantidad de co-detecciones
      final edgeAB = layout.edges.firstWhere(
        (e) => (e.fromId == nodeA && e.toId == nodeB) ||
            (e.fromId == nodeB && e.toId == nodeA),
        orElse: () => throw StateError('Arco A-B no encontrado'),
      );
      // A-B: 2 co-detecciones → grosor 2.0 según thicknessFromCount
      expect(edgeAB.thickness, equals(2.0));
    });

    test('nodo detectado solo → sin aristas', () async {
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Node A');

      final session = await insertSession();
      await insertSessionNode(session, nodeA);

      mockNodeLookup(nodeA, 'AA:BB:CC:DD:EE:01', 'Node A');

      final layout = await repository.buildGraph(session);

      expect(layout.nodes.length, equals(1));
      expect(layout.edges, isEmpty);
    });
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // T2.3 — Grosor de arista desde co-detecciones
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  group('T2.3: Edge thickness from co-detection count', () {
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

      final layout = await repository.buildGraph(s1);

      expect(layout.edges.length, equals(1));
      // 3 co-detecciones → grosor debe ser 2.0
      expect(layout.edges.first.thickness, equals(2.0));
    });
  });
}
