import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:frontend_mobile_nodos_app/core/di/injection_container.dart';
import 'package:frontend_mobile_nodos_app/core/theme/app_theme.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/home_page.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/node_detail_page.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/pages/settings_page.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/bloc/history_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/pages/history_tab.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/pages/stats_tab.dart';

/// Scaffold con BottomNavigationBar de 3 tabs usando StatefulShellRoute.
///
/// QUÉ: envuelve el [StatefulNavigationShell] de GoRouter en un Scaffold
/// con BottomNavigationBar para navegación entre Home, Historial y Stats.
///
/// T2.5: Controla el ciclo de vida del escaneo BLE según la tab activa.
/// Al entrar en Home (índice 0) → StartScan. Al salir de Home → StopScan.
///
/// POR QUÉ: StatefulShellRoute.indexedStack preserva el estado de cada tab
/// mediante IndexedStack, evitando que los BLoCs se destruyan al cambiar
/// de pestaña. Pero el escaneo continuo en Home drenaría batería si no
/// se pausa al cambiar a otras tabs.
class ScaffoldWithNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    // T2.5: Acceder al BleBloc para controlar el escaneo por tab.
    // Se captura en build() porque onTap es un callback sin context propio.
    final bleBloc = context.read<BleBloc>();

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) {
          // T2.5: Auto-scan lifecycle por tab
          // Si el usuario entra a Home (índice 0), inicia el escaneo.
          // Si sale de Home (currentIndex era 0), detiene el escaneo.
          if (index == 0) {
            bleBloc.add(const StartScan());
          } else if (navigationShell.currentIndex == 0) {
            bleBloc.add(const StopScan());
          }

          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Historial',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}

class NodosApp extends StatelessWidget {
  const NodosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<BleBloc>(create: (_) => sl<BleBloc>()),
        BlocProvider<NodeListBloc>(create: (_) => sl<NodeListBloc>()),
        BlocProvider<UserBloc>(create: (_) => sl<UserBloc>()),
        // BleConnectionBloc: gestiona conexiones GATT punto a punto (Enlazar).
        BlocProvider<BleConnectionBloc>(
          create: (_) => sl<BleConnectionBloc>(),
        ),
        // VisualizationBloc: construye y posiciona el grafo de nodos
        // cuando hay 5+ dispositivos BLE detectados.
        BlocProvider<VisualizationBloc>(
          create: (_) => sl<VisualizationBloc>(),
        ),
        // HistoryBloc: orquesta el historial de sesiones y estadísticas.
        // Compartido entre HistoryTab y StatsTab via BlocProvider.
        BlocProvider<HistoryBloc>(create: (_) => sl<HistoryBloc>()),
      ],
      child: BlocBuilder<UserBloc, UserState>(
        builder: (context, state) {
          // Lee el themeMode del estado del UserBloc.
          // Si el perfil aún no cargó, usa system como fallback.
          final themeMode = (state is UserLoaded)
              ? state.themeMode
              : ThemeMode.system;

          return MaterialApp.router(
            title: 'Nodos',
            theme: AppTheme.light,
            // Tema oscuro: misma semilla de color, solo cambia el brillo.
            darkTheme: AppTheme.dark,
            themeMode: themeMode,
            routerConfig: _router,
          );
        },
      ),
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    // T1.9: BottomNavigationBar con 3 tabs usando IndexedStack.
    // Cada tab preserva su estado al cambiar entre ellas.
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          ScaffoldWithNavBar(navigationShell: navigationShell),
      branches: [
        // Tab 0: Home — escaneo BLE y lista/grafo de nodos.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const HomePage(),
            ),
          ],
        ),
        // Tab 1: Historial — sesiones pasadas y filtros.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/history',
              builder: (_, _) => const HistoryTab(),
            ),
          ],
        ),
        // Tab 2: Stats — estadísticas agregadas.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/stats',
              builder: (_, _) => const StatsTab(),
            ),
          ],
        ),
      ],
    ),
    // Rutas accesibles desde cualquier tab (no forman parte del shell).
    GoRoute(
      path: '/node/:id',
      builder: (_, state) => NodeDetailPage(
        id: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => const SettingsPage(),
    ),
  ],
);
