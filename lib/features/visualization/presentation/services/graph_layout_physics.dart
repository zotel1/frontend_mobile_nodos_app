import 'dart:math' as math;
import 'dart:ui';

import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_edge.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/graph_node.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Owns the short-lived physical relaxation state of the graph.
///
/// This is deliberately separate from [VisualizationBloc]: the BLoC
/// coordinates events and states, while this class owns velocities, spring
/// lengths and force calculation.
class GraphLayoutPhysics {
  static const double canvasMargin = 30.0;
  static const double _directSpringStrength = 0.020;
  static const double _reportedSpringStrength = 0.012;
  static const double _transitiveSpringStrength = 0.008;
  static const double _damping = 0.82;
  static const double _maxSpeed = 24.0;
  static const double _repulsionDistance = 90.0;
  static const double _repulsionStrength = 0.035;
  static const double settledSpeed = 0.12;

  final Map<int, Offset> _velocities = <int, Offset>{};
  final Map<String, double> _springRestLengths = <String, double>{};

  void beginDrag(LayoutResult layout, int nodeId) {
    _velocities[nodeId] = Offset.zero;
    _captureSpringRestLengths(layout);
  }

  void resetVelocity(int nodeId) {
    _velocities[nodeId] = Offset.zero;
  }

  void stop() {
    _velocities.removeWhere(
      (nodeId, velocity) => velocity.distance < settledSpeed,
    );
  }

  void removeStaleData(LayoutResult layout) {
    final ids = layout.nodes.map((node) => node.id).whereType<int>().toSet();
    _velocities.removeWhere((id, _) => !ids.contains(id));

    final validEdges = layout.edges.map(_edgeKey).toSet();
    _springRestLengths.removeWhere((key, _) => !validEdges.contains(key));
  }

  GraphPhysicsStep tick(LayoutResult layout, {required int? draggedNodeId}) {
    final nodesById = <int, GraphNode>{};

    for (final node in layout.nodes) {
      final id = node.id;
      if (id != null) {
        nodesById[id] = node;
      }
    }

    final forces = <int, Offset>{
      for (final id in nodesById.keys) id: Offset.zero,
    };

    _applySpringForces(layout: layout, nodesById: nodesById, forces: forces);
    _applyRepulsion(nodesById: nodesById, forces: forces);

    var maxSpeed = 0.0;
    final updatedNodes = layout.nodes
        .map((node) {
          final id = node.id;
          if (id == null) {
            return node;
          }

          if (id == draggedNodeId) {
            _velocities[id] = Offset.zero;
            return node;
          }

          final force = forces[id] ?? Offset.zero;
          final previousVelocity = _velocities[id] ?? Offset.zero;
          var velocity = Offset(
            (previousVelocity.dx + force.dx) * _damping,
            (previousVelocity.dy + force.dy) * _damping,
          );

          velocity = _limitVector(velocity, _maxSpeed);
          if (velocity.distance < 0.01) {
            velocity = Offset.zero;
          }

          _velocities[id] = velocity;
          maxSpeed = math.max(maxSpeed, velocity.distance);

          if (velocity == Offset.zero) {
            return node;
          }

          final newX = (node.x + velocity.dx)
              .clamp(canvasMargin, 2000.0 - canvasMargin)
              .toDouble();
          final newY = (node.y + velocity.dy)
              .clamp(canvasMargin, 2000.0 - canvasMargin)
              .toDouble();

          return node.copyWith(x: newX, y: newY);
        })
        .toList(growable: false);

    return GraphPhysicsStep(
      layout: LayoutResult(
        nodes: updatedNodes,
        edges: layout.edges,
        iterations: layout.iterations,
        converged: draggedNodeId == null && maxSpeed < settledSpeed,
      ),
      maxSpeed: maxSpeed,
    );
  }

  void _applySpringForces({
    required LayoutResult layout,
    required Map<int, GraphNode> nodesById,
    required Map<int, Offset> forces,
  }) {
    for (final edge in layout.edges) {
      final from = nodesById[edge.fromId];
      final to = nodesById[edge.toId];
      if (from == null || to == null) {
        continue;
      }

      final dx = to.x - from.x;
      final dy = to.y - from.y;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < 0.0001) {
        continue;
      }

      final distance = math.sqrt(distanceSquared);
      final direction = Offset(dx / distance, dy / distance);
      final restLength =
          _springRestLengths[_edgeKey(edge)] ??
          distance.clamp(80.0, 500.0).toDouble();
      final displacement = distance - restLength;
      final springStrength = switch (edge.edgeType) {
        EdgeType.direct => _directSpringStrength,
        EdgeType.reported => _reportedSpringStrength,
        EdgeType.transitive => _transitiveSpringStrength,
      };
      final thicknessMultiplier =
          1.0 + ((edge.thickness - 1.0).clamp(0.0, 2.0) * 0.12);
      final force =
          direction * (displacement * springStrength * thicknessMultiplier);

      forces[edge.fromId] = (forces[edge.fromId] ?? Offset.zero) + force;
      forces[edge.toId] = (forces[edge.toId] ?? Offset.zero) - force;
    }
  }

  void _applyRepulsion({
    required Map<int, GraphNode> nodesById,
    required Map<int, Offset> forces,
  }) {
    final entries = nodesById.entries.toList(growable: false);
    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final first = entries[i];
        final second = entries[j];
        final dx = second.value.x - first.value.x;
        final dy = second.value.y - first.value.y;
        final distanceSquared = dx * dx + dy * dy;
        if (distanceSquared < 0.0001) {
          continue;
        }

        final distance = math.sqrt(distanceSquared);
        if (distance >= _repulsionDistance) {
          continue;
        }

        final direction = Offset(dx / distance, dy / distance);
        final force =
            direction * ((_repulsionDistance - distance) * _repulsionStrength);
        forces[first.key] = (forces[first.key] ?? Offset.zero) - force;
        forces[second.key] = (forces[second.key] ?? Offset.zero) + force;
      }
    }
  }

  void _captureSpringRestLengths(LayoutResult layout) {
    final nodesById = <int, GraphNode>{};
    for (final node in layout.nodes) {
      final id = node.id;
      if (id != null) {
        nodesById[id] = node;
      }
    }

    for (final edge in layout.edges) {
      final from = nodesById[edge.fromId];
      final to = nodesById[edge.toId];
      if (from == null || to == null) {
        continue;
      }

      final dx = to.x - from.x;
      final dy = to.y - from.y;
      _springRestLengths[_edgeKey(edge)] = math
          .sqrt(dx * dx + dy * dy)
          .clamp(60.0, 600.0)
          .toDouble();
    }
  }

  String _edgeKey(GraphEdge edge) {
    final first = math.min(edge.fromId, edge.toId);
    final second = math.max(edge.fromId, edge.toId);
    return '$first:$second:${edge.edgeType.name}';
  }

  Offset _limitVector(Offset vector, double maximum) {
    final magnitude = vector.distance;
    if (magnitude <= maximum || magnitude == 0) {
      return vector;
    }

    final factor = maximum / magnitude;
    return Offset(vector.dx * factor, vector.dy * factor);
  }
}

class GraphPhysicsStep {
  final LayoutResult layout;
  final double maxSpeed;

  const GraphPhysicsStep({required this.layout, required this.maxSpeed});
}
