import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app.dart';
import 'core/di/injection_container.dart' as di;
import 'core/observers/app_bloc_observer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // T-PR1-008: Registrar el observer global de BLoC para logging
  // centralizado de transiciones, eventos y errores.
  Bloc.observer = AppBlocObserver();
  await di.initDependencies();

  runApp(const NodosApp());
}
