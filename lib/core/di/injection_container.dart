import 'package:get_it/get_it.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_scanner_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_advertiser_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_blue_plus_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_ble_peripheral_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/repositories/ble_repository_impl.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/start_ble_scan.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/stop_ble_scan.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/start_ble_advertise.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/stop_ble_advertise.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
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
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // ── Database ──
  sl.registerLazySingleton<AppDatabase>(() => AppDatabase());

  // ── BLE data sources ──
  sl.registerLazySingleton<BleScannerDataSource>(
    () => FlutterBluePlusDataSource(),
  );
  sl.registerLazySingleton<BleAdvertiserDataSource>(
    () => FlutterBlePeripheralDataSource(),
  );

  // ── Node data sources ──
  sl.registerLazySingleton<NodeLocalDataSource>(
    () => NodeDriftDataSource(sl()),
  );

  // ── User data sources ──
  sl.registerLazySingleton<UserLocalDataSource>(
    () => UserDriftDataSource(sl()),
  );

  // ── Repositories ──
  sl.registerLazySingleton<BleRepository>(
    () => BleRepositoryImpl(
      scanner: sl(),
      advertiser: sl(),
    ),
  );
  sl.registerLazySingleton<NodeRepository>(
    () => NodeRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<UserRepository>(
    () => UserRepositoryImpl(sl()),
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
  // Registra el repositorio de grafos que deriva aristas desde
  // la tabla scan_session_nodes y nodos desde NodeRepository.
  sl.registerLazySingleton<GraphRepository>(
    () => GraphRepositoryImpl(sl(), sl()),
  );
  // Caso de uso: construye el LayoutResult inicial desde el repositorio.
  sl.registerLazySingleton(() => BuildGraph(sl()));
  // Caso de uso: ejecuta Fruchterman-Reingold en un Isolate.
  sl.registerLazySingleton(() => const CalculateLayout());

  // ── BLoCs (factory — new instance per BlocProvider) ──
  sl.registerFactory(() => BleBloc(repository: sl()));
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
    ),
  );
  // VisualizationBloc: orquesta BuildGraph + CalculateLayout con debounce.
  // Se registra como factory para que cada BlocProvider obtenga su instancia.
  sl.registerFactory<VisualizationBloc>(
    () => VisualizationBloc(
      buildGraph: sl(),
      calculateLayout: sl(),
    ),
  );
}
