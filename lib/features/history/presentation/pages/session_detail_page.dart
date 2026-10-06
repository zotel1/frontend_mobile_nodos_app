import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/session_node.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/bloc/history_bloc.dart';

class SessionDetailPage extends StatefulWidget {
  final int sessionId;

  const SessionDetailPage({super.key, required this.sessionId});

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<HistoryBloc>().add(
          SelectSession(sessionId: widget.sessionId),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de sesión')),
      body: BlocBuilder<HistoryBloc, HistoryState>(
        builder: (context, state) {
          if (state is HistoryError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          if (state is! HistoryLoaded ||
              state.selectedSessionId != widget.sessionId) {
            return const Center(child: CircularProgressIndicator());
          }
          final session = state.sessions.firstWhere(
            (item) => item.id == widget.sessionId,
            orElse: () => state.sessions.first,
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Inicio: ${session.startedAt}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                session.duration == null
                    ? 'En curso'
                    : 'Duración: ${session.duration}',
              ),
              Text('Nodos observados: ${session.nodeCount}'),
              const SizedBox(height: 16),
              if (state.detailNodes.isEmpty) const Text('Sin nodos observados'),
              ...state.detailNodes.map(_nodeTile),
            ],
          );
        },
      ),
    );
  }

  Widget _nodeTile(SessionNode node) {
    return ListTile(
      leading: const Icon(Icons.bluetooth),
      title: Text(node.nodeName ?? 'Nodo ${node.nodeId}'),
      subtitle: Text('RSSI: ${node.rssi} · Proximidad: ${node.proximityLevel}'),
    );
  }
}
