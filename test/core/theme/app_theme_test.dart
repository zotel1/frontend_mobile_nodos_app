import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    // ─── Tema claro ──────────────────────────────────────────────
    group('light', () {
      test('brightness is light', () {
        expect(AppTheme.light.brightness, Brightness.light);
      });

      test('uses Material 3', () {
        expect(AppTheme.light.useMaterial3, isTrue);
      });

      test('colorScheme brightness is light', () {
        expect(AppTheme.light.colorScheme.brightness, Brightness.light);
      });
    });

    // ─── Tema oscuro ─────────────────────────────────────────────
    // NOTA: AppTheme.dark no existe aún → este grupo fuerza RED.
    group('dark', () {
      test('brightness is dark', () {
        // QUÉ: verifica que el tema oscuro tenga Brightness.dark
        // POR QUÉ: el sistema operativo alterna automáticamente
        //   entre claro/oscuro, la app debe reflejarlo
        expect(AppTheme.dark.brightness, Brightness.dark);
      });

      test('colorScheme brightness is dark', () {
        expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
      });

      test('uses Material 3', () {
        // QUÉ: ambos temas deben usar Material 3
        // POR QUÉ: consistencia visual entre modos
        expect(AppTheme.dark.useMaterial3, isTrue);
      });

      test('uses same seed color as light theme', () {
        // QUÉ: el tema oscuro usa la misma semilla de color primario
        // POR QUÉ: mantiene la identidad visual de Nodos (blue 500)
        //   en ambos modos. Solo cambia el brillo del esquema.
        // Verificamos que ambos ColorSchemes deriven de la misma
        // semilla comprobando que el primary es de la familia blue
        final lightPrimary = AppTheme.light.colorScheme.primary;
        final darkPrimary = AppTheme.dark.colorScheme.primary;

        // Ambos deben ser azules (el valor exacto varía con brightness
        // porque fromSeed adapta la paleta, pero deben ser tonos de azul)
        // Verificamos que el canal azul domina sobre rojo y verde
        // Usamos los getters .b/.r/.g (doubles 0.0–1.0) en lugar de
        // los deprecados .blue/.red/.green (int 0–255).
        expect(darkPrimary.b, greaterThan(darkPrimary.r));
        expect(darkPrimary.b, greaterThan(darkPrimary.g));

        // Y que ambas variantes comparten la misma familia de color
        // (ambos tienen el canal azul como dominante)
        expect(lightPrimary.b, greaterThan(lightPrimary.r));
        expect(lightPrimary.b, greaterThan(lightPrimary.g));
      });
    });
  });
}
