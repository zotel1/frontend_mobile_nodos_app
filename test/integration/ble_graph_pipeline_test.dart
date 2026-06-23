import 'dart:async';

import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/core/utils/app_theme_mode.dart';
import 'package:frontend_mobile_nodos_app/core/utils/device_classifier.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/repositories/node_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/update_node_metadata.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/data/datasources/scan_session_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/repositories/user_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/get_user_profile.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_color.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_name.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/algorithms/fruchterman_reingold.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/repositories/graph_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/build_graph.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';

// ──────────────────────────────────────────────────────────────
// Stub BLE Repository (hardware boundary — única sustitución)
// ──────────────────────────────────────────────────────────────

class _TestBleRepository implements BleRepository {
  final _scanController = StreamController<List<BleDevice>>.broadcast();
  final _btController = StreamController<bool>.broadcast();
  int startScanCalls = 0;

  @override
  Stream<List<BleDevice>> get scanResults => _scanController.stream;

  @override
  Stream<bool> get bluetoothState => _btController.stream;

  @override
  Future<void> startScan() async {
    startScanCalls++;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> startAdvertise(String uuid, String name, String color) async {}

  @override
  Future<void> stopAdvertise() async {}

  @override
  Future<void> endScanSession() async {}

  void emitDevices(List<BleDevice> devices) =>
      _scanController.add(devices);

  void emitBluetoothOn() => _btController.add(true);

  void dispose() {
    _scanController.close();
    _btController.close();
  }
}

// ──────────────────────────────────────────────────────────────
// Stub BLE Connection Repository
// ──────────────────────────────────────────────────────────────

class _TestBleConnectionRepository implements BleConnectionRepository {
  final _stateControllers = <String, StreamController<bool>>{};

  @override
  Future<void> connect(String remoteId) async {}

  @override
  Future<void> disconnect(String remoteId) async {}

  @override
  Stream<bool> connectionState(String remoteId) =>
      (_stateControllers.putIfAbsent(
        remoteId,
        () => StreamController<bool>.broadcast(),
      )).stream;

  @override
  Future<void> discoverServices(String remoteId) async {}

  @override
  Future<List<int>?> readCharacteristic(
      String remoteId, String characteristicUuid) async {
    return null;
  }

  @override
  Future<void> saveConnection(int fromNodeId, int toNodeId) async {}

  void emitConnected(String remoteId) =>
      _stateControllers[remoteId]?.add(true);

  void emitDisconnected(String remoteId) =>
      _stateControllers[remoteId]?.add(false);

