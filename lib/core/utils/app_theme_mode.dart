/// Modo de tema de la aplicación (dominio, sin dependencia de Flutter).
///
/// Reemplaza [ThemeMode] de `package:flutter/material.dart` en la capa
/// de dominio y presentación. Solo se mapea a [ThemeMode] en el boundary
/// de `MaterialApp` (app.dart).
///
/// QUÉ problema resuelve: AD-31 — el dominio NO debe importar Flutter.
/// Al usar este enum propio, UserBloc y SettingsPage no necesitan
/// `import 'package:flutter/material.dart'` solo para referenciar ThemeMode.
///
/// [fromString] permite reconstruir el enum desde el string persistido
/// en SharedPreferences (case-insensitive, fallback a system).
enum AppThemeMode {
  /// Usa el tema claro forzado.
  light,

  /// Usa el tema oscuro forzado.
  dark,

  /// Sigue la configuración del sistema operativo.
  system;

  /// Convierte un string (ej. de SharedPreferences) a [AppThemeMode].
  ///
  /// Case-insensitive: 'Light', 'LIGHT', 'light' → [AppThemeMode.light].
  /// Si el string no coincide con ningún valor, retorna [AppThemeMode.system]
  /// como fallback seguro (por defecto, sigue al SO).
  static AppThemeMode fromString(String value) {
    return switch (value.toLowerCase()) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      'system' => AppThemeMode.system,
      _ => AppThemeMode.system,
    };
  }
}
