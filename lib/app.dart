import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_mobile_nodos_app/core/di/injection_container.dart';
import 'package:frontend_mobile_nodos_app/core/theme/app_theme.dart';
import 'package:frontend_mobile_nodos_app/core/utils/app_theme_mode.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/home_page.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/node_detail_page.dart';
import 'package:frontend_mobile_nodos_app/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/pages/settings_page.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/bloc/history_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/pages/history_tab.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/pages/stats_tab.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/presentation/bloc/scan_session_bloc.dart';

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
    final bleBloc = context.read<BleBloc>();

    /// Escucha el UserBloc para iniciar advertising cuando el perfil
    /// del usuario esté cargado (uuid, name, color).
    ///
    /// QUÉ hace: cuando UserBloc emite [UserLoaded], despacha
    /// [StartAdvertise] al BleBloc con los metadatos de identidad.
    /// Solo se dispara una vez por perfil (cada UserLoaded).
    ///
    /// POR QUÉ: sin este listener el dispositivo nunca anuncia el UUID
    /// Nodos, por lo que otros dispositivos no pueden detectarlo.
    return BlocListener<UserBloc, UserState>(
      listener: (context, userState) {
        if (userState is UserLoaded) {
          bleBloc.add(StartAdvertise(
            userState.user.uuid,
            userState.user.name,
            userState.user.color,
          ));
        }
      },
      child: Scaffold(
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
        // ScanSessionBloc: gestiona el ciclo de vida de sesiones de escaneo.
        BlocProvider<ScanSessionBloc>(create: (_) => sl<ScanSessionBloc>()),
      ],
      child: const _NodosAppBody(),
    );
  }
}

/// Widget interno que vive dentro del árbol de [MultiBlocProvider].
///
/// QUÉ: despacha [LoadProfile] al [UserBloc] en startup para garantizar
/// que el perfil del usuario esté cargado ANTES de que cualquier pantalla
/// intente operaciones dependientes del perfil (BLE advertising, grafo, etc.).
///
/// POR QUÉ: antes LoadProfile solo se despachaba en SettingsPage.initState,
/// dejando la app en UserInitial o UserError indefinidamente si el usuario
/// nunca abría Settings. Esto causaba que el self-node nunca se marcara
/// (myDeviceUuid era null) y que BLE advertising no se iniciara.
///
/// El [addPostFrameCallback] asegura que el [UserBloc] ya fue creado
/// por [BlocProvider] antes de despachar el evento.
class _NodosAppBody extends StatefulWidget {
  const _NodosAppBody();

  @override
  State<_NodosAppBody> createState() => _NodosAppBodyState();
}

class _NodosAppBodyState extends State<_NodosAppBody> {
  @override
  void initState() {
    super.initState();
    // Despachar LoadProfile en el primer frame para que el UserBloc
    // cargue (o cree) el perfil antes de cualquier operación.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<UserBloc>().add(const LoadProfile());
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserBloc, UserState>(
      builder: (context, state) {
        // Lee el themeMode del estado del UserBloc y mapea
        // AppThemeMode (dominio) → ThemeMode (Flutter Material).
        final appThemeMode = (state is UserLoaded)
            ? state.themeMode
            : AppThemeMode.system;

        final themeMode = switch (appThemeMode) {
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
          AppThemeMode.system => ThemeMode.system,
        };

        return MaterialApp.router(
          title: 'Nodos',
          theme: AppTheme.light,
          // Tema oscuro: misma semilla de color, solo cambia el brillo.
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          routerConfig: _router,
        );
      },
    );
  }
}

/// Router principal con redirect guard de onboarding.
///
/// QUÉ: si el flag `onboarding_complete` en SharedPreferences es false
/// o no existe, redirige a `/onboarding`. Si es true y el usuario está
/// en `/onboarding`, redirige a `/` (HomePage).
///
/// POR QUÉ: el onboarding solo debe verse una vez en la primera
/// ejecución de la app. Después de configurar perfil, nunca más.
final _router = GoRouter(
  initialLocation: '/onboarding',
  redirect: (context, state) async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
    final isOnboarding = state.matchedLocation == '/onboarding';

    // Si ya completó onboarding y está en /onboarding → ir a Home.
    if (onboardingComplete && isOnboarding) return '/';
    // Si no completó onboarding y no está en /onboarding → forzar onboarding.
    if (!onboardingComplete && !isOnboarding) return '/onboarding';
    // Si está donde debe estar, no redirigir.
    return null;
  },
  routes: [
    // PR3: Ruta de onboarding — primera ejecución.
    GoRoute(
      path: '/onboarding',
      builder: (_, _) => const OnboardingPage(),
    ),
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