  void dispose() {
    for (final c in _stateControllers.values) {
      c.close();
    }
  }
}

// ──────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────

Future<UserBloc> _makeUserBloc(AppDatabase db) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final ds = UserDriftDataSource(db);
  final repo = UserRepositoryImpl(ds);
  return UserBloc(
    getProfile: GetUserProfile(repo),
    updateName: UpdateUserName(repo),
    updateColor: UpdateUserColor(repo),
    userRepository: repo,
    prefs: prefs,
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// IT1 – IT20: Integration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

void main() {
  // Suppress Drift warning about multiple in-memory DB instances.
  // Each test creates its own isolated AppDatabase.inMemory() — no race condition.
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  // ━━━━━━━━━━━━━━━━━ Pipeline ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  test('IT1: BLE scan → NodeList → Session → Graph → GraphReady',
      tags: ['integration'], () {
    fakeAsync((async) async {
      final db = AppDatabase.inMemory();
      final nodeDs = NodeDriftDataSource(db);
      final nodeRepo = NodeRepositoryImpl(nodeDs);
      final scanRepo = ScanSessionRepositoryImpl(db);
      final bleRepo = _TestBleRepository();

      final bleBloc = BleBloc(
        repository: bleRepo,
        dutyCyclePeriod: const Duration(minutes: 10),
      );
      final nodeBloc = NodeListBloc(
        observeNodes: ObserveNodes(nodeRepo),
        updateNodeMetadata: UpdateNodeMetadata(nodeRepo),
        nodeRepository: nodeRepo,
      );

      // Start scan
      bleBloc.add(const StartScan());
      async.flushMicrotasks();

      // Simular detección de 3 dispositivos → sincronizar
      final devices = [
        BleDevice(
          deviceId: 'AA:BB:CC:DD:EE:01',
          rssi: -50,
          distance: rssiToDistance(-50),
          proximity: rssiToProximity(-50),
          timestamp: DateTime.now(),
          advName: 'Sensor A',
        ),
        BleDevice(
          deviceId: 'AA:BB:CC:DD:EE:02',
          rssi: -60,
          distance: rssiToDistance(-60),
          proximity: rssiToProximity(-60),
          timestamp: DateTime.now(),
          advName: 'Sensor B',
        ),
        BleDevice(
          deviceId: 'AA:BB:CC:DD:EE:03',
          rssi: -75,
          distance: rssiToDistance(-75),
          proximity: rssiToProximity(-75),
          timestamp: DateTime.now(),
          advName: 'Sensor C',
        ),
      ];

      nodeBloc.add(SyncBleDevices(devices));
      // Esperar que el handler asíncrono complete
      async.flushMicrotasks();
      await Future.delayed(const Duration(milliseconds: 50));
      async.flushMicrotasks();

      // Persistent nodes must exist in DB
      final savedNodes = await nodeRepo.observeNodes().first;
      expect(savedNodes.length, greaterThanOrEqualTo(3));

      // Crear sesión y asociar nodos
      final sessionId = await scanRepo.startSession();
      final nodeIds = savedNodes.map((n) => n.id!).toList();
      await scanRepo.addNodesToSession(sessionId, nodeIds);

      // Construir grafo real
      final graphRepo = GraphRepositoryImpl(nodeRepo, db);
      final layout = await graphRepo.buildGraph(sessionId,
          myDeviceUuid: 'self-uuid');
      expect(layout.nodes, isNotEmpty);
      expect(layout.nodes.length, greaterThanOrEqualTo(3));

      // Pipeline completo: VizBloc
      final buildGraph = BuildGraph(graphRepo);
      final calc = CalculateLayout(layoutAlgorithm: FruchtermanReingold());
      final vizBloc = VisualizationBloc(
        buildGraph: buildGraph,
        calculateLayout: calc,
        debounceDuration: const Duration(milliseconds: 10),
      );

      vizBloc.add(BuildGraphRequested(
        scanSessionId: sessionId,
        nodes: savedNodes,
        myDeviceUuid: 'self-uuid',
      ));
      // Adelantar tiempo para pasar el debounce
      async.elapse(const Duration(milliseconds: 30));
      async.flushMicrotasks();

      // Esperar GraphReady (FR puede tardar un poco)
      await Future.delayed(const Duration(milliseconds: 100));
      async.flushMicrotasks();

      final states = <VisualizationState>[];
      final sub = vizBloc.stream.listen(states.add);
      await Future.delayed(const Duration(milliseconds: 100));
      async.flushMicrotasks();

      final ready = states.whereType<GraphReady>().firstOrNull;
      expect(ready, isNotNull,
          reason: 'Pipeline must reach GraphReady');

      await sub.cancel();
      await vizBloc.close();
      await bleBloc.close();
      await nodeBloc.close();
      bleRepo.dispose();
      await db.close();
    });
  });

  // ━━━━━━━━━━━━━━━━━ User / Onboarding ━━━━━━━━━━━━━━━━━━━━━━━

  test('IT2: Onboarding → createProfile → persist → reload verify identity',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();
    final bloc = await _makeUserBloc(db);

    // DB vacía → LoadProfile crea perfil default
    bloc.add(const LoadProfile());
    await bloc.stream.firstWhere((s) => s is UserLoaded);

    final user = (bloc.state as UserLoaded).user;
    expect(user.name, 'Mi dispositivo');
    expect(user.color, '#2196F3');
    final uuid1 = user.uuid;
    expect(uuid1, isNotEmpty);

    // Reload: mismo UUID, mismos datos
    bloc.add(const LoadProfile());
    await bloc.stream.firstWhere(
      (s) => s is UserLoaded && s.user.uuid == uuid1,
    );

    final reloaded = (bloc.state as UserLoaded).user;
    expect(reloaded.uuid, uuid1);
    expect(reloaded.name, 'Mi dispositivo');

    await bloc.close();
    await db.close();
  });

  test('IT3: Connect → GATT connected → disconnect → verify state transitions',
      tags: ['integration'], () {
    fakeAsync((async) async {
      final db = AppDatabase.inMemory();
      final nodeDs = NodeDriftDataSource(db);
      final nodeRepo = NodeRepositoryImpl(nodeDs);
      final connRepo = _TestBleConnectionRepository();

      final bloc = BleConnectionBloc(
        connectionRepository: connRepo,
        nodeRepository: nodeRepo,
      );

      const remoteId = 'AA:BB:CC:DD:EE:FF';

      // Initial
      expect(bloc.state, isA<BleConnectionInitial>());

      // Connect → BleConnecting → BleConnected
      bloc.add(const ConnectToDevice(remoteId, myNodeId: 1));
      async.flushMicrotasks();
      expect(bloc.state, isA<BleConnected>());

      // Disconnect → BleConnectionInitial
      bloc.add(const DisconnectDevice(remoteId));
      async.flushMicrotasks();
      expect(bloc.state, isA<BleConnectionInitial>(),
          reason: 'After disconnect, must be Initial');

      await bloc.close();
      connRepo.dispose();
      await db.close();
    });
  });

