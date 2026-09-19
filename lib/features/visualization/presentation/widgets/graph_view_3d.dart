import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Vista interactiva 3D del grafo.
///
/// Three.js se ejecuta dentro de un WebView y recibe una representación
/// serializada del mismo [LayoutResult] utilizado por la vista 2D.
///
/// La vista 3D conserva la misma semántica que la vista 2D:
///
/// - mismos nodos;
/// - mismas conexiones;
/// - mismos colores;
/// - mismo self-node;
/// - mismo nodo seleccionado;
/// - mismos tamaños;
///
/// La única diferencia intencional es la representación espacial 3D.
class GraphView3D extends StatefulWidget {
  final LayoutResult layout;

  /// Nodo seleccionado actualmente.
  ///
  /// Se envía a Three.js para que la selección visual sea equivalente
  /// a la implementada por GraphPainter en 2D.
  final int? selectedNodeId;

  /// Callback ejecutado cuando el usuario toca un nodo en Three.js.
  final void Function(int nodeId)? onNodeTapped;

  const GraphView3D({
    super.key,
    required this.layout,
    this.selectedNodeId,
    this.onNodeTapped,
  });

  @override
  State<GraphView3D> createState() => _GraphView3DState();
}

class _GraphView3DState extends State<GraphView3D> {
  late final WebViewController _controller;

  /// Indica que graph_3d.html terminó de cargarse.
  bool _pageLoaded = false;

