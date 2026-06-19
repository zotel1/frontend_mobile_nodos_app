import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:app_settings/app_settings.dart'
    show AppSettings, AppSettingsType;
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/core/di/injection_container.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/widgets/bluetooth_off_banner.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/widgets/bluetooth_off_dialog.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/widgets/node_tile.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view.dart';

/// Pantalla principal: alterna entre lista de nodos (≤4) y grafo (>4).
///
/// Usa [AnimatedCrossFade] con histéresis para evitar parpadeos:
/// - Sube a grafo cuando llega a 5+ nodos.
/// - Baja a lista cuando desciende a ≤3 nodos.
/// - Con 4 nodos mantiene la vista actual.
///
/// Escucha [NodeListBloc] para cambios en la lista y
/// [VisualizationBloc] para el estado del grafo (cargando/listo/error).
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Controla qué hijo del AnimatedCrossFade se muestra.
  /// true = grafo (secondChild), false = lista (firstChild).
  bool _showingGraph = false;

  /// ID de la sesión de escaneo activa para el grafo.
  /// Se crea bajo demanda cuando se transiciona a modo grafo.
  int? _scanSessionId;

  /// Guard contra stacking de [BluetoothOffDialog].
  ///
  /// QUÉ hace: previene que se muestren múltiples diálogos
  /// superpuestos cuando BleBloc emite [BluetoothOff] repetidamente.
  ///
  /// POR QUÉ: cada emisión del stream de estado BT (por ej. durante
  /// un toggle rápido encendido/apagado) podría disparar showDialog.
  /// Este flag asegura que solo haya un diálogo visible a la vez.
  bool _dialogVisible = false;

  @override
  Widget build(BuildContext context) {
    final bleBloc = context.read<BleBloc>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nodos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: BlocListener<BleBloc, BleState>(
        /// Puente BLE → Node: convierte resultados de escaneo BLE en
        /// entidades Node persistentes.
        ///
        /// QUÉ hace: escucha BleBloc y cuando emite BleScanning con
        /// dispositivos detectados, despacha SyncBleDevices al NodeListBloc
        /// para que persista cada BleDevice como un Node en Drift.
        ///
        /// POR QUÉ: sin este listener la app escanea dispositivos pero
        /// nunca los muestra en la UI. El BlocListener<NodeListBloc> (abajo)
        /// maneja los cambios de vista cuando los nodos ya están persistidos.
        listener: (context, bleState) {
          if (bleState is BleScanning && bleState.devices.isNotEmpty) {
            context
                .read<NodeListBloc>()
                .add(SyncBleDevices(bleState.devices));
          }
          // Mostrar diálogo cuando BT está apagado.
          // El guard _dialogVisible previene stacking de múltiples diálogos.
          if (bleState is BluetoothOff && !_dialogVisible) {
            _dialogVisible = true;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => BluetoothOffDialog(
                onGoToSettings: () {
                  _dialogVisible = false;
                  AppSettings.openAppSettings(
                    type: AppSettingsType.bluetooth,
                  );
                },
                onCancel: () {
                  _dialogVisible = false;
                },
              ),
            );
          }
          // Si BT vuelve a estar disponible, reseteamos el guard.
          if (bleState is BleStopped || bleState is BleScanning) {
            _dialogVisible = false;
          }
        },
        child: BlocListener<NodeListBloc, NodeListState>(
        // Dispara la construcción del grafo cuando la lista cambia.
        // Usa listener (no builder) para side effects — no dispara
        // reconstrucciones innecesarias.
        listener: (context, nodeListState) {
          if (nodeListState is NodeListLoaded) {
            _updateViewMode(nodeListState.nodes, context);
          }
        },
        child: BlocBuilder<BleBloc, BleState>(
          builder: (context, bleState) {
            return Column(
              children: [
                if (bleState is BluetoothOff)
                  BluetoothOffBanner(
                    onGoToSettings: () {
                      AppSettings.openAppSettings(
                        type: AppSettingsType.bluetooth,
                      );
                    },
                  ),
                Expanded(child: _buildContent()),
              ],
            );
          },
        ),
      ),
      ),
      floatingActionButton: BlocBuilder<BleBloc, BleState>(
        builder: (context, bleState) {
          final isScanning = bleState is BleScanning;
          return FloatingActionButton(
            onPressed: () {
              if (isScanning) {
                bleBloc.add(const StopScan());
              } else {
                bleBloc.add(const StartScan());
              }
            },
            tooltip: isScanning ? 'Detener escaneo' : 'Iniciar escaneo',
            child: Icon(isScanning ? Icons.stop : Icons.bluetooth_searching),
          );
        },
      ),
    );
  }

  /// Aplica histéresis al modo de visualización según la cantidad de nodos.
  ///
  /// Umbrales:
  /// - ≥5 nodos: activa modo grafo (si no estaba activo) y dispara
  ///   la construcción/reconstrucción del layout.
  /// - ≤3 nodos: vuelve a modo lista (si estaba en grafo).
  /// - 4 nodos: mantiene el modo actual, evitando parpadeos.
  ///
  /// Cuando se activa el grafo, asegura que exista una sesión de escaneo
  /// en la BD y dispara [BuildGraphRequested] en el [VisualizationBloc].
  /// El debounce interno del BLoC (1s) evita procesamiento excesivo
  /// cuando el conteo de nodos cambia rápidamente durante el escaneo.
  void _updateViewMode(List<Node> nodes, BuildContext context) {
    final count = nodes.length;

    if (count >= 5) {
      if (!_showingGraph) {
        setState(() => _showingGraph = true);
      }
      _triggerGraphBuild(nodes, context);
    } else if (count <= 3 && _showingGraph) {
      setState(() => _showingGraph = false);
    }
  }

  /// Crea una sesión de escaneo bajo demanda y dispara la construcción
  /// del grafo en el [VisualizationBloc].
  ///
  /// Problema que resuelve: la tabla [scanSessionNodes] es la fuente de
  /// verdad para las aristas del grafo. Sin datos en esta tabla,
  /// GraphRepositoryImpl.buildGraph() retorna un LayoutResult vacío.
  /// Aquí aseguramos que los nodos actuales estén registrados antes
  /// de solicitar el layout.
  Future<void> _triggerGraphBuild(
    List<Node> nodes,
    BuildContext context,
  ) async {
    final db = sl<AppDatabase>();
    final vizBloc = context.read<VisualizationBloc>();

    // Reusar sesión existente o crear una nueva
    int sessionId;
    if (_scanSessionId != null) {
      sessionId = _scanSessionId!;
    } else {
      sessionId = await db.into(db.scanSessions).insert(
            ScanSessionsCompanion.insert(
              startedAt: DateTime.now(),
              nodesDetected: nodes.length,
            ),
          );
      _scanSessionId = sessionId;
    }

    // Insertar nodos en scan_session_nodes (insertOrIgnore evita duplicados)
    for (final node in nodes) {
      if (node.id != null) {
        await db.into(db.scanSessionNodes).insert(
              ScanSessionNodesCompanion.insert(
                sessionId: sessionId,
                nodeId: node.id!,
                rssi: node.rssiHistory.isNotEmpty ? node.rssiHistory.last : -100,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }

    if (!mounted) return;

    // Disparar construcción del grafo con debounce interno del BLoC
    vizBloc.add(BuildGraphRequested(
      scanSessionId: sessionId,
      nodes: nodes,
    ));
  }

  /// Construye el contenido principal: ListView para lista,
  /// GraphView (con loading/error) para grafo, mediante AnimatedCrossFade.
  Widget _buildContent() {
    return BlocBuilder<NodeListBloc, NodeListState>(
      builder: (context, state) {
        return switch (state) {
          NodeListLoading() =>
            const Center(child: CircularProgressIndicator()),
          NodeListEmpty() => const Center(
              child: Text(
                'No se encontraron nodos',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          NodeListLoaded(:final nodes) => _buildAnimatedContent(nodes),
          NodeListError(:final message) => Center(
              child: Text(
                message,
                style: const TextStyle(color: Colors.red, fontSize: 16),
              ),
            ),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }

  /// AnimatedCrossFade entre ListView (≤4 nodos) y GraphView (>4 nodos).
  ///
  /// La histéresis (_showingGraph) evita que el crossfade oscile
  /// cuando la cantidad de nodos fluctúa alrededor del umbral.
  Widget _buildAnimatedContent(List<Node> nodes) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 300),
      crossFadeState: _showingGraph
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      firstChild: _buildListView(nodes),
      secondChild: BlocBuilder<VisualizationBloc, VisualizationState>(
        builder: (context, vizState) {
          return switch (vizState) {
            VisualizationInitial() || GraphBuilding() =>
              const Center(child: CircularProgressIndicator()),
            GraphReady(:final layout, :final selectedNodeId) =>
              GraphView(
                layout: layout,
                selectedNodeId: selectedNodeId,
                onNodeTapped: (nodeId) {
                  context.read<VisualizationBloc>().add(NodeSelected(nodeId));
                },
              ),
            GraphError(:final message) => Center(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                ),
              ),
            _ => const SizedBox.shrink(),
          };
        },
      ),
    );
  }

  /// Lista tradicional de nodos (usada cuando hay ≤4 nodos).
  ///
  /// Usa shrinkWrap: true porque la lista se renderiza dentro de un
  /// AnimatedCrossFade, que construye ambos hijos simultáneamente
  /// y requiere que cada hijo declare su tamaño intrínseco.
  Widget _buildListView(List<Node> nodes) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: nodes.length,
      itemBuilder: (context, index) => NodeTile(
        node: nodes[index],
        onTap: () => Navigator.pushNamed(
          context,
          '/node/${nodes[index].id}',
        ),
      ),
    );
  }
}
