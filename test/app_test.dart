import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:get_it/get_it.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';

import 'package:frontend_mobile_nodos_app/app.dart';

@GenerateNiceMocks([
  MockSpec<BleBloc>(),
  MockSpec<NodeListBloc>(),
  MockSpec<UserBloc>(),
  MockSpec<VisualizationBloc>(),
])
import 'app_test.mocks.dart';

void main() {
  late MockBleBloc mockBleBloc;
  late MockNodeListBloc mockNodeListBloc;
  late MockUserBloc mockUserBloc;
  late MockVisualizationBloc mockVizBloc;
  late AppDatabase testDb;

  setUp(() async {
    mockBleBloc = MockBleBloc();
    mockNodeListBloc = MockNodeListBloc();
    mockUserBloc = MockUserBloc();
    mockVizBloc = MockVisualizationBloc();

    // Configurar mocks para evitar crashes
    when(mockBleBloc.state).thenReturn(const BleStopped());
    when(mockBleBloc.stream)
        .thenAnswer((_) => Stream.value(const BleStopped()));
    when(mockNodeListBloc.state).thenReturn(const NodeListInitial());
    when(mockNodeListBloc.stream)
        .thenAnswer((_) => Stream.value(const NodeListInitial()));
    when(mockUserBloc.state).thenReturn(const UserInitial());
    when(mockUserBloc.stream)
        .thenAnswer((_) => Stream.value(const UserInitial()));
    when(mockVizBloc.state).thenReturn(const VisualizationInitial());
    when(mockVizBloc.stream)
        .thenAnswer((_) => Stream.value(const VisualizationInitial()));

    // Registrar mocks en GetIt para que NodosApp los resuelva.
    if (!GetIt.instance.isRegistered<BleBloc>()) {
      GetIt.instance.registerFactory<BleBloc>(() => mockBleBloc);
    }
    if (!GetIt.instance.isRegistered<NodeListBloc>()) {
      GetIt.instance.registerFactory<NodeListBloc>(() => mockNodeListBloc);
    }
    if (!GetIt.instance.isRegistered<UserBloc>()) {
      GetIt.instance.registerFactory<UserBloc>(() => mockUserBloc);
    }
    if (!GetIt.instance.isRegistered<VisualizationBloc>()) {
      GetIt.instance.registerFactory<VisualizationBloc>(() => mockVizBloc);
    }

    testDb = AppDatabase.inMemory();
    if (!GetIt.instance.isRegistered<AppDatabase>()) {
      GetIt.instance.registerSingleton<AppDatabase>(testDb);
    }
  });

  tearDown(() async {
    await testDb.close();
    // Limpiar registros de GetIt
    if (GetIt.instance.isRegistered<AppDatabase>()) {
      GetIt.instance.unregister<AppDatabase>();
    }
    if (GetIt.instance.isRegistered<BleBloc>()) {
      GetIt.instance.unregister<BleBloc>();
    }
    if (GetIt.instance.isRegistered<NodeListBloc>()) {
      GetIt.instance.unregister<NodeListBloc>();
    }
    if (GetIt.instance.isRegistered<UserBloc>()) {
      GetIt.instance.unregister<UserBloc>();
    }
    if (GetIt.instance.isRegistered<VisualizationBloc>()) {
      GetIt.instance.unregister<VisualizationBloc>();
    }
  });

  /// Helper que construye NodosApp con BLoCs mockeados via GetIt.
  Widget buildApp() {
    return const NodosApp();
  }

  group('NodosApp BottomNavigationBar', () {
    // T1.9: Verifica que el BottomNavigationBar tiene 3 tabs
    // (Home, Historial, Stats) y StatefulShellRoute está activo.
    testWidgets('has BottomNavigationBar with 3 tabs', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // Debe existir un BottomNavigationBar con 3 items
      expect(find.byType(BottomNavigationBar), findsOneWidget);

      // Verifica los 3 íconos de los tabs
      expect(find.byIcon(Icons.home), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    });

    // T1.10: El tab Home (índice 0) muestra contenido de HomePage.
    // Como HomePage está presente en el IndexedStack, debe mostrar
    // "Buscando nodos cercanos..." (estado NodeListInitial).
    testWidgets('Home tab shows HomePage content', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // La HomePage debería estar visible con su contenido.
      // NodeListInitial → "Buscando nodos cercanos..."
      expect(find.text('Buscando nodos cercanos...'), findsOneWidget);
    });

    // T1.10: Los tabs Historial y Stats muestran placeholder.
    testWidgets('Historial tab shows placeholder text', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // Navegar a la tab Historial (índice 1)
      await tester.tap(find.byIcon(Icons.history));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Próximamente...'), findsOneWidget);
    });

    testWidgets('Stats tab shows placeholder text', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // Navegar a la tab Stats (índice 2)
      await tester.tap(find.byIcon(Icons.bar_chart));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Próximamente...'), findsOneWidget);
    });
  });
}
