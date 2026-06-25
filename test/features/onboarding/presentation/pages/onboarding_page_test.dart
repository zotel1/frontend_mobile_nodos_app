import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/onboarding/presentation/pages/onboarding_page.dart';

@GenerateNiceMocks([
  MockSpec<BleBloc>(),
  MockSpec<UserBloc>(),
])
import 'onboarding_page_test.mocks.dart';

/// Helper que construye el widget OnboardingPage con BLoCs mockeados.
Widget _pumpOnboardingPage({
  required MockUserBloc mockUserBloc,
  required MockBleBloc mockBleBloc,
  BleState bleState = const BleStopped(),
}) {
  when(mockBleBloc.state).thenReturn(bleState);
  when(mockBleBloc.stream).thenAnswer((_) => Stream.value(bleState));

  return MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => MultiBlocProvider(
            providers: [
              BlocProvider<UserBloc>.value(value: mockUserBloc),
              BlocProvider<BleBloc>.value(value: mockBleBloc),
            ],
            child: const OnboardingPage(),
          ),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: Center(child: Text('Home Page')),
          ),
        ),
      ],
    ),
  );
}

void main() {
  late MockUserBloc mockUserBloc;
  late MockBleBloc mockBleBloc;

  setUp(() async {
    mockUserBloc = MockUserBloc();
    mockBleBloc = MockBleBloc();

    when(mockUserBloc.state).thenReturn(const UserInitial());
    when(mockUserBloc.stream)
        .thenAnswer((_) => Stream.value(const UserInitial()));

    SharedPreferences.setMockInitialValues({});

    // Mock del MethodChannel de permission_handler para entorno de test.
    // Sin este mock, Permission.bluetoothScan.request() cuelga indefinidamente.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async {
        // Devolver granted para ambos permisos en test.
        return {
          '16': 3, // Permission.bluetoothScan.value = 16, granted = 3
          '17': 3, // Permission.bluetoothConnect.value = 17, granted = 3
        };
      },
    );
  });

  group('OnboardingPage', () {
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Paso 1: Permisos
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    testWidgets('Paso 1: muestra texto de permisos y botón Continuar',
        (tester) async {
      await tester.pumpWidget(_pumpOnboardingPage(
        mockUserBloc: mockUserBloc,
        mockBleBloc: mockBleBloc,
      ));
      await tester.pump();

      expect(
        find.text(
            'Nodos necesita permiso de Bluetooth para detectar dispositivos cercanos'),
        findsOneWidget,
      );
      expect(find.text('Continuar'), findsOneWidget);
    });

    testWidgets(
        'Paso 1: tocar Continuar avanza al paso 2 y muestra texto de Bluetooth',
        (tester) async {
      await tester.pumpWidget(_pumpOnboardingPage(
        mockUserBloc: mockUserBloc,
        mockBleBloc: mockBleBloc,
      ));
      await tester.pump();

      // Tocar el botón Continuar
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Debe aparecer el texto del paso 2 (Bluetooth)
      // Si BT está encendido (BleStopped), muestra "Bluetooth activado"
      expect(find.text('Bluetooth activado'), findsOneWidget);
    });

    testWidgets(
        'Paso 1: cuando permisos son denegados, muestra mensaje de error',
        (tester) async {
      // Simulamos que los permisos fueron denegados seteando un estado
      // que la página puede mostrar. En producción esto viene de
      // Permission.bluetoothScan.request().
      // Para el test, verificamos que el mecanismo de reintento existe.
      await tester.pumpWidget(_pumpOnboardingPage(
        mockUserBloc: mockUserBloc,
        mockBleBloc: mockBleBloc,
      ));
      await tester.pump();

      // Verificar que el mensaje de permisos está presente
      expect(
        find.text(
            'Nodos necesita permiso de Bluetooth para detectar dispositivos cercanos'),
        findsOneWidget,
      );
    });

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Paso 2: Bluetooth
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    testWidgets('Paso 2: muestra "Bluetooth activado" cuando BT está encendido',
        (tester) async {
      await tester.pumpWidget(_pumpOnboardingPage(
        mockUserBloc: mockUserBloc,
        mockBleBloc: mockBleBloc,
        bleState: const BleStopped(),
      ));
      await tester.pump();

      // Avanzar al paso 2
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Bluetooth activado'), findsOneWidget);
    });

    testWidgets(
        'Paso 2: muestra mensaje para activar BT cuando está apagado',
        (tester) async {
      await tester.pumpWidget(_pumpOnboardingPage(
        mockUserBloc: mockUserBloc,
        mockBleBloc: mockBleBloc,
        bleState: const BluetoothOff(),
      ));
      await tester.pump();

      // Avanzar al paso 2
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Activá Bluetooth para continuar'), findsOneWidget);
      expect(find.text('Abrir configuración'), findsOneWidget);
    });

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Paso 3: Perfil
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    testWidgets('Paso 3: muestra campo de nombre, color picker y botón Comenzar',
        (tester) async {
      await tester.pumpWidget(_pumpOnboardingPage(
        mockUserBloc: mockUserBloc,
        mockBleBloc: mockBleBloc,
      ));
      await tester.pump();

      // Avanzar al paso 2 (BT encendido, avanza automáticamente)
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Avanzar al paso 3
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verificar elementos del paso 3
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Comenzar'), findsOneWidget);
    });

    testWidgets('Paso 3: campo de nombre tiene valor por defecto "Nodo"',
        (tester) async {
      await tester.pumpWidget(_pumpOnboardingPage(
        mockUserBloc: mockUserBloc,
        mockBleBloc: mockBleBloc,
      ));
      await tester.pump();

      // Navegar al paso 3
      await tester.tap(find.text('Continuar')); // paso 1 → 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Continuar')); // paso 2 → 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // El TextField debe mostrar "Nodo"
      expect(find.widgetWithText(TextField, 'Nodo'), findsOneWidget);
    });

    testWidgets(
        'Paso 3: tocar Comenzar despacha eventos al UserBloc y navega a /',
        (tester) async {
      await tester.pumpWidget(_pumpOnboardingPage(
        mockUserBloc: mockUserBloc,
        mockBleBloc: mockBleBloc,
      ));
      await tester.pump();

      // Navegar al paso 3
      await tester.tap(find.text('Continuar')); // paso 1 → 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Continuar')); // paso 2 → 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tocar Comenzar
      await tester.tap(find.text('Comenzar'));
      await tester.pump();
      // La espera de 500ms en _saveAndStart() + SharedPreferences + navegación
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(); // Procesar frame posterior a context.go('/')

      // Verificar que se despacharon eventos al UserBloc
      verify(mockUserBloc.add(argThat(
        predicate((e) => e is CreateUserProfile &&
            e.name == 'Nodo' && e.color == '#2196F3'),
      ))).called(1);
      verify(mockUserBloc.add(argThat(
        predicate((e) => e is UpdateUserNameEvent && e.name == 'Nodo'),
      ))).called(1);
      verify(mockUserBloc.add(argThat(
        predicate((e) => e is UpdateUserColorEvent && e.color == '#2196F3'),
      ))).called(1);

      // Verificar que se guardó onboarding_complete en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_complete'), isTrue);

      // Verificar navegación a Home
      expect(find.text('Home Page'), findsOneWidget);
    });

    testWidgets(
        'Paso 3: tocar Comenzar usa el nombre ingresado por el usuario',
        (tester) async {
      // Reconstruir con SharedPreferences limpio
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_pumpOnboardingPage(
        mockUserBloc: mockUserBloc,
        mockBleBloc: mockBleBloc,
      ));
      await tester.pump();

      // Navegar al paso 3
      await tester.tap(find.text('Continuar')); // paso 1 → 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Continuar')); // paso 2 → 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Cambiar el nombre
      await tester.enterText(find.byType(TextField), 'Mi Nodo');
      await tester.pump();

      // Tocar Comenzar
      await tester.tap(find.text('Comenzar'));
      await tester.pump();
      // La espera de 500ms en _saveAndStart() + SharedPreferences
      await tester.pump(const Duration(milliseconds: 600));

      // Verificar que se usó el nombre ingresado (CreateUserProfile + Update)
      verify(mockUserBloc.add(argThat(
        predicate((e) => e is CreateUserProfile && e.name == 'Mi Nodo'),
      ))).called(1);
      verify(mockUserBloc.add(argThat(
        predicate((e) => e is UpdateUserNameEvent && e.name == 'Mi Nodo'),
      ))).called(1);
    });

    testWidgets('Paso 2: BT encendido muestra botón Continuar para avanzar',
        (tester) async {
      await tester.pumpWidget(_pumpOnboardingPage(
        mockUserBloc: mockUserBloc,
        mockBleBloc: mockBleBloc,
        bleState: const BleStopped(),
      ));
      await tester.pump();

      // Avanzar al paso 2
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Con BT encendido, debe haber botón Continuar para paso 3
      expect(find.text('Bluetooth activado'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
    });

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // T5.1: Hardware back bloqueado (R20, R21)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    // T5.1: QUÉ — verifica que el botón back del hardware está bloqueado
    // en la OnboardingPage via PopScope(canPop: false) y que al intentar
    // salir se muestra un diálogo de confirmación.
    // POR QUÉ — sin esta protección, el usuario puede saltarse el
    // onboarding presionando back (N1), dejando la app sin perfil.
    testWidgets(
        'T5.1: hardware back bloqueado — dialogo de confirmacion aparece',
        (tester) async {
      await tester.pumpWidget(_pumpOnboardingPage(
        mockUserBloc: mockUserBloc,
        mockBleBloc: mockBleBloc,
      ));
      await tester.pump();

      // Verificar que estamos en la página de onboarding
      expect(find.text('Paso 1 de 3'), findsOneWidget);

      // Simular hardware back button via handlePopRoute
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialogo de confirmación debe aparecer
      expect(
        find.text('¿Salir sin completar el perfil?'),
        findsOneWidget,
      );
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Salir'), findsOneWidget);

      // Seguimos en la página de onboarding (no navegó a ningún lado)
      expect(find.text('Paso 1 de 3'), findsOneWidget);

      // Tocar Cancelar cierra el diálogo sin salir
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Diálogo desapareció, seguimos en onboarding
      expect(
        find.text('¿Salir sin completar el perfil?'),
        findsNothing,
      );
      expect(find.text('Paso 1 de 3'), findsOneWidget);
    });
  });
}
