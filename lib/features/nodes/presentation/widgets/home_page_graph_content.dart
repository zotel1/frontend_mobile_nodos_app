import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_mobile_nodos_app/core/di/injection_container.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view_3d.dart';

/// Owns the 2D/3D graph viewport and keeps both renderers mounted.
class HomePageGraphContent extends StatelessWidget {
  const HomePageGraphContent({
    super.key,
    required this.graphViewKey,
    required this.is3D,
    required this.layout,
    required this.selectedNodeId,
    required this.detailsNodeId,
    required this.barycenter,
  });

  final GlobalKey<GraphViewState> graphViewKey;
  final ValueNotifier<bool> is3D;
  final LayoutResult layout;
  final int? selectedNodeId;
  final int? detailsNodeId;
  final Offset? barycenter;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: is3D,
      builder: (context, showing3D, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: showing3D,
              child: GraphView(
                key: graphViewKey,
                layout: layout,
                selectedNodeId: selectedNodeId,
                detailsNodeId: detailsNodeId,
                barycenter: barycenter,
                onNodeTapped: (nodeId) =>
                    context.read<VisualizationBloc>().add(NodeSelected(nodeId)),
                onNodeDoubleTapped: (nodeId) => context
                    .read<VisualizationBloc>()
                    .add(NodeDetailsToggled(nodeId)),
                onNodeDragStarted: (nodeId) => context
                    .read<VisualizationBloc>()
                    .add(NodeDragStarted(nodeId)),
                onNodeDragUpdated: (nodeId, position) =>
                    context.read<VisualizationBloc>().add(
                      NodeDragUpdated(
                        nodeId: nodeId,
                        x: position.dx,
                        y: position.dy,
                      ),
                    ),
                onNodeDragEnded: (nodeId) => context
                    .read<VisualizationBloc>()
                    .add(NodeDragEnded(nodeId)),
              ),
            ),
            Offstage(
              offstage: !showing3D,
              child: GraphView3D(
                layout: layout,
                selectedNodeId: selectedNodeId,
                onNodeTapped: (nodeId) =>
                    context.read<VisualizationBloc>().add(NodeSelected(nodeId)),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Toolbar for switching between the mounted 2D and 3D graph renderers.
class HomePageGraphToolbar extends StatelessWidget {
  const HomePageGraphToolbar({super.key, required this.is3D});

  final ValueNotifier<bool> is3D;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: is3D,
      builder: (context, showing3D, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                showing3D ? 'Vista 3D' : 'Vista 2D',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(showing3D ? Icons.grid_view : Icons.view_in_ar),
                tooltip: showing3D
                    ? 'Cambiar a vista 2D'
                    : 'Cambiar a vista 3D',
                onPressed: () {
                  is3D.value = !is3D.value;
                  sl<SharedPreferences>().setBool('is3D', is3D.value);
                },
                iconSize: 24,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        );
      },
    );
  }
}
