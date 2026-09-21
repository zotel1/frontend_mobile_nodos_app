import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';

import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_ble_peripheral_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_blue_plus_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_blue_plus_gatt_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/remote_relation_drift_datasource.dart';

import 'package:frontend_mobile_nodos_app/features/ble/data/repositories/ble_connection_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/repositories/ble_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/repositories/remote_relation_repository_impl.dart';

import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';

import 'package:frontend_mobile_nodos_app/features/ble/domain/services/active_graph_exchange_service.dart';

import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/start_ble_advertise.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/start_ble_scan.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/stop_ble_advertise.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/stop_ble_scan.dart';

import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';

import 'package:frontend_mobile_nodos_app/features/history/data/datasources/history_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/history/data/repositories/history_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/repositories/history_repository.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_scan_sessions.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_session_detail.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/bloc/history_bloc.dart';

import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/repositories/node_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/ensure_local_node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/get_node_detail.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/update_node_metadata.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';

import 'package:frontend_mobile_nodos_app/features/scan_session/data/datasources/scan_session_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/domain/repositories/scan_session_repository.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/presentation/bloc/scan_session_bloc.dart';

import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/repositories/user_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/get_user_profile.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_color.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_name.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';

import 'package:frontend_mobile_nodos_app/features/visualization/data/algorithms/fruchterman_reingold.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/repositories/graph_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/algorithms/layout_algorithm.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/repositories/graph_repository.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/build_graph.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // ── BLE Platform Config ──
  // R5.6: Modo de cola de operaciones por dispositivo.
  FlutterBluePlus.setOperationQueueMode(OperationQueueMode.perDevice);

  // ── Database ──
  //
  // La BD usa un seed constante para pre-release.
  // En producción, la clave se derivará de un secreto específico
  // del dispositivo.
  const encryptionSeed = 'nodos_app_v1_encryption_seed_2026';

  sl.registerLazySingleton<AppDatabase>(
    () => AppDatabase(encryptionKey: encryptionSeed),
  );

  // ── SharedPreferences ──
  final prefs = await SharedPreferences.getInstance();

  sl.registerLazySingleton<SharedPreferences>(() => prefs);

  // ── BLE data sources ──

  sl.registerLazySingleton<BleScannerDataSource>(
    () => FlutterBluePlusDataSource(),
  );

  sl.registerLazySingleton<BleAdvertiserDataSource>(
    () => FlutterBlePeripheralDataSource(),
  );

  sl.registerLazySingleton<BleGattDataSource>(
    () => FlutterBluePlusGattDataSource(),
  );

  // ── Node data sources ──

  sl.registerLazySingleton<NodeLocalDataSource>(
    () => NodeDriftDataSource(sl<AppDatabase>()),
  );

  // ── User data sources ──

  sl.registerLazySingleton<UserLocalDataSource>(
    () => UserDriftDataSource(sl<AppDatabase>()),
  );

  // ── History data source ──

  sl.registerLazySingleton<HistoryDriftDataSource>(
    () => HistoryDriftDataSource(sl<AppDatabase>()),
  );

  // ── Remote relations data source ──
  //
  // Persiste el último snapshot activo recibido desde cada instalación Nodos.
  //
  // No utiliza la tabla `connections`.
  sl.registerLazySingleton<RemoteRelationDriftDataSource>(
    () => RemoteRelationDriftDataSource(sl<AppDatabase>()),
  );

  // ── Repositories ──

  sl.registerLazySingleton<BleRepository>(
    () => BleRepositoryImpl(
      scanner: sl<BleScannerDataSource>(),
      advertiser: sl<BleAdvertiserDataSource>(),
      sessionRepository: sl<ScanSessionRepository>(),
    ),
  );

  sl.registerLazySingleton<NodeRepository>(
    () => NodeRepositoryImpl(sl<NodeLocalDataSource>()),
  );

  sl.registerLazySingleton<UserRepository>(
    () => UserRepositoryImpl(sl<UserLocalDataSource>()),
  );

  sl.registerLazySingleton<HistoryRepository>(
    () => HistoryRepositoryImpl(sl<HistoryDriftDataSource>()),
  );

  // ── Remote relations repository ──
  //
  // Abstracción utilizada para persistir y consultar los snapshots
  // recibidos desde otras instalaciones Nodos sin exponer el datasource
  // concreto a las capas consumidoras.
  sl.registerLazySingleton<RemoteRelationRepository>(
    () => RemoteRelationRepositoryImpl(sl<RemoteRelationDriftDataSource>()),
  );

  // ── BLE connection repository ──
  //
  // Encapsula:
  // - operaciones GATT;
  // - persistencia de conexiones locales.
  sl.registerLazySingleton<BleConnectionRepository>(
    () => BleConnectionRepositoryImpl(
      gatt: sl<BleGattDataSource>(),
      db: sl<AppDatabase>(),
    ),
  );

  // ── Active graph exchange ──
  //
  // Mantiene el conjunto de conexiones BLE actualmente activas conocidas
  // por esta instalación y publica el snapshot distribuible mediante GATT.
  //
  // IMPORTANTE:
  // - NO usa `connections` como fuente del estado activo.
  // - NO transmite bleAddress como identidad global.
  // - Debe existir una sola instancia durante la ejecución.
  sl.registerLazySingleton<ActiveGraphExchangeService>(
    () => ActiveGraphExchangeService(
      nodeRepository: sl<NodeRepository>(),
      userRepository: sl<UserRepository>(),
      bleRepository: sl<BleRepository>(),
    ),
  );

  // ── BLE use cases ──

  sl.registerLazySingleton(() => StartBleScan(sl<BleRepository>()));

  sl.registerLazySingleton(() => StopBleScan(sl<BleRepository>()));

  sl.registerLazySingleton(() => StartBleAdvertise(sl<BleRepository>()));

  sl.registerLazySingleton(() => StopBleAdvertise(sl<BleRepository>()));

  // ── Node use cases ──

  sl.registerLazySingleton(() => ObserveNodes(sl<NodeRepository>()));

  sl.registerLazySingleton(() => GetNodeDetail(sl<NodeRepository>()));

  sl.registerLazySingleton(() => UpdateNodeMetadata(sl<NodeRepository>()));

  sl.registerLazySingleton(
    () => EnsureLocalNode(
      nodeRepository: sl<NodeRepository>(),
      userRepository: sl<UserRepository>(),
    ),
  );

  // ── User use cases ──

  sl.registerLazySingleton(() => GetUserProfile(sl<UserRepository>()));

  sl.registerLazySingleton(() => UpdateUserName(sl<UserRepository>()));

  sl.registerLazySingleton(() => UpdateUserColor(sl<UserRepository>()));

  // ── Graph ──
  //
  // GraphRepository combina:
  // - nodos locales/persistidos mediante NodeRepository;
  // - relaciones locales mediante AppDatabase;
  // - snapshots distribuidos mediante RemoteRelationRepository.
  sl.registerLazySingleton<GraphRepository>(
    () => GraphRepositoryImpl(
      sl<NodeRepository>(),
      sl<AppDatabase>(),
      sl<RemoteRelationRepository>(),
    ),
  );

  sl.registerLazySingleton(() => BuildGraph(sl<GraphRepository>()));

  sl.registerLazySingleton<LayoutAlgorithm>(() => const FruchtermanReingold());

  sl.registerLazySingleton(
    () => CalculateLayout(layoutAlgorithm: sl<LayoutAlgorithm>()),
  );

  // ── History use cases ──

  sl.registerLazySingleton(() => GetScanSessions(sl<HistoryRepository>()));

  sl.registerLazySingleton(() => GetSessionDetail(sl<HistoryRepository>()));

  sl.registerLazySingleton(() => GetHistoryStats(sl<HistoryRepository>()));

  // ── Scan session repository ──
  //
  // LazySingleton porque representa el acceso compartido a las sesiones
  // de escaneo persistidas.
  sl.registerLazySingleton<ScanSessionRepository>(
    () => ScanSessionRepositoryImpl(sl<AppDatabase>()),
  );

  // ── BLoCs ──
  //
  // Factory: cada BlocProvider obtiene una instancia nueva.

  sl.registerFactory<BleBloc>(() => BleBloc(repository: sl<BleRepository>()));

  // BleConnectionBloc coordina:
  // - operaciones GATT mediante BleConnectionRepository;
  // - resolución de nodos mediante NodeRepository;
  // - publicación del snapshot local mediante ActiveGraphExchangeService;
  // - persistencia de snapshots recibidos mediante RemoteRelationRepository.
  sl.registerFactory<BleConnectionBloc>(
    () => BleConnectionBloc(
      connectionRepository: sl<BleConnectionRepository>(),
      nodeRepository: sl<NodeRepository>(),
      activeGraphExchange: sl<ActiveGraphExchangeService>(),
      remoteRelationRepository: sl<RemoteRelationRepository>(),
    ),
  );

  sl.registerFactory<NodeListBloc>(
    () => NodeListBloc(
      observeNodes: sl<ObserveNodes>(),
      updateNodeMetadata: sl<UpdateNodeMetadata>(),
      nodeRepository: sl<NodeRepository>(),
    ),
  );

  sl.registerFactory<UserBloc>(
    () => UserBloc(
      getProfile: sl<GetUserProfile>(),
      updateName: sl<UpdateUserName>(),
      updateColor: sl<UpdateUserColor>(),
      ensureLocalNode: sl<EnsureLocalNode>(),
      userRepository: sl<UserRepository>(),
      prefs: sl<SharedPreferences>(),
    ),
  );

  // VisualizationBloc observa tanto los cambios BLE solicitados por la UI
  // como los cambios persistidos en remote_relations.
  sl.registerFactory<VisualizationBloc>(
    () => VisualizationBloc(
      buildGraph: sl<BuildGraph>(),
      calculateLayout: sl<CalculateLayout>(),
      remoteRelationRepository: sl<RemoteRelationRepository>(),
    ),
  );

  sl.registerFactory<HistoryBloc>(
    () => HistoryBloc(
      getScanSessions: sl<GetScanSessions>(),
      getSessionDetail: sl<GetSessionDetail>(),
      getHistoryStats: sl<GetHistoryStats>(),
    ),
  );

  sl.registerFactory<ScanSessionBloc>(
    () => ScanSessionBloc(repository: sl<ScanSessionRepository>()),
  );
}
