import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Observador global de BLoC para la app Nodos.
///
/// QUÉ hace: registra cada transición de estado, error y evento de
/// todos los BLoCs de la aplicación. Centraliza el logging para
/// debugging y monitoreo en producción.
///
/// POR QUÉ: T-PR1-008 — antes la app no tenía BlocObserver global.
/// Errores silenciosos en BLoCs (como StateError por eventos sin
/// handler) pasaban desapercibidos porque no había logging
/// centralizado. Este observer captura transiciones y errores de
/// TODOS los BLoCs, permitiendo diagnosticar crashes en runtime.
///
/// QUÉ problema resuelve: HIGH H4 — falta de observabilidad en la
/// capa BLoC. Sin observer, los errores de eventos no manejados
/// o transiciones inesperadas son invisibles durante debugging.
///
/// Se registra en [main.dart] con `Bloc.observer = AppBlocObserver();`
/// antes de `runApp()`.
class AppBlocObserver extends BlocObserver {
  /// Registra cada cambio de estado en cualquier BLoC.
  ///
  /// QUÉ: imprime el BLoC, evento, estado actual y próximo estado.
  /// Solo visible en debug mode para no contaminar logs de release.
  /// POR QUÉ: saber qué evento causó qué transición es esencial para
  /// diagnosticar bugs de lógica de estado.
  @override
  void onTransition(Bloc<dynamic, dynamic> bloc, Transition transition) {
    super.onTransition(bloc, transition);
    if (kDebugMode) {
      debugPrint(
        '[BLoC] ${bloc.runtimeType}: ${transition.event.runtimeType} '
        '→ ${transition.currentState.runtimeType} '
        '→ ${transition.nextState.runtimeType}',
      );
    }
  }

  /// Registca errores emitidos por cualquier BLoC.
  ///
  /// QUÉ: captura el error y stack trace. En debug mode imprime
  /// información del BLoC. En producción podría enviarse a Crashlytics.
  /// POR QUÉ: errores como StateError por eventos sin handler matan
  /// el BLoC silenciosamente. Con este observer, el error queda
  /// registrado y es diagnosticable.
  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    if (kDebugMode) {
      debugPrint(
        '[BLoC ERROR] ${bloc.runtimeType}: $error',
      );
    }
    // En producción, aquí se integraría con Crashlytics o
    // un sistema de reporte de errores.
  }

  /// Registra cada evento despachado a cualquier BLoC.
  ///
  /// QUÉ: imprime el tipo de BLoC y evento. Útil para trazar
  /// el flujo completo de eventos durante debugging.
  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    if (kDebugMode) {
      debugPrint('[BLoC EVENT] ${bloc.runtimeType}: ${event.runtimeType}');
    }
  }
}
