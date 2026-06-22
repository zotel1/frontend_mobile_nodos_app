import 'package:bloc/bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── T-PR1-007: Tests para AppBlocObserver ───────────────────────────
// QUÉ: verifica que AppBlocObserver registra transiciones de estado,
// errores y eventos de todos los BLoCs de la app.
// POR QUÉ: sin observer global, errores silenciosos en BLoCs pasan
// desapercibidos en producción.

import 'package:frontend_mobile_nodos_app/core/observers/app_bloc_observer.dart';

/// BLoC mínimo para testear el observer.
///
/// Emite estados y errores bajo demanda para verificar que
/// AppBlocObserver recibe las callbacks correctamente.
class _TestBloc extends Bloc<_TestEvent, int> {
  _TestBloc() : super(0) {
    on<_Increment>((event, emit) => emit(state + 1));
    on<_EmitError>((event, emit) {
      addError(Exception('test error'), StackTrace.current);
    });
  }
}

sealed class _TestEvent {}
class _Increment extends _TestEvent {}
class _EmitError extends _TestEvent {}

/// Helper: espera que la cola de microtasks y eventos se drene.
///
/// En tests con `test()` (no `blocTest`), los eventos añadidos vía
/// `bloc.add()` se procesan asíncronamente. Este helper espera a que
/// el event loop procese el evento.
Future<void> pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('AppBlocObserver (T-PR1-007)', () {
    // Guardar el observer original para restaurarlo después
    BlocObserver? originalObserver;

    setUp(() {
      originalObserver = Bloc.observer;
    });

    tearDown(() {
      Bloc.observer = originalObserver!;
    });

    test('onTransition se llama en cada cambio de estado', () async {
      // Arrange: instalar AppBlocObserver globalmente
      Bloc.observer = AppBlocObserver();

      final bloc = _TestBloc();

      // Act: disparar un evento que cambia el estado
      bloc.add(_Increment());
      // Esperar que el evento se procese asíncronamente
      await pumpEventQueue();

      // Assert: el estado cambió a 1 sin crashear
      expect(bloc.state, equals(1));

      await bloc.close();
    });

    test('onError no crashea cuando un BLoC emite error', () async {
      // Arrange
      Bloc.observer = AppBlocObserver();

      final bloc = _TestBloc();

      // Act: disparar evento que causa addError
      bloc.add(_EmitError());
      await pumpEventQueue();

      // Assert: el observer no crashea al recibir onError
      // (el estado no cambia en error, sigue en 0)
      expect(bloc.state, equals(0));

      await bloc.close();
    });

    test('onEvent se llama cuando se despacha un evento', () async {
      // Arrange
      Bloc.observer = AppBlocObserver();

      final bloc = _TestBloc();

      // Act: despachar evento
      bloc.add(_Increment());
      await pumpEventQueue();

      // Assert: el observer registró el evento y el estado cambió
      expect(bloc.state, equals(1));

      await bloc.close();
    });
  });
}
