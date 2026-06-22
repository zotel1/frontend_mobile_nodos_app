import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_mobile_nodos_app/core/di/injection_container.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/widgets/bluetooth_off_banner.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/widgets/bluetooth_off_dialog.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/widgets/node_metadata_sheet.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/widgets/node_tile.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view_3d.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/node_tooltip.dart';
import 'package:frontend_mobile_nodos_app/features/scan_session/presentation/bloc/scan_session_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
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

  /// T2.9: Controla si el grafo se renderiza en 3D (WebView) o 2D (CustomPainter).
  /// `ValueNotifier<bool>` permite que el toolbar use ValueListenableBuilder
  /// para rebuilds limitados, sin reconstruir todo HomePage (R9).
  final ValueNotifier<bool> _is3D = ValueNotifier<bool>(false);

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

  /// T3.8: Lista actual de nodos persistidos (Drift).
  ///
  /// Se actualiza en el [BlocListener<NodeListBloc>] cada vez que se
  /// emite [NodeListLoaded]. Se usa para mapear [GraphNode].id → [Node].bleAddress
  /// cuando el usuario presiona "Enlazar" en el tooltip.
  List<Node> _currentNodes = [];

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
        // T3.8: Al presionar "Enlazar", despacha ConnectToDevice al BleConnectionBloc.
        // Mapea GraphNode.id → Node.bleAddress usando la lista de nodos actual.
        onEnlazar: () {
          final bleAddress = _currentNodes
              .where((n) => n.id == node.id)
              .map((n) => n.bleAddress)
              .firstOrNull;
          if (bleAddress != null && mounted) {
            final userState = context.read<UserBloc>().state;
            final myNodeId = userState is UserLoaded ? userState.user.id : null;
            if (myNodeId != null) {
              context
                  .read<BleConnectionBloc>()
                  .add(ConnectToDevice(bleAddress, myNodeId: myNodeId));
            }
          }
          // Cerrar tooltip después de presionar Enlazar
          _tooltipEntry?.remove();
          _tooltipEntry = null;
          _tooltipNodeId = null;
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
  /// T3.8: Carga la preferencia is3D desde SharedPreferences vía GetIt DI.
  /// NOTA: usa sl<SharedPreferences>() — sincrónico porque la instancia
  /// ya está registrada como lazySingleton en injection_container.dart.
  @override
  void initState() {
    super.initState();
    // T3.6 (R12): Cargar preferencia is3D desde SharedPreferences vía GetIt DI.
    // sl<SharedPreferences>() es sincrónico — no necesita .then() ni await.
    final prefs = sl<SharedPreferences>();
    _is3D.value = prefs.getBool('is3D') ?? false;
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
    _is3D.dispose(); // T2.9: liberar ValueNotifier
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
      body: BlocListener<BleConnectionBloc, BleConnectionState>(
        /// T3.9: Muestra el estado de la conexión GATT como SnackBar.
        /// T3.8: Maneja RemoteIdentityLoaded y RemoteIdentityUnavailable
        /// para actualizar metadata o mostrar bottom sheet (R5.5).
        ///
        /// - BleConnecting → "Conectando..."
        /// - BleConnected → "Conectado ✅" (verde)
        /// - BleConnectionError → muestra el error
        /// - RemoteIdentityLoaded → actualiza nombre y color del nodo
        /// - RemoteIdentityUnavailable → abre bottom sheet de metadata
        listener: (context, connectionState) {
          switch (connectionState) {
            case BleConnecting(:final remoteId):
              // Buscar nombre del nodo para el mensaje
              final nodeName = _currentNodes
                  .where((n) => n.bleAddress == remoteId)
                  .map((n) => n.name ?? n.suggestedName ?? 'dispositivo')
                  .firstOrNull;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Conectando a ${nodeName ?? remoteId}...'),
                  duration: const Duration(seconds: 10),
                ),
              );
            case BleConnected():
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Conectado ✅',
                    style: TextStyle(color: Colors.greenAccent),
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
            case BleConnectionError(:final message, :final retryable):
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              final action = retryable
                  ? SnackBarAction(
                      label: 'Reintentar',
                      onPressed: () {
                        // Reintentar con el último remoteId conocido
                      },
                    )
                  : null;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: $message'),
                  backgroundColor: Colors.red.shade700,
                  duration: const Duration(seconds: 5),
                  action: action,
                ),
              );
            // T3.8: Identidad remota cargada — actualizar nodo automáticamente
            // Usa addPostFrameCallback para que _currentNodes esté poblado
            // por el BlocListener<NodeListBloc> antes de buscar el nodo.
            case RemoteIdentityLoaded(:final remoteId, :final name, :final color):
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final node = _currentNodes
                    .where((n) => n.bleAddress == remoteId)
                    .firstOrNull;
                if (node != null && node.id != null) {
                  context
                      .read<NodeListBloc>()
                      .add(UpdateNodeName(node.id!, name));
                  context
                      .read<NodeListBloc>()
                      .add(UpdateNodeColor(node.id!, color));
                }
              });
            // T3.8: Identidad no disponible — abrir bottom sheet manual
            case RemoteIdentityUnavailable(:final remoteId):
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final node = _currentNodes
                    .where((n) => n.bleAddress == remoteId)
                    .firstOrNull;
                if (node != null) {
                  showModalBottomSheet(
                    context: context,
                    builder: (_) => NodeMetadataSheet(
                      node: node,
                      nodeListBloc: context.read<NodeListBloc>(),
                    ),
                  );
                }
              });
            case BleConnectionInitial():
            case ConnectionInserted():
              // Nada que mostrar — estados informativos
              break;
          }
        },
        child: BlocListener<VisualizationBloc, VisualizationState>(
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
            // PR1: StartSession se movió al listener de NodeListBloc
            // para secuenciar correctamente SyncBleDevices → StartSession
            // → AddNodesToSession → BuildGraphRequested (R3).
          }
          // Mostrar diálogo cuando BT está apagado.
          // El guard _dialogVisible previene stacking de múltiples diálogos.
          // T3.8: También despacha ClearNodes para limpiar el contador (R5.17).
          if (bleState is BluetoothOff) {
            if (!_dialogVisible) {
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
            // Limpiar nodos cuando BT se apaga
            context.read<NodeListBloc>().add(const ClearNodes());
            // Finalizar sesión activa
            final sessionBloc = context.read<ScanSessionBloc>();
            final sessionState = sessionBloc.state;
            if (sessionState is SessionActive) {
              sessionBloc.add(EndSession(sessionState.sessionId));
            }
          }
          // Si BT vuelve a estar disponible, reseteamos el guard.
          if (bleState is BleStopped || bleState is BleScanning) {
            _dialogVisible = false;
          }
          // Finalizar sesión cuando el escaneo se detiene
          if (bleState is BleStopped) {
            final sessionBloc = context.read<ScanSessionBloc>();
            final sessionState = sessionBloc.state;
            if (sessionState is SessionActive) {
              sessionBloc.add(EndSession(sessionState.sessionId));
            }
          }
        },
        child: BlocListener<NodeListBloc, NodeListState>(
        // Dispara la construcción del grafo cuando la lista cambia.
        // Usa listener (no builder) para side effects — no dispara
        // reconstrucciones innecesarias.
        listener: (context, nodeListState) {
          if (nodeListState is NodeListLoaded) {
            // T3.8: Guardar la lista actual de nodos para mapeo GraphNode.id → bleAddress
            _currentNodes = nodeListState.nodes;
            // PR1: Secuenciar eventos — StartSession primero si no hay sesión,
            // luego AddNodesToSession + BuildGraphRequested cuando la sesión
            // esté activa (R3). Esto evita la race condition donde StartSession
            // y SyncBleDevices se despachaban en paralelo desde listeners distintos.
            final sessionBloc = context.read<ScanSessionBloc>();
            final sessionState = sessionBloc.state;
            if (sessionState is! SessionActive) {
              // Iniciar sesión si no hay una activa.
              // Los nodos se agregarán en el próximo ciclo cuando SessionActive
              // sea emitido y NodeListLoaded vuelva a dispararse.
              sessionBloc.add(const StartSession());
            } else {
              // Sesión ya activa: agregar nodos detectados y construir grafo.
              if (nodeListState.nodes.isNotEmpty) {
                final nodeIds = nodeListState.nodes
                    .map((n) => n.id)
                    .whereType<int>()
                    .toList();
                if (nodeIds.isNotEmpty) {
                  sessionBloc.add(
                      AddNodesToSession(sessionState.sessionId, nodeIds));
                }
              }
            }
            _updateViewMode(nodeListState.nodes, context);
          }
        },
          child: BlocListener<ScanSessionBloc, ScanSessionState>(
            listener: (context, sessionState) {
              if (sessionState is SessionActive) {
                debugPrint(
                    'Sesión ${sessionState.sessionId} activa — ${sessionState.nodeCount} nodos');
              } else if (sessionState is SessionEnded) {
                debugPrint('Sesión finalizada');
              } else if (sessionState is SessionError) {
                debugPrint('Error de sesión: ${sessionState.message}');
              }
            },
            child: BlocBuilder<BleBloc, BleState>(
              builder: (context, bleState) {
                return Column(
                  children: [
                    if (bleState is BluetoothOff)
                      BluetoothOffBanner(
                        onGoToSettings: () {
                          const AndroidIntent(
                                  action:
                                      'android.settings.BLUETOOTH_SETTINGS')
                              .launch();
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
                  // T5.6: Toolbar de grafo con toggle 2D/3D (solo visible en modo grafo)
              if (_showingGraph) _buildGraphToolbar(),
              Expanded(child: _buildContent()),
                ],
              );
            },
            ),
          ),
      ),
      ),
      ),
      ), // cierra BlocListener<BleConnectionBloc>
    );
  }

  /// Aplica histéresis al modo de visualización según la cantidad de nodos.
  ///
  /// Umbrales (T3.8: threshold reducido a ≥1 — R5.12):
  /// - ≥1 nodo: activa modo grafo (si no estaba activo) y dispara
  ///   la construcción del layout usando la sesión activa del ScanSessionBloc.
  /// - 0 nodos: vuelve a modo lista (si estaba en grafo).
  void _updateViewMode(List<Node> nodes, BuildContext context) {
    final count = nodes.length;

    if (count >= 1) {
      if (!_showingGraph) {
        setState(() => _showingGraph = true);
      }
      // Disparar construcción del grafo con la sesión activa
      final sessionState = context.read<ScanSessionBloc>().state;
      if (sessionState is SessionActive) {
        context.read<VisualizationBloc>().add(BuildGraphRequested(
          scanSessionId: sessionState.sessionId,
          nodes: nodes,
        ));
      }
    } else if (_showingGraph) {
      setState(() => _showingGraph = false);
    }
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
  ///
  /// T5.7: Wiring — alterna entre GraphView (CustomPainter 2D) y
  /// GraphView3D (WebView Three.js) según [_is3D].
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
            GraphReady(:final layout, :final selectedNodeId,
                :final barycenter) =>
              // T2.8: Stack+Offstage mantiene ambos widgets en el árbol (R9, R10).
              // Ambos GraphView (2D) y GraphView3D (3D) se crean y se mantienen
              // vivos siempre. Offstage oculta el que no está activo pero NO lo
              // destruye, preservando el WebViewController 3D entre toggles.
              //
              // T2.9: ValueListenableBuilder limita el rebuild solo al Stack
              // cuando _is3D cambia, sin reconstruir todo HomePage (R9).
              ValueListenableBuilder<bool>(
                valueListenable: _is3D,
                builder: (context, is3D, _) {
                  return Stack(
                    children: [
                      // Vista 2D — offstage cuando is3D = true
                      Offstage(
                        offstage: is3D,
                        child: GraphView(
                          key: _graphViewKey,
                          layout: layout,
                          selectedNodeId: selectedNodeId,
                          barycenter: barycenter,
                          onNodeTapped: (nodeId) {
                            context
                                .read<VisualizationBloc>()
                                .add(NodeSelected(nodeId));
                          },
                        ),
                      ),
                      // Vista 3D — offstage cuando is3D = false
                      Offstage(
                        offstage: !is3D,
                        child: GraphView3D(
                          layout: layout,
                          onNodeTapped: (nodeId) {
                            context
                                .read<VisualizationBloc>()
                                .add(NodeSelected(nodeId));
                          },
                        ),
                      ),
                    ],
                  );
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

  /// T2.9: Barra de herramientas del grafo con toggle 2D/3D.
  ///
  /// QUÉ: usa ValueListenableBuilder para reconstruir SOLO el toolbar
  /// cuando _is3D cambia, sin rebuild de todo HomePage (R9).
  /// El icono y texto reflejan el estado actual.
  /// Solo se muestra en modo grafo ([_showingGraph] == true).
  /// POR QUÉ: R6.1 — el usuario debe poder alternar entre las dos vistas.
  Widget _buildGraphToolbar() {
    return ValueListenableBuilder<bool>(
      valueListenable: _is3D,
      builder: (context, is3D, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                is3D ? 'Vista 3D' : 'Vista 2D',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(is3D ? Icons.grid_view : Icons.view_in_ar),
                tooltip: is3D ? 'Cambiar a vista 2D' : 'Cambiar a vista 3D',
                onPressed: () {
                  // T2.9: ValueNotifier elimina setState — el toolbar
                  // se reconstruye automáticamente vía ValueListenableBuilder.
                  _is3D.value = !_is3D.value;
                  // T2.10: Persistir preferencia is3D vía GetIt (R12)
                  sl<SharedPreferences>().setBool('is3D', _is3D.value);
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
        onTap: () => context.push('/node/${nodes[index].id}'),
      ),
    );
  }
}
