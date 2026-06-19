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

    test('radius is derived from proximity', () {
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

      // close > medium > far
      expect(closeNode.radius, 24.0);
      expect(mediumNode.radius, 18.0);
      expect(farNode.radius, 14.0);
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

    test('props list contains correct fields', () {
      final node = GraphNode(
        id: 5,
        x: 150.0,
        y: 250.0,
        proximity: ProximityLevel.medium,
        name: 'Test',
      );

      // name debe estar en props: dos nodos con mismo id/pos/proximidad
      // pero diferente nombre NO deben ser considerados iguales.
      expect(node.props, [5, 150.0, 250.0, ProximityLevel.medium, 'Test']);
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
  });
}