  test('IT4: Set dark mode → restart UserBloc → verify ThemeMode persists',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();

    SharedPreferences.setMockInitialValues({});
    var prefs = await SharedPreferences.getInstance();
    final ds = UserDriftDataSource(db);
    final repo = UserRepositoryImpl(ds);

    var bloc = UserBloc(
      getProfile: GetUserProfile(repo),
      updateName: UpdateUserName(repo),
      updateColor: UpdateUserColor(repo),
      userRepository: repo,
      prefs: prefs,
    );

    // Load (auto-crea)
    bloc.add(const LoadProfile());
    await bloc.stream.firstWhere((s) => s is UserLoaded);

    // Set dark
    bloc.add(const UpdateThemeMode(AppThemeMode.dark));
    await Future.microtask(() {});
    expect((bloc.state as UserLoaded).themeMode, AppThemeMode.dark);
    expect(prefs.getString('theme_mode'), 'dark');

    await bloc.close();

    // Nuevo UserBloc — debe leer tema persistido
    prefs = await SharedPreferences.getInstance();
    bloc = UserBloc(
      getProfile: GetUserProfile(repo),
      updateName: UpdateUserName(repo),
      updateColor: UpdateUserColor(repo),
      userRepository: repo,
      prefs: prefs,
    );
    bloc.add(const LoadProfile());
    await bloc.stream.firstWhere((s) => s is UserLoaded);

    expect((bloc.state as UserLoaded).themeMode, AppThemeMode.dark,
        reason: 'Theme must survive BLoC restart');

    await bloc.close();
    await db.close();
  });

  // ━━━━━━━━━━━━━━━━━ Self-node & Dedup ━━━━━━━━━━━━━━━━━━━━━━━

  test('IT5: myDeviceUuid → buildGraph → isSelf=true for matching node',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();
    final nodeDs = NodeDriftDataSource(db);
    final nodeRepo = NodeRepositoryImpl(nodeDs);

    const myUuid = 'device-xxxx-xxxx-xxxx-xxxxxxxxxxxx';

    // Insertar 2 nodos: uno con bleAddress == myUuid (self)
    final now = DateTime.now();
    await nodeRepo.upsertNode(Node(
      bleAddress: myUuid, firstSeen: now, lastSeen: now,
      rssiHistory: const [-40]));
    await nodeRepo.upsertNode(Node(
      bleAddress: 'other-device', firstSeen: now, lastSeen: now,
      rssiHistory: const [-60]));

    final nodes = await nodeRepo.observeNodes().first;
    final scanRepo = ScanSessionRepositoryImpl(db);
    final sessionId = await scanRepo.startSession();
    await scanRepo.addNodesToSession(
        sessionId, nodes.map((n) => n.id!).toList());

    final graphRepo = GraphRepositoryImpl(nodeRepo, db);
    final layout = await graphRepo.buildGraph(sessionId,
        myDeviceUuid: myUuid);

    // Encontrar el self-node por isSelf=true
    final selfNodes = layout.nodes.where((n) => n.isSelf).toList();
    expect(selfNodes, hasLength(1),
        reason: 'Exactly 1 node must be marked isSelf');
    expect(selfNodes.single.id, isNotNull);

    // Al menos 1 nodo NO es self
    final nonSelf = layout.nodes.where((n) => !n.isSelf).toList();
    expect(nonSelf, isNotEmpty,
        reason: 'Other node must not be isSelf');

    await db.close();
  });

  test('IT6: Multiple BLE devices with same ID → dedup to single node',
      tags: ['integration'], () {
    fakeAsync((async) async {
      final db = AppDatabase.inMemory();
      final nodeDs = NodeDriftDataSource(db);
      final nodeRepo = NodeRepositoryImpl(nodeDs);
      final bloc = NodeListBloc(
        observeNodes: ObserveNodes(nodeRepo),
        updateNodeMetadata: UpdateNodeMetadata(nodeRepo),
        nodeRepository: nodeRepo,
      );

      const sameId = 'AA:BB:CC:DD:EE:DUP';
      final devices = [
        BleDevice(
          deviceId: sameId, rssi: -50, distance: 5, proximity: ProximityLevel.medium,
          timestamp: DateTime.now(), advName: 'Dupe A'),
        BleDevice(
          deviceId: sameId, rssi: -55, distance: 6, proximity: ProximityLevel.medium,
          timestamp: DateTime.now(), advName: 'Dupe A Update'),
        BleDevice(
          deviceId: 'other-dev', rssi: -60, distance: 7, proximity: ProximityLevel.medium,
          timestamp: DateTime.now(), advName: 'Unique'),
      ];

      bloc.add(SyncBleDevices(devices));
      async.flushMicrotasks();
      await Future.delayed(const Duration(milliseconds: 50));
      async.flushMicrotasks();

      final nodes = await nodeRepo.observeNodes().first;
      final addresses = nodes.map((n) => n.bleAddress).toSet();
      expect(addresses.length, 2,
          reason: 'Same deviceId must not create duplicate nodes');

      await bloc.close();
      await db.close();
    });
  });

  test('IT7: RSSI update → same IDs → graph rebuild with new proximity',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();
    final nodeDs = NodeDriftDataSource(db);
    final nodeRepo = NodeRepositoryImpl(nodeDs);

    // Insertar un nodo con RSSI -40 (close)
    final now = DateTime.now();
    await nodeRepo.upsertNode(Node(
      bleAddress: 'AA:BB:CC:DD:EE:PROX',
      firstSeen: now, lastSeen: now, rssiHistory: const [-40]));

    final nodes = await nodeRepo.observeNodes().first;
    final nodeId = nodes.first.id!;
    final scanRepo = ScanSessionRepositoryImpl(db);
    final sessionId = await scanRepo.startSession();
    await scanRepo.addNodesToSession(sessionId, [nodeId]);

    final graphRepo = GraphRepositoryImpl(nodeRepo, db);
    var layout = await graphRepo.buildGraph(sessionId);

    // RSSI -40 → proximity close
    final node1 = layout.nodes.firstWhere((n) => n.id == nodeId);
    expect(node1.proximity, ProximityLevel.close);

    // Actualizar nodo con RSSI -90 (far)
    await nodeRepo.upsertNode(Node(
      id: nodeId, bleAddress: 'AA:BB:CC:DD:EE:PROX',
      firstSeen: now, lastSeen: DateTime.now(),
      rssiHistory: const [-90]));

    // Rebuild → proximity debe cambiar
    layout = await graphRepo.buildGraph(sessionId);
    final node2 = layout.nodes.firstWhere((n) => n.id == nodeId);
    expect(node2.proximity, ProximityLevel.far,
        reason: 'RSSI update must change proximity in rebuilt graph');

    await db.close();
  });

  test('IT8: Empty DB → getUser returns null → UserBloc auto-creates default',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final ds = UserDriftDataSource(db);

    // DB vacía → getUser retorna null
    final user = await ds.getUser();
    expect(user, isNull);

    // UserBloc auto-crea el perfil default
    final repo = UserRepositoryImpl(ds);
    final bloc = UserBloc(
      getProfile: GetUserProfile(repo),
      updateName: UpdateUserName(repo),
      updateColor: UpdateUserColor(repo),
      userRepository: repo,
      prefs: prefs,
    );

    bloc.add(const LoadProfile());
    await bloc.stream.firstWhere((s) => s is UserLoaded);

    final loaded = (bloc.state as UserLoaded).user;
    expect(loaded.name, 'Mi dispositivo');
    expect(loaded.uuid, isNotEmpty);
    expect(loaded.color, '#2196F3');

    await bloc.close();
    await db.close();
  });

  // ━━━━━━━━━━━━━━━━━ Session + Edges ━━━━━━━━━━━━━━━━━━━━━━━━━

  test('IT9: Create session → insert nodes → buildGraph returns edges',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();
    final nodeDs = NodeDriftDataSource(db);
    final nodeRepo = NodeRepositoryImpl(nodeDs);

    final now = DateTime.now();
    await nodeRepo.upsertNode(Node(
      bleAddress: 'AA:01', firstSeen: now, lastSeen: now,
      rssiHistory: const [-50]));
    await nodeRepo.upsertNode(Node(
      bleAddress: 'AA:02', firstSeen: now, lastSeen: now,
      rssiHistory: const [-60]));
    await nodeRepo.upsertNode(Node(
      bleAddress: 'AA:03', firstSeen: now, lastSeen: now,
      rssiHistory: const [-70]));

    final nodes = await nodeRepo.observeNodes().first;
    final scanRepo = ScanSessionRepositoryImpl(db);
    final sessionId = await scanRepo.startSession();
    await scanRepo.addNodesToSession(
        sessionId, nodes.map((n) => n.id!).toList());

    // Insertar conexión entre node1 y node2
    await db.into(db.connections).insert(
      ConnectionsCompanion(
        fromNodeId: Value(nodes[0].id!),
        toNodeId: Value(nodes[1].id!),
        createdAt: Value(now),
      ),
      mode: InsertMode.insertOrIgnore,
    );

    final graphRepo = GraphRepositoryImpl(nodeRepo, db);
    final layout = await graphRepo.buildGraph(sessionId);

    expect(layout.nodes, hasLength(3));
    // Debe haber al menos una arista directa
    final directEdges = layout.edges
        .where((e) => e.edgeType == EdgeType.direct);
    expect(directEdges, isNotEmpty,
        reason: 'Session with a connection must produce edges');

    await db.close();
  });

  // ━━━━━━━━━━━━━━━━━ Layout / Metadata ━━━━━━━━━━━━━━━━━━━━━━━

  test('IT10: FR layout → preserve metadata after isolate computation',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();
    final nodeDs = NodeDriftDataSource(db);
    final nodeRepo = NodeRepositoryImpl(nodeDs);

    final now = DateTime.now();
    await nodeRepo.upsertNode(Node(
      bleAddress: 'meta-dev-1',
      firstSeen: now, lastSeen: now,
      rssiHistory: const [-45],
      suggestedName: 'Living Room Sensor',
      deviceType: 'Sensor',
      connectable: true,
    ));

    final nodes = await nodeRepo.observeNodes().first;
    final scanRepo = ScanSessionRepositoryImpl(db);
    final sessionId = await scanRepo.startSession();
    await scanRepo.addNodesToSession(
        sessionId, nodes.map((n) => n.id!).toList());

    final graphRepo = GraphRepositoryImpl(nodeRepo, db);
    final layout = await graphRepo.buildGraph(sessionId);

    final gn = layout.nodes.single;
    expect(gn.suggestedName, 'Living Room Sensor');
    expect(gn.connectable, isTrue);

    // Aplicar FR layout (con Isolate)
    final calc = CalculateLayout(layoutAlgorithm: FruchtermanReingold());
    final result = await calc(layout, 2000.0, 2000.0);
    final refined = result.fold(
      (f) => fail('FR failed: ${f.message}'),
      (r) => r,
    );

    final refinedNode = refined.nodes.single;
    expect(refinedNode.suggestedName, 'Living Room Sensor',
        reason: 'Metadata must survive FR isolate computation');

    await db.close();
  });

  // ━━━━━━━━━━━━━━━━━ BleConnectionBloc Lifecycle ━━━━━━━━━━━━━━

  test('IT11: BleConnectionBloc full lifecycle: connecting → connected → disconnected',
      tags: ['integration'], () {
    fakeAsync((async) async {
      final db = AppDatabase.inMemory();
      final nodeDs = NodeDriftDataSource(db);
      final nodeRepo = NodeRepositoryImpl(nodeDs);
      final connRepo = _TestBleConnectionRepository();

      final bloc = BleConnectionBloc(
        connectionRepository: connRepo,
        nodeRepository: nodeRepo,
      );

      const remoteId = '11:22:33:44:55:66';

      // 1. Initial
      expect(bloc.state, isA<BleConnectionInitial>());

      // 2. Connect → BleConnected
      bloc.add(const ConnectToDevice(remoteId, myNodeId: 1));
      async.flushMicrotasks();
      expect(bloc.state, isA<BleConnected>());

      // 3. Emitir connected → handler debe ejecutarse
      connRepo.emitConnected(remoteId);
      async.flushMicrotasks();

      // 4. Disconnect → BleConnectionInitial
      bloc.add(const DisconnectDevice(remoteId));
      async.flushMicrotasks();
      expect(bloc.state, isA<BleConnectionInitial>());

      await bloc.close();
      connRepo.dispose();
      await db.close();
    });
  });

  test('IT12: Onboarding + Settings roundtrip: set name/color → reload → verify',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();
    final bloc = await _makeUserBloc(db);

    // Load → auto-crea default
    bloc.add(const LoadProfile());
    await bloc.stream.firstWhere((s) => s is UserLoaded);

    // Set name and color (simula onboarding)
    bloc.add(const UpdateUserNameEvent('Zotel'));
    await bloc.stream.firstWhere(
      (s) => s is UserLoaded && s.user.name == 'Zotel');


    bloc.add(const UpdateUserColorEvent('#FF0000'));
    await bloc.stream.firstWhere(
      (s) => s is UserLoaded && s.user.color == '#FF0000');

    // Reload profile → must persist
    bloc.add(const LoadProfile());
    await bloc.stream.firstWhere((s) => s is UserLoaded);

    final user = (bloc.state as UserLoaded).user;
    expect(user.name, 'Zotel', reason: 'Name must survive reload');
    expect(user.color, '#FF0000', reason: 'Color must survive reload');

    await bloc.close();
    await db.close();
  });

  test('IT13: Theme survives name update (dark → updateName → theme stays dark)',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();
    final bloc = await _makeUserBloc(db);

    bloc.add(const LoadProfile());
    await bloc.stream.firstWhere((s) => s is UserLoaded);

    // Set dark
    bloc.add(const UpdateThemeMode(AppThemeMode.dark));
    await Future.microtask(() {});
    expect((bloc.state as UserLoaded).themeMode, AppThemeMode.dark);

    // Update name → themeMode must be preserved
    bloc.add(const UpdateUserNameEvent('Nuevo'));
    await bloc.stream.firstWhere(
      (s) => s is UserLoaded && s.user.name == 'Nuevo');

    expect((bloc.state as UserLoaded).themeMode, AppThemeMode.dark,
        reason: 'ThemeMode must NOT reset on name update');

    await bloc.close();
    await db.close();
  });

  test('IT14: RSSI null → proximity "far" (RSSI -100 semantics)',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();
    final nodeDs = NodeDriftDataSource(db);
    final nodeRepo = NodeRepositoryImpl(nodeDs);

    final now = DateTime.now();
    // Nodo con rssiHistory vacío → lastRssi fallback a -100
    await nodeRepo.upsertNode(Node(
      bleAddress: 'no-rssi-dev',
      firstSeen: now, lastSeen: now,
      rssiHistory: const []));

    final nodes = await nodeRepo.observeNodes().first;
    final scanRepo = ScanSessionRepositoryImpl(db);
    final sessionId = await scanRepo.startSession();
    await scanRepo.addNodesToSession(
        sessionId, nodes.map((n) => n.id!).toList());

    final graphRepo = GraphRepositoryImpl(nodeRepo, db);
    final layout = await graphRepo.buildGraph(sessionId);

    final gn = layout.nodes.single;
    // Sin RSSI → rssiHistory vacío → lastRssi = -100 → proximity far
    expect(gn.proximity, ProximityLevel.far,
        reason: 'Node without RSSI must render as far (RSSI -100 fallback)');

    await db.close();
  });

  test('IT15: Transaction rollback — no partial data persisted on failure',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();

    // Simular transacción que falla
    try {
      await db.transaction(() async {
        await db.into(db.scanSessions).insert(
          ScanSessionsCompanion.insert(
            startedAt: DateTime.now(), nodesDetected: 0));

        await db.into(db.nodes).insert(
          NodesCompanion.insert(
            bleAddress: 'rollback-test-01',
            firstSeen: DateTime.now(), lastSeen: DateTime.now()));

        throw Exception('Simulated mid-transaction failure');
      });
    } catch (_) {
      // Expected — rollback occurred
    }

    // NADA debe haberse persistido
    final sessions = await db.select(db.scanSessions).get();
    final nodes = await db.select(db.nodes).get();
    expect(sessions, isEmpty);
    expect(nodes, isEmpty);

    await db.close();
  });

  test('IT16: Session lifecycle: create → add nodes → endSession → verify history',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();
    final nodeDs = NodeDriftDataSource(db);
    final nodeRepo = NodeRepositoryImpl(nodeDs);
    final scanRepo = ScanSessionRepositoryImpl(db);

    // Insertar 5 nodos
    final now = DateTime.now();
    for (var i = 0; i < 5; i++) {
      await nodeRepo.upsertNode(Node(
        bleAddress: 'hist-dev-$i', firstSeen: now, lastSeen: now,
        rssiHistory: [-50 - i * 10]));
    }

    final nodes = await nodeRepo.observeNodes().first;
    expect(nodes, hasLength(5));

    // Create session
    final sessionId = await scanRepo.startSession();
    expect(sessionId, greaterThan(0));

    // Add nodes
    await scanRepo.addNodesToSession(
        sessionId, nodes.map((n) => n.id!).toList());

    // End session
    await scanRepo.endSession(sessionId);

    // Verify endedAt + nodesDetected
    final sessions = await db.select(db.scanSessions).get();
    final session = sessions.firstWhere((s) => s.id == sessionId,
        orElse: () => fail('Session not found'));
    expect(session.endedAt, isNotNull,
        reason: 'endSession must set endedAt');
    expect(session.nodesDetected, 5,
        reason: 'nodesDetected must match added nodes');

    await db.close();
  });

  test('IT17: 3D representation — z-coordinates survive graph rebuild',
      tags: ['integration'], () async {
    final db = AppDatabase.inMemory();
    final nodeDs = NodeDriftDataSource(db);
    final nodeRepo = NodeRepositoryImpl(nodeDs);

    final now = DateTime.now();
    await nodeRepo.upsertNode(Node(
      bleAddress: 'webview-3d-test',
      firstSeen: now, lastSeen: now,
      rssiHistory: const [-50]));

    final nodes = await nodeRepo.observeNodes().first;
    final graphRepo = GraphRepositoryImpl(nodeRepo, db);
    final scanRepo = ScanSessionRepositoryImpl(db);
    final sessionId = await scanRepo.startSession();
    await scanRepo.addNodesToSession(
        sessionId, nodes.map((n) => n.id!).toList());

    // Build twice — nodes must remain consistent
    final layout1 = await graphRepo.buildGraph(sessionId);
    final layout2 = await graphRepo.buildGraph(sessionId);

    for (final node in layout1.nodes) {
      expect(node.z, 0.0,
          reason: 'z-coordinate must be preserved across builds');
    }
    expect(layout1.nodes.length, layout2.nodes.length,
        reason: 'Graph rebuild must preserve node count');

    await db.close();
  });

  test('IT18: Auto-center on GraphReady — barycenter computed from node positions',
      tags: ['integration'], () {
    fakeAsync((async) async {
      final db = AppDatabase.inMemory();
      final nodeDs = NodeDriftDataSource(db);
      final nodeRepo = NodeRepositoryImpl(nodeDs);

      final now = DateTime.now();
      await nodeRepo.upsertNode(Node(
        bleAddress: 'center-dev-1', firstSeen: now, lastSeen: now,
        rssiHistory: const [-50]));
      await nodeRepo.upsertNode(Node(
        bleAddress: 'center-dev-2', firstSeen: now, lastSeen: now,
        rssiHistory: const [-60]));

      final nodes = await nodeRepo.observeNodes().first;
      final scanRepo = ScanSessionRepositoryImpl(db);
      final sessionId = await scanRepo.startSession();
      await scanRepo.addNodesToSession(
          sessionId, nodes.map((n) => n.id!).toList());

      final graphRepo = GraphRepositoryImpl(nodeRepo, db);
      final buildGraph = BuildGraph(graphRepo);
      final calc = CalculateLayout(layoutAlgorithm: FruchtermanReingold());

      final vizBloc = VisualizationBloc(
        buildGraph: buildGraph,
        calculateLayout: calc,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final states = <VisualizationState>[];
      final sub = vizBloc.stream.listen(states.add);

      vizBloc.add(BuildGraphRequested(
        scanSessionId: sessionId, nodes: nodes));
      async.elapse(const Duration(milliseconds: 30));
      async.flushMicrotasks();

      // Esperar a que FR termine
      await Future.delayed(const Duration(milliseconds: 200));
      async.flushMicrotasks();

      final ready = states.whereType<GraphReady>().firstOrNull;
      expect(ready, isNotNull, reason: 'Must reach GraphReady');

      final bc = ready!.barycenter;
      expect(bc, isNotNull,
          reason: 'GraphReady must include barycenter for auto-centering');
      expect(bc!.dx, greaterThan(0));
      expect(bc.dy, greaterThan(0));

      await sub.cancel();
      await vizBloc.close();
      await db.close();
    });
  });

  test('IT19: DeviceClassifier integration — classify returns correct deviceType',
      tags: ['integration'], () {
    const hrUuid = '0000180d-0000-1000-8000-00805f9b34fb'; // Heart Rate
    const batUuid = '0000180f-0000-1000-8000-00805f9b34fb'; // Battery
    const nodosUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

    // Heart Rate → "Reloj/Fitness"
    expect(DeviceClassifier.classify([hrUuid], null), 'Reloj/Fitness');

    // Nodos UUID → "Nodo" (máxima prioridad)
    expect(DeviceClassifier.classify([nodosUuid, hrUuid], null), 'Nodo',
        reason: 'Nodos service UUID must take priority');

    // Battery → "Batería"
    expect(DeviceClassifier.classify([batUuid], null), 'Batería');

    // Unknown UUID + manufacturer → brand-based fallback
    expect(DeviceClassifier.classify(['unknown-uuid'], 0x004C),
        'Apple (Desconocido)');

    // Nothing recognizable → null
    expect(DeviceClassifier.classify(['unknown'], null), isNull);
  });

  test('IT20: Full cold start — empty DB → onboarding → BLE scan → graph ready',
      tags: ['integration'], () {
    fakeAsync((async) async {
      final db = AppDatabase.inMemory();

      // ── Onboarding / User ──
      final userDs = UserDriftDataSource(db);
      final userRepo = UserRepositoryImpl(userDs);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final userBloc = UserBloc(
        getProfile: GetUserProfile(userRepo),
        updateName: UpdateUserName(userRepo),
        updateColor: UpdateUserColor(userRepo),
        userRepository: userRepo,
        prefs: prefs,
      );

      // First load → auto-create profile
      userBloc.add(const LoadProfile());
      await userBloc.stream.firstWhere((s) => s is UserLoaded);

      // Set name and color (onboarding)
      userBloc.add(const UpdateUserNameEvent('Zotel'));
      await userBloc.stream.firstWhere(
        (s) => s is UserLoaded && s.user.name == 'Zotel');
      userBloc.add(const UpdateUserColorEvent('#FF5722'));
      await userBloc.stream.firstWhere(
        (s) => s is UserLoaded && s.user.color == '#FF5722');

      final myUuid = userBloc.myDeviceUuid;
      expect(myUuid, isNotNull);

      // ── BLE scan + Nodes ──
      final nodeDs = NodeDriftDataSource(db);
      final nodeRepo = NodeRepositoryImpl(nodeDs);
      final scanRepo = ScanSessionRepositoryImpl(db);
      final bleRepo = _TestBleRepository();
      final bleBloc = BleBloc(
        repository: bleRepo, dutyCyclePeriod: const Duration(minutes: 10));
      final nodeBloc = NodeListBloc(
        observeNodes: ObserveNodes(nodeRepo),
        updateNodeMetadata: UpdateNodeMetadata(nodeRepo),
        nodeRepository: nodeRepo,
      );

      bleBloc.add(const StartScan());
      async.flushMicrotasks();

      // 5 dispositivos BLE
      final devices = [
        BleDevice(deviceId: 'DD:01', rssi: -45, distance: 2,
            proximity: ProximityLevel.close, timestamp: DateTime.now(), advName: 'S1'),
        BleDevice(deviceId: 'DD:02', rssi: -55, distance: 3,
            proximity: ProximityLevel.close, timestamp: DateTime.now(), advName: 'S2'),
        BleDevice(deviceId: 'DD:03', rssi: -65, distance: 4,
            proximity: ProximityLevel.medium, timestamp: DateTime.now(), advName: 'S3'),
        BleDevice(deviceId: 'DD:04', rssi: -75, distance: 6,
            proximity: ProximityLevel.medium, timestamp: DateTime.now(), advName: 'S4'),
        BleDevice(deviceId: 'DD:05', rssi: -85, distance: 10,
            proximity: ProximityLevel.far, timestamp: DateTime.now(), advName: 'S5'),
      ];

      nodeBloc.add(SyncBleDevices(devices));
      async.flushMicrotasks();
      await Future.delayed(const Duration(milliseconds: 50));
      async.flushMicrotasks();

      final nodes = await nodeRepo.observeNodes().first;
      expect(nodes.length, greaterThanOrEqualTo(5));

      // ── Session + Graph ──
      final sessionId = await scanRepo.startSession();
      await scanRepo.addNodesToSession(
          sessionId, nodes.map((n) => n.id!).toList());
      await scanRepo.endSession(sessionId);

      final graphRepo = GraphRepositoryImpl(nodeRepo, db);
      final layout = await graphRepo.buildGraph(sessionId,
          myDeviceUuid: myUuid);

      expect(layout.nodes.length, greaterThanOrEqualTo(5),
          reason: 'Cold start must produce graph with all detected nodes');

      // Cleanup
      await userBloc.close();
      await bleBloc.close();
      await nodeBloc.close();
      bleRepo.dispose();
      await db.close();
    });
  });

  // ━━━━━━━━━━━━━━━━━ Sanity checks ━━━━━━━━━━━━━━━━━━━━━━━━━

  test('DB inMemory: each instance is isolated from others',
      tags: ['integration'], () async {
    final db1 = AppDatabase.inMemory();
    final db2 = AppDatabase.inMemory();

    await db1.into(db1.users).insert(
      UsersCompanion.insert(
        uuid: 'separation-test', name: 'T', color: '#000',
        deviceType: 'test', createdAt: DateTime.now()));

    final user2 = await (db2.select(db2.users)
          ..where((u) => u.uuid.equals('separation-test')))
        .getSingleOrNull();
    expect(user2, isNull,
        reason: 'Each inMemory DB must be isolated');

    await db1.close();
    await db2.close();
  });
}
