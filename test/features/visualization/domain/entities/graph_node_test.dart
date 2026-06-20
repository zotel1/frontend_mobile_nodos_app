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

      // T3.10: props incluyen connectable. T5.1: z agregado. PR2: userColor+estimatedDistance.
      expect(node.props,
          [5, 150.0, 250.0, ProximityLevel.medium, 'Test', null, 0, false, true, 0.0, null, null]);
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

    // ─── T5.1: campo z para grafo 3D ─────────────────────────────
    // QUÉ: GraphNode incluye double z (default 0) para coordenadas 3D
    // del algoritmo Fruchterman-Reingold extendido.
    // POR QUÉ: R6.6 — la entidad debe soportar la tercera dimensión
    // para el pipeline 3D. z=0 preserva compatibilidad con 2D.

    test('T5.1: z es 0 por defecto para compatibilidad 2D', () {
      final node = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
      );
      expect(node.z, 0.0);
    });

    test('T5.1: z puede especificarse con valor no cero', () {
      final node = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        z: 350.0,
      );
      expect(node.z, 350.0);
    });

    test('T5.1: dos nodos con mismo z son iguales', () {
      final a = GraphNode(
        id: 1, x: 100, y: 200,
        proximity: ProximityLevel.close, z: 150.0,
      );
      final b = GraphNode(
        id: 1, x: 100, y: 200,
        proximity: ProximityLevel.close, z: 150.0,
      );
      expect(a, equals(b));
    });

    test('T5.1: dos nodos con distinto z NO son iguales', () {
      final a = GraphNode(
        id: 1, x: 100, y: 200,
        proximity: ProximityLevel.close, z: 100.0,
      );
      final b = GraphNode(
        id: 1, x: 100, y: 200,
        proximity: ProximityLevel.close, z: 200.0,
      );
      expect(a, isNot(equals(b)));
    });

    test('T5.1: z está en la lista props para equality', () {
      final node = GraphNode(
        id: 5, x: 150, y: 250,
        proximity: ProximityLevel.medium,
        name: 'Test', z: 42.0,
      );
      expect(node.props,
          [5, 150.0, 250.0, ProximityLevel.medium, 'Test', null, 0, false, true, 42.0, null, null]);
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

    // ─── PR2 T2.1: userColor, estimatedDistance, displayColor ───
    // QUÉ: userColor (int? ARGB) permite al usuario asignar un color
    // que sobrescribe el color de proximidad en el grafo.
    // displayColor devuelve el userColor como Color si no es null,
    // caso contrario delega al getter color (proximidad).
    // POR QUÉ: R5.6 — user-assigned colors must override proximity.

    test('PR2: userColor es null por defecto', () {
      final node = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
      );
      expect(node.userColor, isNull);
    });

    test('PR2: userColor puede especificarse con valor ARGB', () {
      final node = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        userColor: 0xFF2196F3, // azul
      );
      expect(node.userColor, equals(0xFF2196F3));
    });

    test('PR2: displayColor usa userColor cuando no es null', () {
      final node = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close, // verde
        userColor: 0xFF2196F3, // azul asignado por usuario
      );
      expect(node.displayColor, equals(const Color(0xFF2196F3)));
      // El color de proximidad original sigue siendo verde
      expect(node.color, equals(const Color(0xFF4CAF50)));
    });

    test('PR2: displayColor delega a color de proximidad cuando userColor es null', () {
      final node = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.far, // rojo
      );
      expect(node.displayColor, equals(const Color(0xFFF44336)));
    });

    test('PR2: estimatedDistance es null por defecto', () {
      final node = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
      );
      expect(node.estimatedDistance, isNull);
    });

    test('PR2: estimatedDistance puede especificarse con valor double', () {
      final node = GraphNode(
        id: 1,
        x: 100.0,
        y: 200.0,
        proximity: ProximityLevel.close,
        estimatedDistance: 3.16,
      );
      expect(node.estimatedDistance, equals(3.16));
    });

    test('PR2: userColor y estimatedDistance están en props para equality', () {
      final nodeA = GraphNode(
        id: 1, x: 100.0, y: 200.0,
        proximity: ProximityLevel.close,
        userColor: 0xFF0000FF, estimatedDistance: 1.5,
      );
      final nodeB = GraphNode(
        id: 1, x: 100.0, y: 200.0,
        proximity: ProximityLevel.close,
        userColor: 0xFF0000FF, estimatedDistance: 1.5,
      );
      final nodeC = GraphNode(
        id: 1, x: 100.0, y: 200.0,
        proximity: ProximityLevel.close,
        userColor: 0xFF00FF00, estimatedDistance: 1.5, // distinto color
      );
      final nodeD = GraphNode(
        id: 1, x: 100.0, y: 200.0,
        proximity: ProximityLevel.close,
        userColor: 0xFF0000FF, estimatedDistance: 5.0, // distinta distancia
      );

      expect(nodeA, equals(nodeB));
      expect(nodeA, isNot(equals(nodeC)));
      expect(nodeA, isNot(equals(nodeD)));
    });
  });
}
