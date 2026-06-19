import 'package:flutter/material.dart';

/// Nodos brand theme — Material 3 light theme.
///
/// Uses ColorScheme.fromSeed with a Nodos blue primary seed color.
class AppTheme {
  AppTheme._();

  static const Color _primarySeed = Color(0xFF2196F3); // Material Blue

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primarySeed,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
        ),
      );
}
