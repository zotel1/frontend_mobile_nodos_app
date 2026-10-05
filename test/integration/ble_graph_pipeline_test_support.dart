import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/repositories/ble_connection_repository_impl.dart';

import 'package:frontend_mobile_nodos_app/core/database/app_database.dart'
    hide User;
import 'package:frontend_mobile_nodos_app/core/utils/app_theme_mode.dart';
import 'package:frontend_mobile_nodos_app/core/utils/device_classifier.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/active_graph_exchange_service.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/repositories/node_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/ensure_local_node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/update_node_metadata.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/data/datasources/scan_session_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/repositories/user_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';
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

import 'package:frontend_mobile_nodos_app/features/history/data/datasources/history_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/history/data/repositories/history_repository_impl.dart';

export 'dart:async';
export 'dart:typed_data';
export 'package:drift/drift.dart' hide Column, isNull, isNotNull;
export 'package:fake_async/fake_async.dart';
export 'package:flutter_test/flutter_test.dart';
export 'package:shared_preferences/shared_preferences.dart';
export 'package:frontend_mobile_nodos_app/core/database/app_database.dart'
    hide User;
export 'package:frontend_mobile_nodos_app/core/utils/app_theme_mode.dart';
export 'package:frontend_mobile_nodos_app/core/utils/device_classifier.dart';
export 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
export 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';
export 'package:frontend_mobile_nodos_app/features/ble/data/repositories/ble_connection_repository_impl.dart';
export 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
export 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
export 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
export 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
export 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
export 'package:frontend_mobile_nodos_app/features/ble/domain/services/active_graph_exchange_service.dart';
export 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
export 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
export 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
export 'package:frontend_mobile_nodos_app/features/history/data/datasources/history_drift_datasource.dart';
export 'package:frontend_mobile_nodos_app/features/history/data/repositories/history_repository_impl.dart';
export 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_drift_datasource.dart';
export 'package:frontend_mobile_nodos_app/features/nodes/data/repositories/node_repository_impl.dart';
export 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
export 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/ensure_local_node.dart';
export 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';
export 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/update_node_metadata.dart';
export 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
export 'package:frontend_mobile_nodos_app/features/scan_session/data/datasources/scan_session_drift_datasource.dart';
export 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_drift_datasource.dart';
export 'package:frontend_mobile_nodos_app/features/user/data/repositories/user_repository_impl.dart';
export 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
export 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';
export 'package:frontend_mobile_nodos_app/features/user/domain/usecases/get_user_profile.dart';
export 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_color.dart';
export 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_name.dart';
export 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/data/algorithms/fruchterman_reingold.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/data/repositories/graph_repository_impl.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/build_graph.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
export 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';

// ──────────────────────────────────────────────────────────────
// Stub BLE Repository (hardware boundary — única sustitución)
// ──────────────────────────────────────────────────────────────

class TestBleRepository implements BleRepository {
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
  Future<void> updateGraphPayload(Uint8List payload) async {}
  @override
  Future<void> stopAdvertise() async {}

  @override
  Stream<BleIncomingGattWrite> get incomingLinkRequests => const Stream.empty();

  @override
  Future<void> sendLinkResponse(Uint8List payload) async {}

  @override
  Stream<BleIncomingGattWrite> get incomingPeerGraphPayloads =>
      const Stream.empty();

  @override
  Future<void> endScanSession() async {}

  void emitDevices(List<BleDevice> devices) {
    _scanController.add(devices);
  }

  void emitBluetoothOn() {
    _btController.add(true);
  }

  void dispose() {
    _scanController.close();
    _btController.close();
  }
}

// ──────────────────────────────────────────────────────────────
// Fake GATT DataSource para integración BUG-001
// ──────────────────────────────────────────────────────────────

class TestBleGattDataSource implements BleGattDataSource {
  final Map<String, bool> _connected = {};

  @override
  Future<void> connect(String remoteId) async {
    _connected[remoteId] = true;
  }

  @override
  Future<void> disconnect(String remoteId) async {
    _connected[remoteId] = false;
  }

  @override
  Future<bool> isConnected(String remoteId) async {
    return _connected[remoteId] ?? false;
  }

  @override
  Stream<bool> connectionState(String remoteId) async* {
    yield _connected[remoteId] ?? false;
  }

