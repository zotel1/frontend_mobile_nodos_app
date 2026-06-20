import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';

void main() {
  group('GraphNode', () {
    test('supports equality by id, x, y, proximity', () {
      final node1 = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
      );

      final node2 = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
      );

      expect(node1, equals(node2));
    });

    test('supports inequality when id differs', () {
      final node1 = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
      );
      final node2 = GraphNode(
        id: 2,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
      );

      expect(node1, isNot(equals(node2)));
    });

    test('supports inequality when position differs', () {
      final node1 = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
      );
      final node2 = GraphNode(
        id: 1,
        x: 300.0,
        y: 400.0,
        proximity: ProximityLevel.close,
      );

      expect(node1, isNot(equals(node2)));
    });

    test('supports inequality when proximity differs', () {
      final node1 = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
      );
      final node2 = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.far,
      );

      expect(node1, isNot(equals(node2)));
    });

    // T2.1: radio ahora basado en connectionCount, no en proximity.
    test('radio por defecto es 12px con connectionCount=0', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
      );
      // Sin connectionCount explícito → usa default 0 → radius=12
      expect(node.radius, 12.0);
    });

    test('color is derived from proximity', () {
      final closeNode = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
      );
      final mediumNode = GraphNode(
        id: 2,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.medium,
      );
      final farNode = GraphNode(
        id: 3,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.far,
      );

      expect(closeNode.color, const Color(0xFF4CAF50));
      expect(mediumNode.color, const Color(0xFFFFC107));
      expect(farNode.color, const Color(0xFFF44336));
    });

    test('label returns default when no name', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
      );

      expect(node.label, 'Desconocido');
    });

    test('label returns name when provided', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
        name: 'Mi Dispositivo',
      );

      expect(node.label, 'Mi Dispositivo');
    });

    // ─── T1.8: label con suggestedName ─────────────────────────
    // QUÉ: label ahora usa name ?? suggestedName ?? 'Desconocido'
    // POR QUÉ: Phase 4 identity enrichment — si el usuario no asignó
    // nombre, se muestra el nombre sugerido del advertisement BLE.

    test('label usa suggestedName cuando name es null', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
        suggestedName: 'AirPods Pro',
      );
      expect(node.label, 'AirPods Pro');
    });

    test('label prefiere name sobre suggestedName', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
        name: 'Mis auris',
        suggestedName: 'AirPods Pro',
      );
      expect(node.label, 'Mis auris');
    });

    test('label usa Desconocido cuando ambos son null', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
      );
      expect(node.label, 'Desconocido');
    });

    test('props list contains correct fields', () {
      final node = GraphNode(
        id: 5,
        x: 150.0,
        y: 250.0,
        proximity: ProximityLevel.medium,
        name: 'Test',
      );

      // T3.10: props incluyen connectable
      expect(node.props,
          [5, 150.0, 250.0, ProximityLevel.medium, 'Test', null, 0, false, true]);
    });

    test('isKnown returns true when node has a name', () {
      final node = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        name: 'Mi Nodo',
      );

      expect(node.isKnown, isTrue);
    });

    test('isKnown returns false when node has no name', () {
      final node = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
      );

      expect(node.isKnown, isFalse);
    });

    test('isKnown returns false when name is explicitly null', () {
      final node = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        name: null,
      );

      expect(node.isKnown, isFalse);
    });

    test('nodes with same position and same name are equal', () {
      final nodeA = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        name: 'Nodo A',
      );
      final nodeB = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        name: 'Nodo A',
      );

      expect(nodeA, equals(nodeB));
    });

    test('nodes with same position but different names are not equal', () {
      final nodeA = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        name: 'Nodo A',
      );
      final nodeB = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        name: 'Nodo B',
      );

      // BUG fix: dos nodos con distinto nombre NO deben ser iguales.
      // Antes del fix, name no estaba en props y eran considerados iguales.
      expect(nodeA, isNot(equals(nodeB)));
    });

    // ─── T2.1: connectionCount, isSelf, nuevo radius ─────────────
    // QUÉ: radio ahora basado en connectionCount en vez de proximity.
    // Fórmula: (12 + degree*3).clamp(12, 50)
    // POR QUÉ: LinkedIn Maps style — nodos con más conexiones son más grandes.

    test('radius es 12px cuando connectionCount=0', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
        connectionCount: 0,
      );
      expect(node.radius, 12.0);
    });

    test('radius es 27px con 5 conexiones', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.far,
        connectionCount: 5,
      );
      expect(node.radius, 27.0);
    });

    test('radius se clampéa a 50px máximo con 20 conexiones', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.medium,
        connectionCount: 20,
      );
      expect(node.radius, 50.0);
    });

    test('radius se clampéa a 12px mínimo con 0 conexiones', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
        connectionCount: 0,
      );
      expect(node.radius, 12.0);
    });

    test('radius=15px con 1 conexión', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
        connectionCount: 1,
      );
      expect(node.radius, 15.0);
    });

    test('radius=18px con 2 conexiones', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
        connectionCount: 2,
      );
      expect(node.radius, 18.0);
    });

    test('isSelf es false por defecto', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
      );
      expect(node.isSelf, isFalse);
    });

    test('isSelf es true cuando se especifica', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
        isSelf: true,
      );
      expect(node.isSelf, isTrue);
    });

    test('connectionCount es 0 por defecto', () {
      final node = GraphNode(
        id: 1,
        x: 0.0,
        y: 0.0,
        proximity: ProximityLevel.close,
      );
      expect(node.connectionCount, 0);
    });

    test('connectionCount y isSelf están en props para equality', () {
      final nodeA = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        connectionCount: 3,
        isSelf: true,
      );
      final nodeB = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        connectionCount: 3,
        isSelf: true,
      );
      final nodeC = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        connectionCount: 5, // distinto
        isSelf: true,
      );
      final nodeD = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        connectionCount: 3,
        isSelf: false, // distinto
      );

      expect(nodeA, equals(nodeB));
      expect(nodeA, isNot(equals(nodeC)));
      expect(nodeA, isNot(equals(nodeD)));
    });
  });
}
