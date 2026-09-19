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
import 'package:frontend_mobile_nodos_app/features/scan_session/presentation/bloc/scan_session_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_event.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/bloc/visualization_state.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/graph_view_3d.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/presentation/widgets/node_tooltip.dart';

/// Pantalla principal: alterna entre lista de nodos y grafo.
///
/// Actualmente:
/// - Con 1 o más nodos activa la vista de grafo.
/// - Con 0 nodos vuelve a la vista de lista.
/// - Las vistas 2D y 3D permanecen montadas mediante Stack + Offstage.
///
/// Escucha [NodeListBloc] para cambios en la lista y
/// [VisualizationBloc] para el estado del grafo.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Controla qué hijo del AnimatedCrossFade se muestra.
  /// true = grafo (secondChild), false = lista (firstChild).
  bool _showingGraph = false;

  /// Controla si el grafo se renderiza en 3D o 2D.
  final ValueNotifier<bool> _is3D = ValueNotifier<bool>(false);

  /// Previene múltiples BluetoothOffDialog superpuestos.
  bool _dialogVisible = false;

  /// GlobalKey del GraphView 2D.
  final GlobalKey<GraphViewState> _graphViewKey = GlobalKey<GraphViewState>();

  /// Referencia al BleBloc para usar en dispose().
  BleBloc? _bleBloc;

  /// Tooltip actualmente visible.
  OverlayEntry? _tooltipEntry;

  /// ID del nodo cuyo tooltip está visible.
  int? _tooltipNodeId;

  /// Timestamp del último escaneo BLE con dispositivos.
  DateTime? _lastScanTime;

  /// Lista actual de nodos persistidos.
  ///
  /// Se usa para mapear GraphNode.id → Node.bleAddress.
  List<Node> _currentNodes = [];

  /// Último remoteId utilizado en un intento de conexión.
  ///
  /// Se usa para el botón "Reintentar".
  String? _lastRemoteId;

  /// Devuelve el ID persistente del Node que representa al dispositivo local.
  ///
  /// IMPORTANTE:
  /// - User.id pertenece a la tabla users.
  /// - User.localNodeId referencia Nodes.id del self-node.
  ///
  /// BleConnectionBloc trabaja exclusivamente con IDs de la tabla nodes,
  /// por lo que cualquier conexión debe utilizar localNodeId.
  int? _getLocalNodeId() {
    final userState = context.read<UserBloc>().state;

    if (userState is! UserLoaded) {
      return null;
    }

    return userState.user.localNodeId;
  }

  /// Abre el tooltip para un nodo específico.
  void _showNodeTooltip(BuildContext context, LayoutResult layout, int nodeId) {
    if (_tooltipNodeId == nodeId) return;

    final node = layout.nodes.firstWhere(
      (n) => n.id == nodeId,
      orElse: () => throw StateError('Nodo $nodeId no encontrado en layout'),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final is3D = _is3D.value;
      final Size screenSize = MediaQuery.of(context).size;

      final Offset globalPosition;

      if (is3D) {
        globalPosition = Offset(screenSize.width / 2, screenSize.height / 2);
      } else {
        final renderBox =
            _graphViewKey.currentContext?.findRenderObject() as RenderBox?;

        if (renderBox == null) return;

        final controller = _graphViewKey.currentState?.transformController;

        final matrix = controller?.value ?? Matrix4.identity();

        final canvasPoint = Offset(node.x, node.y);

        final viewportPoint = MatrixUtils.transformPoint(matrix, canvasPoint);

        globalPosition = renderBox.localToGlobal(viewportPoint);
      }

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

        // BUG-001:
        //
        // Antes se usaba User.id como myNodeId.
        //
        // Eso era incorrecto porque User.id pertenece a la tabla users,
        // mientras que ConnectToDevice.myNodeId representa Nodes.id.
        //
        // ARCH-001 introdujo User.localNodeId como referencia explícita
        // al Node persistente que representa este dispositivo.
        onEnlazar: () {
          final bleAddress = _currentNodes
              .where((n) => n.id == node.id)
              .map((n) => n.bleAddress)
              .firstOrNull;

          if (bleAddress != null && mounted) {
            //final userState = context.read<UserBloc>().state;

            //final myNodeId = userState is UserLoaded
            //  ? userState.user.localNodeId
            // : null;
            final myNodeId = _getLocalNodeId();

            if (myNodeId != null) {
              context.read<BleConnectionBloc>().add(
                ConnectToDevice(bleAddress, myNodeId: myNodeId),
              );
            }
          }

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

  @override
  void initState() {
    super.initState();

    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        _is3D.value = prefs.getBool('is3D') ?? false;
      }
    });

    _bleBloc = context.read<BleBloc>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      context.read<NodeListBloc>().add(const LoadNodes());

      _bleBloc!.add(const StartScan());
    });
  }

  @override
  void dispose() {
    _bleBloc?.add(const StopScan());

    _tooltipEntry?.remove();

    _is3D.dispose();

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
        listener: (context, connectionState) {
          switch (connectionState) {
            case BleConnecting(:final remoteId):
              _lastRemoteId = remoteId;

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
                const SnackBar(
                  content: Text(
                    'Conectado ✅',
                    style: TextStyle(color: Colors.greenAccent),
                  ),
                  duration: Duration(seconds: 3),
                ),
              );

            case BleConnectionError(:final message, :final retryable):
              ScaffoldMessenger.of(context).hideCurrentSnackBar();

              final action = retryable
                  ? SnackBarAction(
                      label: 'Reintentar',

                      // BUG-001:
                      //
                      // Al reintentar debemos utilizar exactamente
                      // el mismo ID de Node local utilizado en el
                      // enlace inicial.
                      //
                      // User.id NO representa un nodo.
                      //
                      // User.localNodeId → Nodes.id del self-node.
                      onPressed: () {
                        if (_lastRemoteId != null && mounted) {
                          //  final userState = context.read<UserBloc>().state;

                          // final myNodeId = userState is UserLoaded
                          //   ? userState.user.localNodeId
                          // : null;

                          final myNodeId = _getLocalNodeId();
                          if (myNodeId != null) {
                            context.read<BleConnectionBloc>().add(
                              ConnectToDevice(
                                _lastRemoteId!,
                                myNodeId: myNodeId,
                              ),
                            );
                          }
                        }
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

            case RemoteIdentityLoaded(
              :final remoteId,
              :final uuid,
              :final name,
              :final color,
            ):
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;

                final node = _currentNodes
                    .where((n) => n.bleAddress == remoteId)
                    .firstOrNull;

                if (node != null && node.id != null) {
                  context.read<NodeListBloc>().add(
                    UpdateNodeIdentity(
                      nodeId: node.id!,
                      deviceUuid: uuid,
                      name: name,
                      color: color,
                    ),
                  );
                }
              });

            case RemoteIdentityUnavailable(:final remoteId):
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;

                final node = _currentNodes
                    .where((n) => n.bleAddress == remoteId)
                    .firstOrNull;

                if (node != null) {
                  showModalBottomSheet<void>(
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
              break;
          }
        },
        child: BlocListener<VisualizationBloc, VisualizationState>(
          listener: (context, vizState) {
            if (vizState is GraphReady) {
              if (vizState.selectedNodeId != null) {
                _showNodeTooltip(
                  context,
                  vizState.layout,
                  vizState.selectedNodeId!,
                );
              } else {
                _dismissTooltip();
              }
            }
          },
          child: BlocListener<BleBloc, BleState>(
            listener: (context, bleState) {
              if (bleState is BleScanning && bleState.devices.isNotEmpty) {
                context.read<NodeListBloc>().add(
                  SyncBleDevices(bleState.devices),
                );

                _lastScanTime = DateTime.now();
              }

              if (bleState is BluetoothOff) {
                if (!_dialogVisible) {
                  _dialogVisible = true;

                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => BluetoothOffDialog(
                      onGoToSettings: () {
                        _dialogVisible = false;

                        const AndroidIntent(
                          action: 'android.settings.BLUETOOTH_SETTINGS',
                        ).launch();
                      },
                      onCancel: () {
                        _dialogVisible = false;
                      },
                    ),
                  );
                }

                context.read<NodeListBloc>().add(const ClearNodes());

                final sessionBloc = context.read<ScanSessionBloc>();

                final sessionState = sessionBloc.state;

                if (sessionState is SessionActive) {
                  sessionBloc.add(EndSession(sessionState.sessionId));
                }
              }

              if (bleState is BleStopped || bleState is BleScanning) {
                _dialogVisible = false;
              }

              if (bleState is BleStopped) {
                final sessionBloc = context.read<ScanSessionBloc>();

                final sessionState = sessionBloc.state;

                if (sessionState is SessionActive) {
                  sessionBloc.add(EndSession(sessionState.sessionId));
                }
              }
            },
            child: BlocListener<NodeListBloc, NodeListState>(
              listener: (context, nodeListState) {
                if (nodeListState is NodeListLoaded) {
                  _currentNodes = nodeListState.nodes;

                  final sessionBloc = context.read<ScanSessionBloc>();

                  final sessionState = sessionBloc.state;

                  if (sessionState is! SessionActive) {
                    sessionBloc.add(const StartSession());
                  } else {
                    if (nodeListState.nodes.isNotEmpty) {
                      final nodeIds = nodeListState.nodes
                          .map((n) => n.id)
                          .whereType<int>()
                          .toList();

                      if (nodeIds.isNotEmpty) {
                        sessionBloc.add(
                          AddNodesToSession(sessionState.sessionId, nodeIds),
                        );
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
                      'Sesión ${sessionState.sessionId} activa — '
                      '${sessionState.nodeCount} nodos',
                    );
                  } else if (sessionState is SessionEnded) {
                    debugPrint('Sesión finalizada');
                  } else if (sessionState is SessionError) {
                    debugPrint(
                      'Error de sesión: '
                      '${sessionState.message}',
                    );
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
                                action: 'android.settings.BLUETOOTH_SETTINGS',
                              ).launch();
                            },
                          ),
                        BlocBuilder<NodeListBloc, NodeListState>(
                          builder: (context, nodeState) {
                            if (nodeState is NodeListLoaded) {
                              return _buildInfoBar(nodeState.nodes.length);
                            }

                            return const SizedBox.shrink();
                          },
                        ),
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
      ),
    );
  }

  /// Cambia entre lista y grafo según cantidad de nodos.
  void _updateViewMode(List<Node> nodes, BuildContext context) {
    final count = nodes.length;

    if (count >= 1) {
      if (!_showingGraph) {
        setState(() => _showingGraph = true);
      }

      final sessionState = context.read<ScanSessionBloc>().state;

      if (sessionState is SessionActive) {
        final userBloc = context.read<UserBloc>();

        final userState = userBloc.state;

        final String? myUuid = userBloc.myDeviceUuid;

        final String? userName = userState is UserLoaded
            ? userState.user.name
            : null;

        final String? userColor = userState is UserLoaded
            ? userState.user.color
            : null;

        context.read<VisualizationBloc>().add(
          BuildGraphRequested(
            scanSessionId: sessionState.sessionId,
            nodes: nodes,
            myDeviceUuid: myUuid,
            userName: userName,
            userColor: userColor,
          ),
        );
      }
    } else if (_showingGraph) {
      setState(() => _showingGraph = false);
    }
  }

  /// Barra superior con cantidad de nodos y tiempo del último escaneo.
  Widget _buildInfoBar(int nodeCount) {
    final timeText = _formatRelativeTime(_lastScanTime);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Text(
        '$nodeCount nodos detectados'
        '${timeText != null ? ' · $timeText' : ''}',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String? _formatRelativeTime(DateTime? time) {
    if (time == null) {
      return null;
    }

    final diff = DateTime.now().difference(time);

    if (diff.inSeconds < 60) {
      return 'Ahora';
    }

    final minutes = diff.inMinutes;

    if (minutes == 1) {
      return 'Hace 1 min';
    }

    return 'Hace $minutes min';
  }

  /// Construye el contenido principal.
  Widget _buildContent() {
    return BlocBuilder<NodeListBloc, NodeListState>(
      builder: (context, state) {
        return switch (state) {
          NodeListInitial() => const Center(
            child: Text(
              'Buscando nodos cercanos...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
          NodeListLoading() => const Center(child: CircularProgressIndicator()),
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

  /// Alterna entre lista y grafo respetando el viewport disponible.
  ///
  /// LayoutBuilder captura las restricciones finitas proporcionadas por
  /// Expanded. SizedBox fuerza a que tanto la lista como el grafo trabajen
  /// dentro del mismo viewport.
  ///
  /// Las vistas 2D y 3D permanecen montadas mediante Stack + Offstage.
  Widget _buildAnimatedContent(List<Node> nodes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: _showingGraph
              ? BlocBuilder<VisualizationBloc, VisualizationState>(
                  builder: (context, vizState) {
                    return switch (vizState) {
                      VisualizationInitial() || GraphBuilding() => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      GraphReady(
                        :final layout,
                        :final selectedNodeId,
                        :final barycenter,
                      ) =>
                        ValueListenableBuilder<bool>(
                          valueListenable: _is3D,
                          builder: (context, is3D, _) {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Offstage(
                                  offstage: is3D,
                                  child: GraphView(
                                    key: _graphViewKey,
                                    layout: layout,
                                    selectedNodeId: selectedNodeId,
                                    barycenter: barycenter,
                                    onNodeTapped: (nodeId) {
                                      context.read<VisualizationBloc>().add(
                                        NodeSelected(nodeId),
                                      );
                                    },
                                  ),
                                ),
                                Offstage(
                                  offstage: !is3D,
                                  child: GraphView3D(
                                    layout: layout,
                                    onNodeTapped: (nodeId) {
                                      context.read<VisualizationBloc>().add(
                                        NodeSelected(nodeId),
                                      );
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
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      _ => const SizedBox.shrink(),
                    };
                  },
                )
              : _buildListView(nodes),
        );

        return viewport;
      },
    );
  }

  /// Toolbar para alternar entre vista 2D y 3D.
  Widget _buildGraphToolbar() {
    return ValueListenableBuilder<bool>(
      valueListenable: _is3D,
      builder: (context, is3D, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
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
                  _is3D.value = !_is3D.value;

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

  /// Lista tradicional de nodos.
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