  @override
  Stream<List<int>> characteristicValueStream(
    String remoteId,
    String characteristicUuid,
  ) => const Stream<List<int>>.empty();

  @override
  Future<List<BleServiceInfo>> discoverServices(String remoteId) async {
    return const [];
  }

  @override
  Future<List<int>?> readCharacteristic(
    String remoteId,
    String characteristicUuid,
  ) async {
    return null;
  }

  @override
  Future<bool> writeCharacteristic(
    String remoteId,
    String characteristicUuid,
    List<int> payload,
  ) async => true;

  @override
  Future<List<int>?> writeAndWaitForResponse(
    String remoteId,
    String characteristicUuid,
    List<int> requestPayload, {
    Duration timeout = const Duration(seconds: 30),
  }) async => null;
}

// ──────────────────────────────────────────────────────────────
// Stub BLE Connection Repository
// ──────────────────────────────────────────────────────────────

class TestBleConnectionRepository implements BleConnectionRepository {
  final _stateControllers = <String, StreamController<bool>>{};

  @override
  Future<void> connect(String remoteId) async {}

  @override
  Future<void> disconnect(String remoteId) async {}

  @override
  Stream<bool> connectionState(String remoteId) {
    return (_stateControllers.putIfAbsent(
      remoteId,
      () => StreamController<bool>.broadcast(),
    )).stream;
  }

  @override
  Stream<List<int>> characteristicValueStream(
    String remoteId,
    String characteristicUuid,
  ) => const Stream<List<int>>.empty();

  @override
  Future<void> discoverServices(String remoteId) async {}

  @override
  Future<List<int>?> readCharacteristic(
    String remoteId,
    String characteristicUuid,
  ) async {
    return null;
  }

  @override
  Future<bool> writeCharacteristic(
    String remoteId,
    String characteristicUuid,
    List<int> payload,
  ) async => true;

  @override
  Future<List<int>?> writeAndWaitForResponse(
    String remoteId,
    String characteristicUuid,
    List<int> requestPayload, {
    Duration timeout = const Duration(seconds: 30),
  }) async => null;

  @override
  Future<void> saveConnection(int fromNodeId, int toNodeId) async {}

  void emitConnected(String remoteId) {
    _stateControllers[remoteId]?.add(true);
  }

  void emitDisconnected(String remoteId) {
    _stateControllers[remoteId]?.add(false);
  }

  void dispose() {
    for (final controller in _stateControllers.values) {
      controller.close();
    }
  }
}

class TestUserRepository implements UserRepository {
  User? profile;

  @override
  Future<User?> getUserProfile() async => profile;

  @override
  Future<void> updateName(String name) async {}

  @override
  Future<void> updateColor(String color) async {}

  @override
  Future<void> createUser(User user) async {
    profile = user;
  }

  @override
  Future<void> setLocalNodeId(int nodeId) async {}
}

class TestRemoteRelationRepository implements RemoteRelationRepository {
  @override
  Future<void> replaceSnapshot({
    required String reporterUuid,
    required List<NodosGraphConnection> connections,
  }) async {}

  @override
  Future<void> clearSnapshot(String reporterUuid) async {}

  @override
  Future<List<RemoteRelation>> getSnapshot(String reporterUuid) async => [];

  @override
  Stream<List<RemoteRelation>> watchAll() => Stream.value(const []);
}

// ──────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────

Future<UserBloc> makeUserBloc(AppDatabase db) async {
  SharedPreferences.setMockInitialValues({});

  final prefs = await SharedPreferences.getInstance();

  final userDs = UserDriftDataSource(db);
  final userRepo = UserRepositoryImpl(userDs);

  final nodeDs = NodeDriftDataSource(db);
  final nodeRepo = NodeRepositoryImpl(nodeDs);

  final ensureLocalNode = EnsureLocalNode(
    nodeRepository: nodeRepo,
    userRepository: userRepo,
  );

  return UserBloc(
    getProfile: GetUserProfile(userRepo),
    updateName: UpdateUserName(userRepo),
    updateColor: UpdateUserColor(userRepo),
    ensureLocalNode: ensureLocalNode,
    userRepository: userRepo,
    prefs: prefs,
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// IT1 – IT20: Integration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
