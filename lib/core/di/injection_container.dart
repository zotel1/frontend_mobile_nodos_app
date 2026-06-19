import 'package:get_it/get_it.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // ── Database ──
  sl.registerLazySingleton<AppDatabase>(() => AppDatabase());

  // More registrations in PR2–PR4:
  // - Data sources
  // - Repositories
  // - Use cases
}
