import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/device_classifier.dart';

/// Tests unitarios para DeviceClassifier.
///
/// QUÉ: Verifica que la clasificación por service UUIDs y manufacturer ID
/// produce las categorías correctas según la especificación de Phase 4.
///
/// POR QUÉ: DeviceClassifier es una utilidad estática pura (0 estado,
/// 0 dependencias), ideal para test unitario sin mocks.
void main() {
  group('DeviceClassifier.classify — por service UUIDs', () {
    test('S3.1: Heart Rate (0x180D) → "Reloj/Fitness"', () {
      // El GUID completo para 0x180D es 0000180d-0000-1000-8000-00805f9b34fb
      final type = DeviceClassifier.classify([
        '0000180d-0000-1000-8000-00805f9b34fb',
      ], null);
      expect(type, 'Reloj/Fitness');
    });

    test('Heart Rate + Battery → "Reloj/Fitness" (prioridad HR)', () {
      final type = DeviceClassifier.classify([
        '0000180d-0000-1000-8000-00805f9b34fb',
        '0000180f-0000-1000-8000-00805f9b34fb',
      ], null);
      expect(type, 'Reloj/Fitness');
    });

    test('Battery (0x180F) → "Batería"', () {
      final type = DeviceClassifier.classify([
        '0000180f-0000-1000-8000-00805f9b34fb',
      ], null);
      expect(type, 'Batería');
    });

    test('Keyboard (0x1812) → "Teclado"', () {
      final type = DeviceClassifier.classify([
        '00001812-0000-1000-8000-00805f9b34fb',
      ], null);
      expect(type, 'Teclado');
    });

    test('Device Info (0x180A) → "Dispositivo"', () {
      final type = DeviceClassifier.classify([
        '0000180a-0000-1000-8000-00805f9b34fb',
      ], null);
      expect(type, 'Dispositivo');
    });

    test('Generic Access (0x1800) → "Genérico"', () {
      final type = DeviceClassifier.classify([
        '00001800-0000-1000-8000-00805f9b34fb',
      ], null);
      expect(type, 'Genérico');
    });

    test('Nodos UUID → "Nodo" con prioridad máxima', () {
      final type = DeviceClassifier.classify([
        '0000180a-0000-1000-8000-00805f9b34fb', // Device Info
        '4fafc201-1fb5-459e-8fcc-c5c9c331914b', // Nodos UUID
      ], null);
      expect(type, 'Nodo');
    });

    test('Nodos UUID solo → "Nodo"', () {
      final type = DeviceClassifier.classify([
        '4fafc201-1fb5-459e-8fcc-c5c9c331914b',
      ], null);
      expect(type, 'Nodo');
    });
  });

  group('DeviceClassifier.classify — por manufacturer ID', () {
    test('Apple (0x004C) → "Apple (Desconocido)" cuando no hay services', () {
      final type = DeviceClassifier.classify([], 0x004C);
      expect(type, 'Apple (Desconocido)');
    });

    test('Samsung (0x0075) → "Samsung (Desconocido)"', () {
      final type = DeviceClassifier.classify([], 0x0075);
      expect(type, 'Samsung (Desconocido)');
    });

    test('Google (0x00E0) → "Google (Desconocido)"', () {
      final type = DeviceClassifier.classify([], 0x00E0);
      expect(type, 'Google (Desconocido)');
    });
  });

  group('DeviceClassifier.classify — service + manufacturer combinados', () {
    test('S3.2: Apple manufacturer + no services → "Apple (Desconocido)"', () {
      final type = DeviceClassifier.classify([], 0x004C);
      expect(type, 'Apple (Desconocido)');
    });

    test('Service tiene prioridad sobre manufacturer', () {
      final type = DeviceClassifier.classify([
        '0000180d-0000-1000-8000-00805f9b34fb', // Heart Rate
      ], 0x004C); // Apple
      expect(type, 'Reloj/Fitness');
    });
  });

  group('DeviceClassifier.classify — casos edge', () {
    test('Lista vacía + manufacturer null → null', () {
      final type = DeviceClassifier.classify([], null);
      expect(type, isNull);
    });

    test('UUID desconocido + manufacturer null → null', () {
      final type = DeviceClassifier.classify([
        '0000ffff-0000-1000-8000-00805f9b34fb',
      ], null);
      expect(type, isNull);
    });

    test('UUID desconocido + manufacturer conocido → marca sin categoría', () {
      final type = DeviceClassifier.classify([
        '0000ffff-0000-1000-8000-00805f9b34fb',
      ], 0x0075); // Samsung
      expect(type, 'Samsung (Desconocido)');
    });

    test('Nodos UUID prevalece sobre manufacturer y otros services', () {
      final type = DeviceClassifier.classify([
        '0000180d-0000-1000-8000-00805f9b34fb', // Heart Rate
        '4fafc201-1fb5-459e-8fcc-c5c9c331914b', // Nodos
      ], 0x004C); // Apple
      expect(type, 'Nodo');
    });

    // PR2: UUID Nodos detectado sin otros servicios — caso advertising real
    test('Nodos UUID único en lista de services → "Nodo" (advertising real)', () {
      final type = DeviceClassifier.classify([
        '4fafc201-1fb5-459e-8fcc-c5c9c331914b',
      ], null);
      expect(type, 'Nodo');
    });
  });
}
