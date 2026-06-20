import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';

void main() {
  final now = DateTime(2026, 6, 18, 12, 0, 0);

  group('Node', () {
    test('supports equality by all props', () {
      final node1 = Node(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Test Node',
        color: '#2196F3',
        firstSeen: now,
        lastSeen: now,
        rssiHistory: const [-55, -60],
      );

      final node2 = Node(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Test Node',
        color: '#2196F3',
        firstSeen: now,
        lastSeen: now,
        rssiHistory: const [-55, -60],
      );

      expect(node1, equals(node2));
    });

    test('supports inequality when props differ', () {
      final node1 = Node(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Test Node',
        color: '#2196F3',
        firstSeen: now,
        lastSeen: now,
        rssiHistory: const [-55],
      );

      final node2 = Node(
        id: 2, // different id
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Test Node',
        color: '#2196F3',
        firstSeen: now,
        lastSeen: now,
        rssiHistory: const [-55],
      );

      expect(node1, isNot(equals(node2)));
    });

    test('isKnown returns true when name is present', () {
      final node = Node(
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Known Node',
        firstSeen: now,
        lastSeen: now,
      );

      expect(node.isKnown, isTrue);
    });

    test('isKnown returns false when name is null', () {
      final node = Node(
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        firstSeen: now,
        lastSeen: now,
      );

      expect(node.isKnown, isFalse);
    });

    test('isKnown returns false for name=null unknown nodes', () {
      final node = Node(
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: null,
        firstSeen: now,
        lastSeen: now,
      );

      expect(node.isKnown, isFalse);
    });

    test('supports null id (unsaved node)', () {
      final node = Node(
        id: null,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Unsaved',
        color: '#808080',
        firstSeen: now,
        lastSeen: now,
        rssiHistory: const [],
      );

      expect(node.id, isNull);
      expect(node.isKnown, isTrue);
    });

    test('props list contains all fields', () {
      final node = Node(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Node',
        color: '#FF0000',
        firstSeen: now,
        lastSeen: now,
        rssiHistory: const [-55, -70],
      );

      expect(node.props.length, 9); // +2: suggestedName, deviceType
      expect(node.props, containsAll([
        1,
        'AA:BB:CC:DD:EE:FF',
        'Node',
        '#FF0000',
        now,
        now,
        [-55, -70],
        null, // suggestedName
        null, // deviceType
      ]));
    });

    // ─── T1.5: suggestedName y deviceType ───────────────────────
    // QUÉ: Node ahora almacena suggestedName (nombre sugerido por
    // advertisement BLE) y deviceType (clasificación del dispositivo).
    // POR QUÉ: enriquece la identidad visual sin requerir que el usuario
    // asigne nombre manualmente (Phase 4 identity enrichment).

    test('suggestedName es null por defecto (backward-compatible)', () {
      final node = Node(
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        firstSeen: now,
        lastSeen: now,
      );
      expect(node.suggestedName, isNull);
    });

    test('suggestedName almacena el nombre sugerido desde advName', () {
      final node = Node(
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: null,
        suggestedName: 'AirPods Pro',
        firstSeen: now,
        lastSeen: now,
      );
      expect(node.suggestedName, 'AirPods Pro');
    });

    test('deviceType es null por defecto', () {
      final node = Node(
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        firstSeen: now,
        lastSeen: now,
      );
      expect(node.deviceType, isNull);
    });

    test('deviceType almacena el tipo clasificado', () {
      final node = Node(
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        deviceType: 'Reloj/Fitness',
        firstSeen: now,
        lastSeen: now,
      );
      expect(node.deviceType, 'Reloj/Fitness');
    });

    test('dos nodos con diferentes suggestedName no son iguales', () {
      final node1 = Node(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        suggestedName: 'Device A',
        firstSeen: now,
        lastSeen: now,
      );
      final node2 = Node(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        suggestedName: 'Device B',
        firstSeen: now,
        lastSeen: now,
      );
      expect(node1, isNot(equals(node2)));
    });

    test('dos nodos con diferentes deviceType no son iguales', () {
      final node1 = Node(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        deviceType: 'Reloj',
        firstSeen: now,
        lastSeen: now,
      );
      final node2 = Node(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        deviceType: 'Auriculares',
        firstSeen: now,
        lastSeen: now,
      );
      expect(node1, isNot(equals(node2)));
    });
  });
}
