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

  /// Tema oscuro adaptativo al sistema.
  ///
  /// Usa la misma semilla [Color(0xFF2196F3)] que el tema claro
  /// para mantener la identidad visual Nodos.
  /// Solo cambia [Brightness.dark] para fondos oscuros y texto claro.
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primarySeed,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(centerTitle: true),
      );
}
