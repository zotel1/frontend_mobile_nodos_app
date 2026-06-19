import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/history_stats.dart';
import 'package:frontend_mobile_nodos_app/features/history/presentation/bloc/history_bloc.dart';

/// Tab de Estadísticas: muestra tarjetas con métricas agregadas
/// de todas las sesiones de escaneo.
///
/// S5.1: Tarjetas con total sesiones, nodos únicos, duración promedio
/// y nodo más frecuente.
/// S5.2: Si no hay datos, muestra ceros y "Desconocido".
///
/// POR QUÉ: separa la vista de estadísticas en un widget independiente
/// que comparte el HistoryBloc con HistoryTab. Las estadísticas se
/// cargan junto con las sesiones en LoadHistory.
class StatsTab extends StatelessWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HistoryBloc, HistoryState>(
      builder: (context, state) {
        if (state is HistoryLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is HistoryLoaded) {
          return _StatsContent(stats: state.stats);
        }
        if (state is HistoryError) {
          return Center(child: Text('Error: ${state.message}'));
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _StatsContent extends StatelessWidget {
  final HistoryStats stats;

  const _StatsContent({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // Grid de 2 columnas con las 4 tarjetas
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [
                _StatCard(
                  label: 'Total sesiones',
                  value: '${stats.totalSessions}',
                  icon: Icons.history,
                  theme: theme,
                ),
                _StatCard(
                  label: 'Nodos únicos',
                  value: '${stats.uniqueNodes}',
                  icon: Icons.devices,
                  theme: theme,
                ),
                _StatCard(
                  label: 'Duración promedio',
                  value: _formatDuration(stats.averageDuration),
                  icon: Icons.timer,
                  theme: theme,
                ),
                _StatCard(
                  label: 'Nodo más frecuente',
                  value: stats.mostFrequentNodeName ?? 'Desconocido',
                  icon: Icons.star,
                  theme: theme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Formatea una duración como "X min" o "0 min" si es cero.
  String _formatDuration(Duration d) {
    if (d.inMinutes > 0) {
      return '${d.inMinutes} min';
    }
    if (d.inSeconds > 0) {
      return '${d.inSeconds}s';
    }
    return '0 min';
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final ThemeData theme;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
