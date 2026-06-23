import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/app_theme_mode.dart';

/// Tests para el enum AppThemeMode y su método fromString.
///
/// QUÉ: verifica que el enum de dominio no dependa de Flutter
/// (ThemeMode de material.dart) y que la conversión desde strings
/// sea robusta (case-insensitive, fallback a system).
///
/// POR QUÉ: AD-31 — el dominio NO debe acoplarse a Flutter.
/// AppThemeMode reemplaza ThemeMode en la capa de dominio/presentación,
/// y solo se mapea a ThemeMode en el boundary de MaterialApp (app.dart).
void main() {
  group('AppThemeMode', () {
    // ─── Valores del enum ─────────────────────────────────────
    test('AppThemeMode.light tiene name "light"', () {
      expect(AppThemeMode.light.name, 'light');
    });

    test('AppThemeMode.dark tiene name "dark"', () {
      expect(AppThemeMode.dark.name, 'dark');
    });

    test('AppThemeMode.system tiene name "system"', () {
      expect(AppThemeMode.system.name, 'system');
    });

    test('AppThemeMode.values tiene exactamente 3 elementos', () {
      expect(AppThemeMode.values.length, 3);
    });

    // ─── fromString — conversión exacta ───────────────────────
    test('fromString("light") retorna AppThemeMode.light', () {
      expect(AppThemeMode.fromString('light'), AppThemeMode.light);
    });

    test('fromString("dark") retorna AppThemeMode.dark', () {
      expect(AppThemeMode.fromString('dark'), AppThemeMode.dark);
    });

    test('fromString("system") retorna AppThemeMode.system', () {
      expect(AppThemeMode.fromString('system'), AppThemeMode.system);
    });

    // ─── fromString — case-insensitive ────────────────────────
    test('fromString es case-insensitive: "Light" → light', () {
      expect(AppThemeMode.fromString('Light'), AppThemeMode.light);
    });

    test('fromString es case-insensitive: "DARK" → dark', () {
      expect(AppThemeMode.fromString('DARK'), AppThemeMode.dark);
    });

    // ─── fromString — fallback ────────────────────────────────
    test('fromString con string inválido retorna AppThemeMode.system (default)', () {
      expect(AppThemeMode.fromString('invalid'), AppThemeMode.system);
    });
  });
}
