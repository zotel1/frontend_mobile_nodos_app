import 'package:get_it/get_it.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_blue_plus_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_blue_plus_gatt_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_ble_peripheral_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/repositories/ble_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/repositories/ble_connection_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/start_ble_scan.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/stop_ble_scan.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/start_ble_advertise.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/stop_ble_advertise.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/datasources/node_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/data/repositories/node_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/get_node_detail.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/update_node_metadata.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_local_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/datasources/user_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/user/data/repositories/user_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/get_user_profile.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_name.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_color.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/repositories/graph_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/repositories/graph_repository.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/build_graph.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/algorithms/layout_algorithm.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/algorithms/fruchterman_reingold.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/history/data/datasources/history_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/repositories/history_repository.dart';
import 'package:frontend_mobile_nodos_app/features/history/data/repositories/history_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_scan_sessions.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_session_detail.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/bloc/history_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/domain/repositories/scan_session_repository.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/data/datasources/scan_session_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/presentation/bloc/scan_session_bloc.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // ── BLE Platform Config ──
  // R5.6: Modo de cola de operaciones por dispositivo.
  FlutterBluePlus.setOperationQueueMode(OperationQueueMode.perDevice);

  // ── Database ──
  // La BD usa un seed constante para pre-release.
  // En producción, la clave se derivará de un secreto específico del dispositivo.
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

  // ── GATT datasource ──
  sl.registerLazySingleton<BleGattDataSource>(
    () => FlutterBluePlusGattDataSource(),
  );

  // ── Node data sources ──
  sl.registerLazySingleton<NodeLocalDataSource>(
    () => NodeDriftDataSource(sl()),
  );

  // ── User data sources ──
  sl.registerLazySingleton<UserLocalDataSource>(
    () => UserDriftDataSource(sl()),
  );

  // ── History datasource ──
  // Encapsula las queries SQL sobre scan_sessions, scan_session_nodes y nodes.
  // El repositorio depende de este datasource, no de AppDatabase directamente.
  sl.registerLazySingleton<HistoryDriftDataSource>(
    () => HistoryDriftDataSource(sl<AppDatabase>()),
  );

  // ── Repositories ──
  sl.registerLazySingleton<BleRepository>(
    () => BleRepositoryImpl(
      scanner: sl(),
      advertiser: sl(),
      sessionRepository: sl<ScanSessionRepository>(),
    ),
  );
  sl.registerLazySingleton<NodeRepository>(
    () => NodeRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<UserRepository>(
    () => UserRepositoryImpl(sl()),
  );

  // ── History repository ──
  // Depende de HistoryDriftDataSource, no de AppDatabase.
  sl.registerLazySingleton<HistoryRepository>(
    () => HistoryRepositoryImpl(sl<HistoryDriftDataSource>()),
  );

  // ── BleConnection repository ──
  // Encapsula las operaciones GATT y persistencia de conexiones.
  // BleConnectionBloc depende de esta abstracción, no de datasources concretos.
  sl.registerLazySingleton<BleConnectionRepository>(
    () => BleConnectionRepositoryImpl(
      gatt: sl<BleGattDataSource>(),
      db: sl<AppDatabase>(),
    ),
  );

  // ── Use cases ──
  sl.registerLazySingleton(() => StartBleScan(sl()));
  sl.registerLazySingleton(() => StopBleScan(sl()));
  sl.registerLazySingleton(() => StartBleAdvertise(sl()));
  sl.registerLazySingleton(() => StopBleAdvertise(sl()));
  sl.registerLazySingleton(() => ObserveNodes(sl()));
  sl.registerLazySingleton(() => GetNodeDetail(sl()));
  sl.registerLazySingleton(() => UpdateNodeMetadata(sl()));
  sl.registerLazySingleton(() => GetUserProfile(sl()));
  sl.registerLazySingleton(() => UpdateUserName(sl()));
  sl.registerLazySingleton(() => UpdateUserColor(sl()));

  // ── Graph ──
  sl.registerLazySingleton<GraphRepository>(
    () => GraphRepositoryImpl(sl(), sl()),
  );
  sl.registerLazySingleton(() => BuildGraph(sl()));
  sl.registerLazySingleton<LayoutAlgorithm>(() => const FruchtermanReingold());
  sl.registerLazySingleton(() => CalculateLayout(layoutAlgorithm: sl()));

  // ── History use cases ──
  sl.registerLazySingleton(() => GetScanSessions(sl<HistoryRepository>()));
  sl.registerLazySingleton(() => GetSessionDetail(sl<HistoryRepository>()));
  sl.registerLazySingleton(() => GetHistoryStats(sl<HistoryRepository>()));

  // ── BLoCs (factory — new instance per BlocProvider) ──
  sl.registerFactory(() => BleBloc(repository: sl()));
  // BleConnectionBloc: depende del repositorio de conexión en vez de
  // datasource + db directos. El repositorio abstrae GATT + persistencia.
  sl.registerFactory<BleConnectionBloc>(
    () => BleConnectionBloc(
      connectionRepository: sl<BleConnectionRepository>(),
      nodeRepository: sl<NodeRepository>(),
    ),
  );
  sl.registerFactory<NodeListBloc>(
    () => NodeListBloc(
      observeNodes: sl(),
      updateNodeMetadata: sl(),
      nodeRepository: sl(),
    ),
  );
  sl.registerFactory<UserBloc>(
    () => UserBloc(
      getProfile: sl(),
      updateName: sl(),
      updateColor: sl(),
      userRepository: sl(),
      prefs: sl(),
    ),
  );
  sl.registerFactory<VisualizationBloc>(
    () => VisualizationBloc(
      buildGraph: sl(),
      calculateLayout: sl(),
    ),
  );

  // HistoryBloc: gestiona historial de sesiones y estadísticas.
  sl.registerFactory<HistoryBloc>(
    () => HistoryBloc(
      getScanSessions: sl(),
      getSessionDetail: sl(),
      getHistoryStats: sl(),
    ),
  );

  // ScanSessionBloc: gestiona el ciclo de vida de sesiones de escaneo.
  sl.registerLazySingleton<ScanSessionRepository>(
    () => ScanSessionRepositoryImpl(sl<AppDatabase>()),
  );
  sl.registerFactory<ScanSessionBloc>(
    () => ScanSessionBloc(repository: sl()),
  );
}
