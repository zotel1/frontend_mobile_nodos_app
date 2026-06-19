import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:android_intent_plus/android_intent.dart';
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
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/node_tooltip.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

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

  /// GlobalKey del GraphView para calcular posiciones globales de nodos.
  ///
  /// Usado por NodeTooltip.show() para posicionar el tooltip cerca del
  /// nodo tocado en coordenadas de pantalla.
  final GlobalKey _graphViewKey = GlobalKey();

  /// Referencia al BleBloc guardada en initState para usar en dispose()
  /// cuando el context ya no es seguro para ancestor lookup.
  BleBloc? _bleBloc;

  /// Entry del tooltip actualmente visible en el Overlay.
  /// null si no hay tooltip abierto.
  OverlayEntry? _tooltipEntry;

  /// ID del nodo para el cual el tooltip está actualmente visible.
  /// Previene re-apertura del tooltip para el mismo nodo.
  int? _tooltipNodeId;

  /// T2.4: Timestamp del último escaneo BLE exitoso.
  ///
  /// Se actualiza cada vez que BleBloc emite [BleScanning] con
  /// dispositivos detectados. Usado para mostrar "Ahora" / "Hace X min"
  /// en la barra de info superior.
  DateTime? _lastScanTime;

  /// Abre el tooltip para un nodo específico en el grafo.
  ///
  /// QUÉ hace: busca el GraphNode por ID en el layout, calcula su
  /// posición global usando el GlobalKey del GraphView, y llama a
  /// NodeTooltip.show() para mostrar un overlay con la info del nodo.
  ///
  /// POR QUÉ: el usuario tocó un nodo en el grafo y necesita ver
  /// detalles (nombre, proximidad, ID) sin navegar a otra pantalla.
  ///
  /// Guard: usa addPostFrameCallback para asegurar que el RenderBox
  /// del GraphView esté disponible después del build.
  void _showNodeTooltip(
      BuildContext context, LayoutResult layout, int nodeId) {
    if (_tooltipNodeId == nodeId) return; // ya visible para este nodo

    final node = layout.nodes.firstWhere(
      (n) => n.id == nodeId,
      orElse: () => throw StateError('Nodo $nodeId no encontrado en layout'),
    );

    // addPostFrameCallback asegura que el RenderBox del GraphView
    // esté disponible después del build del frame actual.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final renderBox =
          _graphViewKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      // Calcular posición global aproximada del nodo en pantalla.
      // La posición del canvas (2000×2000) se transforma vía el RenderBox.
      final localPos = Offset(node.x, node.y);
      final globalPosition = renderBox.localToGlobal(localPos);

      // Remover tooltip previo si existe
      _tooltipEntry?.remove();
      _tooltipEntry = null;

      _tooltipEntry = NodeTooltip.show(
        context: context,
        node: node,
        globalPosition: globalPosition,
        onDismiss: () {
          _tooltipEntry = null;
          _tooltipNodeId = null;
          if (mounted) {
            context.read<VisualizationBloc>().add(const NodeDeselected());
          }
        },
      );
      _tooltipNodeId = nodeId;
    });
  }

  /// Cierra el tooltip si está visible.
  void _dismissTooltip() {
    _tooltipEntry?.remove();
    _tooltipEntry = null;
    _tooltipNodeId = null;
  }

  /// F4 + T1.8: Dispara LoadNodes y StartScan al inicializar la pantalla.
  ///
  /// QUÉ: LoadNodes inicia la suscripción al stream Drift de nodos.
  /// StartScan inicia el escaneo BLE automáticamente sin FAB.
  /// Guarda referencia a BleBloc para dispose() donde context no es seguro.
  /// addPostFrameCallback asegura que el context ya tiene los BLoCs
  /// disponibles desde el árbol de providers.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bleBloc = context.read<BleBloc>();
      _bleBloc = bleBloc;
      context.read<NodeListBloc>().add(const LoadNodes());
      bleBloc.add(const StartScan());
    });
  }

  /// T1.8: Detiene el escaneo BLE al destruir el widget.
  ///
  /// QUÉ: cuando el usuario navega a otra tab, el escaneo debe detenerse
  /// para ahorrar batería y recursos de plataforma.
  /// Usa _bleBloc (guardado en initState) porque context.read no es seguro
  /// durante dispose — el widget ya está desmontado.
  @override
  void dispose() {
    _bleBloc?.add(const StopScan());
    _tooltipEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      body: BlocListener<VisualizationBloc, VisualizationState>(
        /// Escucha cambios en el VisualizationBloc para mostrar/ocultar el
        /// NodeTooltip cuando cambia selectedNodeId.
        ///
        /// QUÉ hace: cuando GraphReady tiene selectedNodeId != null, busca
        /// el nodo en el layout y muestra un tooltip flotante. Cuando
        /// selectedNodeId es null, cierra cualquier tooltip activo.
        ///
        /// POR QUÉ: el tooltip es un efecto lateral (Overlay) que no debe
        /// dispararse durante el build. El listener de BLoC es el lugar
        /// correcto para side effects.
        listener: (context, vizState) {
          if (vizState is GraphReady) {
            if (vizState.selectedNodeId != null) {
              _showNodeTooltip(
                  context, vizState.layout, vizState.selectedNodeId!);
            } else {
              _dismissTooltip();
            }
          }
        },
        child: BlocListener<BleBloc, BleState>(
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
            // T2.4: Registrar timestamp del último escaneo con dispositivos
            _lastScanTime = DateTime.now();
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
                  const AndroidIntent(action: 'android.settings.BLUETOOTH_SETTINGS').launch();
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
                        const AndroidIntent(action: 'android.settings.BLUETOOTH_SETTINGS').launch();
                      },
                    ),
                  // T2.4: Info bar — conteo de nodos y hora último escaneo
                  BlocBuilder<NodeListBloc, NodeListState>(
                    builder: (context, nodeState) {
                      if (nodeState is NodeListLoaded) {
                        return _buildInfoBar(nodeState.nodes.length);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  Expanded(child: _buildContent()),
                ],
              );
            },
          ),
      ),
      ),
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

  /// T2.4: Construye la barra de info superior con conteo de nodos y
  /// tiempo relativo del último escaneo.
  ///
  /// QUÉ: muestra "X nodos detectados · Ahora" o "X nodos · Hace 2 min".
  /// Solo se muestra cuando hay nodos cargados (NodeListLoaded).
  ///
  /// POR QUÉ: el usuario necesita saber cuántos nodos se detectaron y
  /// qué tan reciente fue el último escaneo, sin tener que contar los
  /// elementos en la lista.
  Widget _buildInfoBar(int nodeCount) {
    final timeText = _formatRelativeTime(_lastScanTime);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Text(
        '$nodeCount nodos detectados${timeText != null ? ' · $timeText' : ''}',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// T2.4: Formatea una marca de tiempo a texto relativo legible.
  ///
  /// - null → null (sin texto de tiempo)
  /// - < 1 minuto → "Ahora"
  /// - 1 minuto → "Hace 1 min"
  /// - >= 1 minuto → "Hace X min"
  String? _formatRelativeTime(DateTime? time) {
    if (time == null) return null;

    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Ahora';
    final minutes = diff.inMinutes;
    if (minutes == 1) return 'Hace 1 min';
    return 'Hace $minutes min';
  }

  /// Construye el contenido principal: ListView para lista,
  /// GraphView (con loading/error) para grafo, mediante AnimatedCrossFade.
  Widget _buildContent() {
    return BlocBuilder<NodeListBloc, NodeListState>(
      builder: (context, state) {
        return switch (state) {
          // F5: Estado inicial — muestra mensaje visible al usuario
          // en lugar de SizedBox.shrink (pantalla en blanco).
          // QUÉ: informa que la app está buscando nodos activamente.
          NodeListInitial() => const Center(
              child: Text(
                'Buscando nodos cercanos...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
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
                key: _graphViewKey,
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
