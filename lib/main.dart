import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app.dart';
import 'core/di/injection_container.dart' as di;
import 'core/utils/app_bloc_observer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await di.initDependencies();

  if (kDebugMode) {
    Bloc.observer = AppBlocObserver();
  }

  runApp(const NodosApp());
}
