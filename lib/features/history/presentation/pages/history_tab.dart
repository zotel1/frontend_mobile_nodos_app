import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/scan_session.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/bloc/history_bloc.dart';

/// Formatea un DateTime como "dd/MM/yy HH:mm".
String _formatDateTime(DateTime dt) {
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final year = dt.year.toString().substring(2); // últimos 2 dígitos
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$day/$month/$year $hour:$minute';
}

/// Tab de Historial: muestra sesiones de escaneo pasadas con tarjetas
/// que incluyen fecha, duración y conteo de nodos detectados.
///
/// S4.1: Lista sesiones ordenadas por fecha (más reciente primero).
/// Cada tarjeta muestra: hora de inicio, duración, número de nodos.
///
/// T3.7: Chips de filtro por rango de fecha: Hoy, 7 días, 30 días, Todo.
/// T3.8: Campo de búsqueda textual sobre nombre de nodos.
///
/// POR QUÉ: separa la vista de historial en un widget independiente
/// que se integra en el BottomNavigationBar via StatefulShellRoute.
/// El HistoryBloc se comparte entre HistoryTab y StatsTab.
class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HistoryBloc, HistoryState>(
      builder: (context, state) {
        if (state is HistoryInitial) {
          return const SizedBox.shrink();
        }
        if (state is HistoryLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is HistoryError) {
          return Center(child: Text('Error: ${state.message}'));
        }
        if (state is HistoryLoaded) {
          return _HistoryContent(
            sessions: state.sessions,
            filters: state.filters,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _HistoryContent extends StatelessWidget {
  final List<ScanSession> sessions;
  final HistoryFilters filters;

  const _HistoryContent({
    required this.sessions,
    required this.filters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Date filter chips (T3.7) ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: DateRange.values.map((range) {
                final label = switch (range) {
                  DateRange.today => 'Hoy',
                  DateRange.last7Days => '7 días',
                  DateRange.last30Days => '30 días',
                  DateRange.all => 'Todo',
                };
                final isSelected = filters.dateRange == range;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: (_) {
                      context.read<HistoryBloc>().add(FilterByDate(range));
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // ── Name search filter (T3.8) ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar por nombre de nodo...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (query) {
              context.read<HistoryBloc>().add(FilterByName(query: query));
            },
          ),
        ),

        const SizedBox(height: 8),

        // ── Session list ──
        Expanded(
          child: sessions.isEmpty
              ? const Center(child: Text('Sin sesiones'))
              : ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    return _SessionCard(session: sessions[index]);
                  },
                ),
        ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  final ScanSession session;

  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final startStr = _formatDateTime(session.startedAt);

    String? durationStr;
    if (session.duration != null) {
      final d = session.duration!;
      if (d.inHours > 0) {
        durationStr = '${d.inHours}h ${d.inMinutes % 60}min';
      } else if (d.inMinutes > 0) {
        durationStr = '${d.inMinutes} min';
      } else {
        durationStr = '${d.inSeconds}s';
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.bluetooth_searching),
        title: Text(startStr),
        subtitle: durationStr != null
            ? Text('Duración: $durationStr')
            : const Text('En curso'),
        trailing: Text(
          '${session.nodeCount} nodo${session.nodeCount == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
    );
  }
}