  /// Último payload pendiente de enviar a Three.js.
  ///
  /// Si Flutter actualiza el layout o la selección antes de que el HTML
  /// termine de cargar, conservamos únicamente el estado más reciente.
  String? _pendingData;

  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _controller = _createController();
    _loadContent();
  }

  /// Reinyecta el estado cuando cambia:
  ///
  /// - el layout;
  /// - el nodo seleccionado.
  ///
  /// Esto es necesario para mantener paridad funcional 2D ↔ 3D.
  @override
  void didUpdateWidget(covariant GraphView3D oldWidget) {
    super.didUpdateWidget(oldWidget);

    final layoutChanged = widget.layout != oldWidget.layout;

    final selectionChanged = widget.selectedNodeId != oldWidget.selectedNodeId;

    if (layoutChanged || selectionChanged) {
      _injectData();
    }
  }

  /// Configura el WebView y los canales JavaScript.
  WebViewController _createController() {
    final controller = WebViewController();

    controller.setJavaScriptMode(JavaScriptMode.unrestricted);

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!mounted) {
            return;
          }

          setState(() {
            _pageLoaded = true;
            _isLoading = false;
          });

          _flushPendingData();
        },

        onWebResourceError: (error) {
          // Algunos WebResourceError pueden corresponder a recursos
          // secundarios del documento. Solo registramos el problema para
          // diagnóstico; la carga principal continúa controlándose también
          // mediante el try/catch de _loadContent().
          debugPrint(
            '[3D WebView] Resource error: '
            '${error.errorCode} ${error.description}',
          );
        },
      ),
    );

    // Three.js → Flutter.
    controller.addJavaScriptChannel(
      'onNodeTapped',
      onMessageReceived: (JavaScriptMessage message) {
        if (!mounted) {
          return;
        }

        final nodeId = int.tryParse(message.message);

        if (nodeId != null) {
          widget.onNodeTapped?.call(nodeId);
        }
      },
    );

    // Consola JS → Flutter.
    controller.addJavaScriptChannel(
      'onConsoleLog',
      onMessageReceived: (JavaScriptMessage message) {
        debugPrint('[3D WebView] ${message.message}');
      },
    );

    return controller;
  }

  /// Carga el documento HTML que contiene la escena Three.js.
  Future<void> _loadContent() async {
    try {
      await _controller.loadFlutterAsset('assets/three_graph/graph_3d.html');

      // Puede que onPageFinished todavía no haya ocurrido.
      // En ese caso _injectData() guarda el payload como pendiente.
      _injectData();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _hasError = true;
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// Serializa el estado completo de visualización y lo envía a Three.js.
  ///
  /// No enviamos únicamente el layout: también incluimos selectedNodeId,
  /// porque la selección forma parte del estado visual compartido entre
  /// las vistas 2D y 3D.
  void _injectData() {
    final payload = layoutResultToJson(
      widget.layout,
      selectedNodeId: widget.selectedNodeId,
    );

    final json = jsonEncode(payload);

    if (!_pageLoaded) {
      _pendingData = json;
      return;
    }

    _runGraphInjection(json);
  }

  /// Envía cualquier estado acumulado mientras cargaba el WebView.
  void _flushPendingData() {
    final data = _pendingData;

    if (data == null) {
      // Si por algún motivo todavía no existe payload pendiente,
      // generar uno con el estado actual.
      _injectData();
      return;
    }

    _pendingData = null;

    _runGraphInjection(data);
  }

  /// Ejecuta la función pública definida por graph_3d.js.
  ///
  /// Se mantiene aislada para centralizar el manejo de errores de
  /// comunicación Flutter → JavaScript.
  Future<void> _runGraphInjection(String json) async {
    if (!_pageLoaded) {
      _pendingData = json;
      return;
    }

    try {
      await _controller.runJavaScript('window.loadGraphData($json);');
    } catch (e) {
      debugPrint('[3D WebView] Error inyectando datos: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorState();
    }

    if (_isLoading) {
      return _buildLoadingState();
    }

    if (widget.layout.nodes.isEmpty) {
      return _buildEmptyState();
    }

    return WebViewWidget(controller: _controller);
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Cargando visualización 3D…',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'No hay nodos para visualizar en 3D',
        style: TextStyle(fontSize: 14, color: Colors.grey),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Error al cargar visualización 3D',
              style: TextStyle(
                fontSize: 14,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    try {
      _controller.removeJavaScriptChannel('onNodeTapped');
    } catch (_) {
      // El canal puede no estar disponible en ciertos entornos de test.
    }

    try {
      _controller.removeJavaScriptChannel('onConsoleLog');
    } catch (_) {
      // El canal puede no estar disponible en ciertos entornos de test.
    }

    try {
      _controller.clearCache();
    } catch (_) {
      // Ignorar errores de plataforma durante dispose.
    }

    super.dispose();
  }
}

/// Serializa [LayoutResult] al contrato utilizado por graph_3d.js.
///
/// La estructura mantiene la semántica necesaria para conseguir paridad
/// funcional con GraphPainter.
///
/// Ejemplo:
///
/// ```json
/// {
///   "selectedNodeId": 4,
///   "nodes": [
///     {
///       "id": 4,
///       "x": 1000,
///       "y": 1000,
///       "z": 500,
///       "radius": 25,
///       "color": "#E91E63",
///       "label": "Mi dispositivo",
///       "isSelf": true,
///       "userColor": "#E91E63",
///       "estimatedDistance": 0.5
///     }
///   ],
///   "edges": [
///     {
///       "fromId": 4,
///       "toId": 7,
///       "thickness": 1,
///       "edgeType": "direct"
///     }
///   ]
/// }
/// ```
Map<String, dynamic> layoutResultToJson(
  LayoutResult layout, {
  int? selectedNodeId,
}) {
  return {
    'selectedNodeId': selectedNodeId,

    'nodes': layout.nodes.map((node) {
      return {
        'id': node.id,
        'x': node.x,
        'y': node.y,
        'z': node.z,
        'radius': node.radius,

        // IMPORTANTE:
        // 2D utiliza displayColor, por lo que 3D debe utilizar exactamente
        // la misma fuente para conservar paridad visual.
        'color': _colorToHex(node.displayColor),

        'label': node.label,
        'isSelf': node.isSelf,

        // Color específico del perfil para identificar el self-node.
        'userColor': node.userColor != null
            ? _colorToHex(node.userColor!)
            : null,

        // Se envía ahora aunque el JS actual todavía no lo renderice.
        // Nos permitirá implementar labels equivalentes en el siguiente
        // cambio sin volver a modificar el contrato Flutter → Three.js.
        'estimatedDistance': node.estimatedDistance,
      };
    }).toList(),

    'edges': layout.edges.map((edge) {
      return {
        'fromId': edge.fromId,
        'toId': edge.toId,
        'thickness': edge.thickness,

        // No acoplamos JavaScript al enum completo de Dart.
        // El contrato externo recibe simplemente "direct" o "transitive".
        'edgeType': edge.edgeType.name,
      };
    }).toList(),
  };
}

/// Convierte un color ARGB de Flutter:
///
///     0xFFE91E63
///
/// a:
///
///     #E91E63
///
/// El alpha se elimina porque Three.js recibe el color RGB por separado
/// de cualquier configuración de opacidad del material.
String _colorToHex(int argb) {
  final rgb = argb & 0x00FFFFFF;

  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
