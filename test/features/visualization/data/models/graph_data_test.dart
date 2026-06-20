import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/models/graph_data.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

void main() {
  // ═══════════ T5.3: Serialización/deserialización de Z ═══════════
  // QUÉ: layoutResultToParams y paramsToLayoutResult deben incluir
  // la coordenada Z en el mapa serializable.
  // POR QUÉ: T5.2 introdujo el cálculo de Z en FR 3D. Sin serializar Z,
  // la coordenada se pierde al cruzar el límite del Isolate.

  group('T5.3: layoutResultToParams — incluye z en nodos', () {
    test('serializa GraphNode.z en el mapa de nodos', () {
      final layout = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1, x: 100.0, y: 200.0,
            proximity: ProximityLevel.close,
            z: 350.0,
          ),
          const GraphNode(
            id: 2, x: 300.0, y: 400.0,
            proximity: ProximityLevel.medium,
            z: 150.0,
          ),
        ],
        edges: [
          const GraphEdge(fromId: 1, toId: 2, thickness: 1.0),
        ],
        iterations: 0,
        converged: false,
      );

      final params = layoutResultToParams(layout, 2000, 2000);

      final nodesMap = params['nodes'] as List<Map<String, dynamic>>;
      expect(nodesMap.length, equals(2));
      expect(nodesMap[0]['z'], equals(350.0));
      expect(nodesMap[1]['z'], equals(150.0));
    });

    test('serializa z=0 cuando GraphNode.z es 0 (por defecto)', () {
      final layout = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1, x: 100.0, y: 200.0,
            proximity: ProximityLevel.close,
          ),
        ],
        edges: [],
        iterations: 0,
        converged: false,
      );

      final params = layoutResultToParams(layout, 2000, 2000);
      final nodesMap = params['nodes'] as List<Map<String, dynamic>>;
      expect(nodesMap[0]['z'], equals(0.0));
    });
  });

  group('T5.3: paramsToLayoutResult — lee z del resultado', () {
    test('reconstruye GraphNode.z desde el mapa del Isolate', () {
      final original = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1, x: 0.0, y: 0.0,
            proximity: ProximityLevel.close,
            name: 'Nodo 1',
          ),
          const GraphNode(
            id: 2, x: 0.0, y: 0.0,
            proximity: ProximityLevel.medium,
            name: 'Nodo 2',
          ),
        ],
        edges: [
          const GraphEdge(fromId: 1, toId: 2, thickness: 1.0),
        ],
        iterations: 0,
        converged: false,
      );

      // Simular resultado del Isolate con z calculado
      final resultMap = <String, dynamic>{
        'nodes': [
          {'id': 1, 'x': 500.0, 'y': 600.0, 'z': 350.0},
          {'id': 2, 'x': 700.0, 'y': 800.0, 'z': 150.0},
        ],
        'edges': [
          {'fromId': 1, 'toId': 2, 'thickness': 1.0},
        ],
        'iterations': 100,
        'converged': true,
      };

      final result = paramsToLayoutResult(resultMap, original);

      expect(result.nodes.length, equals(2));
      expect(result.nodes[0].z, equals(350.0));
      expect(result.nodes[1].z, equals(150.0));
    });

    test('usa z=0 cuando el mapa del Isolate no incluye z', () {
      final original = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1, x: 0.0, y: 0.0,
            proximity: ProximityLevel.close,
          ),
        ],
        edges: [],
        iterations: 0,
        converged: false,
      );

      // Resultado del Isolate SIN campo z (backward compatible)
      final resultMap = <String, dynamic>{
        'nodes': [
          {'id': 1, 'x': 500.0, 'y': 600.0}, // sin z
        ],
        'edges': [],
        'iterations': 1,
        'converged': true,
      };

      final result = paramsToLayoutResult(resultMap, original);
      expect(result.nodes[0].z, equals(0.0));
    });
  });

  // ═══════════ F3: Preservación de metadata en round-trip ═══════════
  // QUÉ: paramsToLayoutResult debe preservar connectionCount,
  // suggestedName, isSelf y connectable del nodo original al
  // reconstruir el LayoutResult después del Isolate.
  // POR QUÉ: sin esta preservación, todos los nodos pierden su
  // metadata visual (connectionCount→radio=12px fijo, isSelf→sin glow,
  // suggestedName→labels incorrectos).

  group('F3: paramsToLayoutResult preserva metadata del original', () {
    test('preserva connectionCount del nodo original', () {
      final original = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1, x: 0.0, y: 0.0,
            proximity: ProximityLevel.close,
            connectionCount: 5,
          ),
        ],
        edges: [
          const GraphEdge(fromId: 1, toId: 2, thickness: 1.0),
        ],
        iterations: 0,
        converged: false,
      );

      final resultMap = <String, dynamic>{
        'nodes': [
          {'id': 1, 'x': 500.0, 'y': 600.0},
        ],
        'edges': [],
        'iterations': 100,
        'converged': true,
      };

      final result = paramsToLayoutResult(resultMap, original);
      expect(result.nodes[0].connectionCount, equals(5));
      expect(result.nodes[0].radius, equals(12.0 + 5 * 3.0)); // 27px
    });

    test('preserva suggestedName del nodo original', () {
      final original = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1, x: 0.0, y: 0.0,
            proximity: ProximityLevel.close,
            suggestedName: 'AirPods Pro',
          ),
        ],
        edges: [],
        iterations: 0,
        converged: false,
      );

      final resultMap = <String, dynamic>{
        'nodes': [
          {'id': 1, 'x': 500.0, 'y': 600.0},
        ],
        'edges': [],
        'iterations': 100,
        'converged': true,
      };

      final result = paramsToLayoutResult(resultMap, original);
      expect(result.nodes[0].suggestedName, equals('AirPods Pro'));
      expect(result.nodes[0].label, equals('AirPods Pro'));
    });

    test('preserva isSelf del nodo original', () {
      final original = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1, x: 0.0, y: 0.0,
            proximity: ProximityLevel.close,
            isSelf: true,
          ),
        ],
        edges: [],
        iterations: 0,
        converged: false,
      );

      final resultMap = <String, dynamic>{
        'nodes': [
          {'id': 1, 'x': 500.0, 'y': 600.0},
        ],
        'edges': [],
        'iterations': 100,
        'converged': true,
      };

      final result = paramsToLayoutResult(resultMap, original);
      expect(result.nodes[0].isSelf, isTrue);
    });

    test('preserva connectable del nodo original', () {
      final original = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1, x: 0.0, y: 0.0,
            proximity: ProximityLevel.close,
            connectable: false,
          ),
        ],
        edges: [],
        iterations: 0,
        converged: false,
      );

      final resultMap = <String, dynamic>{
        'nodes': [
          {'id': 1, 'x': 500.0, 'y': 600.0},
        ],
        'edges': [],
        'iterations': 100,
        'converged': true,
      };

      final result = paramsToLayoutResult(resultMap, original);
      expect(result.nodes[0].connectable, isFalse);
    });

    test('preserva todos los campos metadata simultáneamente', () {
      final original = LayoutResult(
        nodes: [
          const GraphNode(
            id: 1, x: 0.0, y: 0.0,
            proximity: ProximityLevel.close,
            connectionCount: 3,
            suggestedName: 'Nodo Test',
            isSelf: true,
            connectable: false,
          ),
        ],
        edges: [],
        iterations: 0,
        converged: false,
      );

      final resultMap = <String, dynamic>{
        'nodes': [
          {'id': 1, 'x': 500.0, 'y': 600.0},
        ],
        'edges': [],
        'iterations': 100,
        'converged': true,
      };

      final result = paramsToLayoutResult(resultMap, original);
      expect(result.nodes[0].connectionCount, equals(3));
      expect(result.nodes[0].suggestedName, equals('Nodo Test'));
      expect(result.nodes[0].isSelf, isTrue);
      expect(result.nodes[0].connectable, isFalse);
    });
  });
}
