import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/data/models/graph_data.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/algorithms/layout_algorithm.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/usecases/calculate_layout.dart';

/// Mock del algoritmo de layout para tests.
///
/// Permite controlar qué retorna el algoritmo sin ejecutar
/// el costoso Fruchterman-Reingold real. Ideal para testear
/// el comportamiento del use case (orquestación, manejo de errores)
/// independientemente del algoritmo concreto.
class MockLayoutAlgorithm implements LayoutAlgorithm {
  /// Valor que retornará [calculate] en la próxima llamada.
  final Map<String, dynamic>? returnValue;

  /// Si no es null, [calculate] lanzará esta excepción.
  final Exception? throwError;

  /// Parámetros recibidos en la última llamada a [calculate].
  Map<String, dynamic>? lastParams;

  MockLayoutAlgorithm({this.returnValue, this.throwError});

  @override
  Future<Map<String, dynamic>> calculate(Map<String, dynamic> params) async {
    lastParams = params;
    if (throwError != null) throw throwError!;
    return returnValue ?? {};
  }
}

void main() {
  // ═══════════ PR5a: CalculateLayout con LayoutAlgorithm ═══════════
  // QUÉ: CalculateLayout depende de la interfaz LayoutAlgorithm
  // en vez de llamar directamente a calculateFRLayout().
  // POR QUÉ: AD-31, AD-34 — el dominio debe depender de interfaces,
  // no de implementaciones concretas en la capa de datos.

  final testLayout = LayoutResult(
    nodes: [
      const GraphNode(id: 1, x: 0, y: 0, proximity: ProximityLevel.close),
      const GraphNode(id: 2, x: 0, y: 0, proximity: ProximityLevel.medium),
    ],
    edges: [
      const GraphEdge(fromId: 1, toId: 2, thickness: 1.0),
    ],
    iterations: 0,
    converged: false,
  );

  final mockResult = {
    'nodes': [
      {'id': 1, 'x': 100.0, 'y': 200.0, 'z': 0.0},
      {'id': 2, 'x': 300.0, 'y': 400.0, 'z': 0.0},
    ],
    'edges': [
      {'fromId': 1, 'toId': 2},
    ],
    'iterations': 50,
    'converged': true,
  };

  group('CalculateLayout con LayoutAlgorithm mock', () {
    test('delega al LayoutAlgorithm con los params correctos', () async {
      final mock = MockLayoutAlgorithm(returnValue: mockResult);
      final useCase = CalculateLayout(layoutAlgorithm: mock);

      final result = await useCase(testLayout, 2000.0, 1500.0);

      // Verifica que el mock recibió los params esperados
      expect(mock.lastParams, isNotNull);
      expect(mock.lastParams!['width'], 2000.0);
      expect(mock.lastParams!['height'], 1500.0);
      expect((mock.lastParams!['nodes'] as List).length, 2);
      expect((mock.lastParams!['edges'] as List).length, 1);

      // Verifica que el resultado es Right con los datos del mock
      expect(result.isRight(), isTrue);
      final layout = result.getOrElse(() => testLayout);
      expect(layout.nodes.length, 2);
      expect(layout.nodes[0].x, 100.0);
      expect(layout.nodes[1].y, 400.0);
      expect(layout.iterations, 50);
      expect(layout.converged, isTrue);
    });

    test('pasa el parámetro depth al LayoutAlgorithm', () async {
      final mock = MockLayoutAlgorithm(returnValue: mockResult);
      final useCase = CalculateLayout(layoutAlgorithm: mock);

      await useCase(testLayout, 2000.0, 2000.0, depth: 1500.0);

      expect(mock.lastParams!['depth'], 1500.0);
    });

    test('retorna Failure cuando el LayoutAlgorithm lanza excepción', () async {
      final mock = MockLayoutAlgorithm(throwError: Exception('FR error'));
      final useCase = CalculateLayout(layoutAlgorithm: mock);

      final result = await useCase(testLayout, 2000.0, 2000.0);

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => null);
      expect(failure, isA<UnexpectedFailure>());
      expect(
        (failure as UnexpectedFailure).message,
        contains('Error al calcular layout del grafo'),
      );
    });

    test('pasa seed al LayoutAlgorithm cuando se especifica', () async {
      final mock = MockLayoutAlgorithm(returnValue: mockResult);
      final useCase = CalculateLayout(layoutAlgorithm: mock);

      await useCase(testLayout, 2000.0, 2000.0, seed: 42);

      expect(mock.lastParams!['seed'], 42);
    });

    test('reutiliza priorLayout como fuente de posiciones iniciales', () async {
      final mock = MockLayoutAlgorithm(returnValue: mockResult);
      final useCase = CalculateLayout(layoutAlgorithm: mock);

      final priorLayout = LayoutResult(
        nodes: [
          const GraphNode(id: 1, x: 50, y: 60, proximity: ProximityLevel.close),
          const GraphNode(id: 2, x: 70, y: 80, proximity: ProximityLevel.medium),
        ],
        edges: testLayout.edges,
        iterations: 10,
        converged: false,
      );

      await useCase(
        testLayout, 2000.0, 2000.0,
        priorLayout: priorLayout,
      );

      // Con cache de posiciones, debería usar menos iteraciones (30 vs 100)
      expect(mock.lastParams!['iterations'], 30);
      // Las posiciones iniciales vienen del priorLayout
      final nodes = mock.lastParams!['nodes'] as List;
      expect(nodes[0]['x'], 50.0);
      expect(nodes[1]['y'], 80.0);
    });
  });
}
