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
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(emitted.isNotEmpty, isTrue);
      expect(emitted.first, isEmpty);

      await sub.cancel();
    });

    test('watchNodes emits updated list after upsert', () async {
      final emitted = <List<Node>>[];
      final sub = dataSource.watchNodes().listen(emitted.add);

      // Give initial empty emission time
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await dataSource.upsertNode(createNode(bleAddress: 'AA:BB'));

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Should have at least one emission with the new node
      final lastEmission = emitted.last;
      expect(lastEmission.length, 1);
      expect(lastEmission.first.bleAddress, 'AA:BB');

      await sub.cancel();
    });

    test('updating a node emits new list via watchNodes', () async {
      final emitted = <List<Node>>[];
      final sub = dataSource.watchNodes().listen(emitted.add);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Insert
      await dataSource.upsertNode(createNode(
        bleAddress: 'AA:BB',
        name: 'Original',
        rssiHistory: [-60],
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Update
      await dataSource.upsertNode(createNode(
        id: 1,
        bleAddress: 'AA:BB',
        name: 'Updated',
        rssiHistory: [-60, -55],
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));

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

    // ─── PR1.3: deleteAllNodes y getNodeByBleAddress ──────────
    // QUÉ: deleteAllNodes() elimina todas las filas de la tabla nodes.
    // getNodeByBleAddress() busca un nodo por su dirección BLE.
    // POR QUÉ: necesario para limpiar nodos al apagar Bluetooth
    // (R5.17) y para lookup de nodos por bleAddress en el flujo
    // de conexiones GATT (connections insert).

    test('deleteAllNodes elimina todas las filas de la tabla', () async {
      // Insertar 3 nodos distintos.
      await dataSource.upsertNode(createNode(
        bleAddress: 'AA:BB:CC:DD:EE:01',
        name: 'Nodo 1',
      ));
      await dataSource.upsertNode(createNode(
        bleAddress: 'AA:BB:CC:DD:EE:02',
        name: 'Nodo 2',
      ));
      await dataSource.upsertNode(createNode(
        bleAddress: 'AA:BB:CC:DD:EE:03',
        name: 'Nodo 3',
      ));

      // Verificar que los 3 existen.
      expect(await dataSource.getNodeById(1), isNotNull);
      expect(await dataSource.getNodeById(2), isNotNull);
      expect(await dataSource.getNodeById(3), isNotNull);

      // Eliminar todos.
      await dataSource.deleteAllNodes();

      // Verificar que ninguno existe.
      expect(await dataSource.getNodeById(1), isNull);
      expect(await dataSource.getNodeById(2), isNull);
      expect(await dataSource.getNodeById(3), isNull);
    });

    test('deleteAllNodes no lanza error si la tabla está vacía', () async {
      // No debe lanzar excepción.
      await dataSource.deleteAllNodes();
    });

    test('getNodeByBleAddress retorna el nodo correcto por bleAddress', () async {
      await dataSource.upsertNode(createNode(
        bleAddress: '11:22:33:44:55:66',
        name: 'Target',
      ));
      await dataSource.upsertNode(createNode(
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Other',
      ));

      final result = await dataSource.getNodeByBleAddress('11:22:33:44:55:66');
      expect(result, isNotNull);
      expect(result!.bleAddress, '11:22:33:44:55:66');
      expect(result.name, 'Target');
    });

    test('getNodeByBleAddress retorna null si no existe', () async {
      final result = await dataSource.getNodeByBleAddress('FF:EE:DD:CC:BB:AA');
      expect(result, isNull);
    });

    // ─── PR3: Mapper unificado _toCompanion(node, isInsert) ──────
    // QUÉ: verifica que el mapper unificado produce los Companions
    // correctos según el parámetro isInsert.
    // POR QUÉ: antes existían dos métodos separados (_toCompanion y
    // _toInsertCompanion) con lógica duplicada. El mapper unificado
    // reduce el código duplicado y centraliza la lógica de mapeo.

    test('mapper unificado con isInsert=false produce NodesCompanion normal', () async {
      // QUÉ: upsertNode usa el mapper con isInsert=false para el UPDATE.
      // El Companion resultante debe usar Values (no insert companion).
      final node = createNode(
        bleAddress: 'MA:PP:ER:IN:S0:01',
        name: 'MapperTest',
        color: '#ABC',
        rssiHistory: [-50],
      );

      await dataSource.upsertNode(node);

      // Update → verifica que el UPDATE funciona (usa mapper con isInsert=false)
      final updated = createNode(
        id: 1,
        bleAddress: 'MA:PP:ER:IN:S0:01',
        name: 'MapperUpdated',
        color: '#DEF',
        rssiHistory: [-50, -45],
      );
      await dataSource.upsertNode(updated);

      final retrieved = await dataSource.getNodeById(1);
      expect(retrieved!.name, 'MapperUpdated');
      expect(retrieved.color, '#DEF');
      expect(retrieved.rssiHistory, [-50, -45]);
    });

    test('mapper unificado con isInsert=true produce insert companion correcto', () async {
      // QUÉ: el primer upsertNode usa el mapper con isInsert=true.
      // El Companion debe ser un insertCompanion (sin id explícito,
      // auto-increment), que produzca una fila nueva.
      final node = createNode(
        bleAddress: 'MA:PP:ER:IN:S0:02',
        name: 'Fresh',
        rssiHistory: [-60],
      );

      await dataSource.upsertNode(node);

      final retrieved = await dataSource.getNodeById(1);
      expect(retrieved, isNotNull);
      expect(retrieved!.bleAddress, 'MA:PP:ER:IN:S0:02');
      expect(retrieved.name, 'Fresh');
      expect(retrieved.rssiHistory, [-60]);
      // connectable debe tener default false cuando no se especifica
      expect(retrieved.connectable, false);
    });

    test('mapper unificado preserva suggestedName en update (freeze on first detection)',
        () async {
      // QUÉ: verifica que el upsert (update path) preserva el
      // suggestedName de la primera detección.
      // POR QUÉ: el suggestedName se congela en la primera detección
      // para evitar que actualizaciones posteriores lo sobrescriban.
      final first = Node(
        bleAddress: 'FR:EE:ZE:NA:ME:01',
        name: 'Desconocido',
        firstSeen: now,
        lastSeen: now,
        rssiHistory: const [-70],
        suggestedName: 'Device-A',
      );

      await dataSource.upsertNode(first);

      // Segunda detección sin suggestedName
      final second = createNode(
        bleAddress: 'FR:EE:ZE:NA:ME:01',
        name: 'Desconocido',
        rssiHistory: [-70, -65],
      );

      await dataSource.upsertNode(second);

      final retrieved = await dataSource.getNodeById(1);
      // El suggestedName debería preservarse del primer insert
      expect(retrieved!.suggestedName, 'Device-A',
          reason: 'suggestedName debe congelarse en la primera detección');
    });
  });
}
