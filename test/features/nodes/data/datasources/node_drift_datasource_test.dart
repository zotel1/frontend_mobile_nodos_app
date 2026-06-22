import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

void main() {
  late AppDatabase database;
  late NodeLocalDataSource dataSource;

  final now = DateTime(2026, 6, 18, 12, 0, 0);

  setUp(() async {
    database = AppDatabase.inMemory();
    dataSource = NodeDriftDataSource(database);
  });

  tearDown(() async {
    await database.close();
  });

  Node createNode({
    int? id,
    String bleAddress = 'AA:BB:CC:DD:EE:FF',
    String? name,
    String? color,
    List<int> rssiHistory = const [-55, -60],
  }) {
    return Node(
      id: id,
      bleAddress: bleAddress,
      name: name,
      color: color,
      firstSeen: now,
      lastSeen: now,
      rssiHistory: rssiHistory,
    );
  }

  group('NodeDriftDataSource', () {
    test('implements NodeLocalDataSource', () {
      expect(dataSource, isA<NodeLocalDataSource>());
    });

    test('upsertNode inserts a new node and it becomes queryable', () async {
      final node = createNode();

      await dataSource.upsertNode(node);

      final retrieved = await dataSource.getNodeById(1); // auto-increment
      expect(retrieved, isNotNull);
      expect(retrieved!.bleAddress, 'AA:BB:CC:DD:EE:FF');
      expect(retrieved.rssiHistory, [-55, -60]);
    });

    test('upsertNode updates existing node by bleAddress', () async {
      final node = createNode(bleAddress: 'AA:BB:CC:DD:EE:FF', rssiHistory: [-50]);
      await dataSource.upsertNode(node);

      // Update the same node (same bleAddress, new rssiHistory)
      final updated = createNode(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Nodo Uno',
        color: '#FF0000',
        rssiHistory: [-50, -70],
      );
      await dataSource.upsertNode(updated);

      final retrieved = await dataSource.getNodeById(1);
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Nodo Uno');
      expect(retrieved.color, '#FF0000');
      expect(retrieved.rssiHistory, [-50, -70]);
    });

    test('getNodeById returns null for non-existent id', () async {
      final result = await dataSource.getNodeById(999);
      expect(result, isNull);
    });

    test('deleteNode removes the node', () async {
      final node = createNode();
      await dataSource.upsertNode(node);

      // Verify it exists
      expect(await dataSource.getNodeById(1), isNotNull);

      await dataSource.deleteNode(1);

      expect(await dataSource.getNodeById(1), isNull);
    });

    test('deleteNode does not throw for non-existent id', () async {
      // Should complete without error
      await dataSource.deleteNode(999);
    });

    test('watchNodes emits initial empty list when no nodes exist', () async {
      final emitted = <List<Node>>[];
      final sub = dataSource.watchNodes().listen(emitted.add);

      // Allow stream to emit
      await Future.delayed(const Duration(milliseconds: 100));

      expect(emitted.isNotEmpty, isTrue);
      expect(emitted.first, isEmpty);

      await sub.cancel();
    });

    test('watchNodes emits updated list after upsert', () async {
      final emitted = <List<Node>>[];
      final sub = dataSource.watchNodes().listen(emitted.add);

      // Give initial empty emission time
      await Future.delayed(const Duration(milliseconds: 100));

      await dataSource.upsertNode(createNode(bleAddress: 'AA:BB'));

      await Future.delayed(const Duration(milliseconds: 100));

      // Should have at least one emission with the new node
      final lastEmission = emitted.last;
      expect(lastEmission.length, 1);
      expect(lastEmission.first.bleAddress, 'AA:BB');

      await sub.cancel();
    });

    test('updating a node emits new list via watchNodes', () async {
      final emitted = <List<Node>>[];
      final sub = dataSource.watchNodes().listen(emitted.add);

      await Future.delayed(const Duration(milliseconds: 100));

      // Insert
      await dataSource.upsertNode(createNode(
        bleAddress: 'AA:BB',
        name: 'Original',
        rssiHistory: [-60],
      ));
      await Future.delayed(const Duration(milliseconds: 100));

      // Update
      await dataSource.upsertNode(createNode(
        id: 1,
        bleAddress: 'AA:BB',
        name: 'Updated',
        rssiHistory: [-60, -55],
      ));
      await Future.delayed(const Duration(milliseconds: 100));

      final lastEmission = emitted.last;
      expect(lastEmission.length, 1);
      expect(lastEmission.first.name, 'Updated');
      expect(lastEmission.first.rssiHistory, [-60, -55]);

      await sub.cancel();
    });

    test('rssiHistory is persisted as JSON and restored correctly', () async {
      final history = [-75, -80, -55, -45];
      final node = createNode(rssiHistory: history);

      await dataSource.upsertNode(node);

      final retrieved = await dataSource.getNodeById(1);
      expect(retrieved!.rssiHistory, history);
    });

    // ──────────────────────────────────────────────────────────
    // T-PR2-007 RED: jsonDecode seguro — JSON corrupto no crashea
    //
    // QUÉ: cuando la columna rssiHistory contiene JSON corrupto o
    // inválido, la operación jsonDecode no debe lanzar FormatException
    // que crashee la app. Debe retornar lista vacía [].
    //
    // POR QUÉ problema existe: el código actual usa jsonDecode sin
    // try-catch. Si un bug o migración corrupta escribe JSON inválido
    // en rssiHistory, la app crashea al leer el nodo.
    //
    // Estado RED esperado: el test falla porque jsonDecode lanza
    // FormatException al encontrar JSON corrupto.
    // ──────────────────────────────────────────────────────────
    test(
        'T-PR2-007 RED: rssiHistory con JSON corrupto retorna lista vacía sin crashear',
        () async {
      final now = DateTime(2026, 6, 18, 12, 0, 0);

      // Insertar un nodo directamente en la BD con JSON corrupto
      await database.into(database.nodes).insert(
            NodesCompanion(
              bleAddress: const Value('CC:DD:EE:FF:00:11'),
              firstSeen: Value(now),
              lastSeen: Value(now),
              rssiHistory: const Value('esto-no-es-json'),
            ),
          );

      // Leer el nodo a través del data source — no debe crashear
      final node = await dataSource.getNodeById(1);

      // Debe existir pero con rssiHistory vacío
      expect(node, isNotNull);
      expect(node!.rssiHistory, isEmpty,
          reason: 'JSON corrupto debe producir lista vacía, no crash');
    });
  });
}
