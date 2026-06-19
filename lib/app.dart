import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:frontend_mobile_nodos_app/core/di/injection_container.dart';
import 'package:frontend_mobile_nodos_app/core/theme/app_theme.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/home_page.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/node_detail_page.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/pages/settings_page.dart';

class NodosApp extends StatelessWidget {
  const NodosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<BleBloc>(create: (_) => sl<BleBloc>()),
        BlocProvider<NodeListBloc>(create: (_) => sl<NodeListBloc>()),
        BlocProvider<UserBloc>(create: (_) => sl<UserBloc>()),
      ],
      child: MaterialApp.router(
        title: 'Nodos',
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const HomePage(),
    ),
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
