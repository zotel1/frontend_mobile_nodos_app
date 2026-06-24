import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:frontend_mobile_nodos_app/features/visualization/domain/entities/layout_result.dart';

/// Widget que renderiza el grafo de nodos en 3D usando Three.js
/// dentro de un WebView.
///
/// Recibe un [LayoutResult] con nodos posicionados y aristas, serializa
/// a JSON, y lo inyecta en el WebView mediante `runJavaScript`.
/// La comunicación inversa (tap en nodo 3D → Dart) se realiza vía
/// `JavaScriptChannel('onNodeTapped')`.
///
/// FIX(PR2): La inyección de datos ahora espera a que la página
/// termine de cargar (onPageFinished) para evitar pantalla en blanco.
/// Si los datos llegan antes, se almacenan en [_pendingData] y se
/// inyectan cuando el callback lo indique.
///
/// Parámetros:
/// - [layout]: resultado del algoritmo FR con nodos y aristas
/// - [onNodeTapped]: callback al tocar un nodo en 3D, recibe el nodeId
class GraphView3D extends StatefulWidget {
  final LayoutResult layout;
  final void Function(int nodeId)? onNodeTapped;

  const GraphView3D({
    super.key,
    required this.layout,
    this.onNodeTapped,
  });

  @override
  State<GraphView3D> createState() => _GraphView3DState();
}

class _GraphView3DState extends State<GraphView3D> {
  late final WebViewController _controller;

  /// Flag que indica si la página HTML ya terminó de cargar.
  /// true → es seguro llamar a _injectData().
  bool _pageLoaded = false;

  /// Datos pendientes de inyectar si llegaron antes de
  /// que la página terminara de cargar.
  String? _pendingData;

  /// T2.5: Estados visuales del widget.
  /// _isLoading: true mientras el WebView inicializa (R6).
  /// _hasError: true si la carga del asset HTML falló (R8).
  /// _errorMessage: mensaje descriptivo del error para debug.
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    _loadContent();
  }

  /// Reinyecta datos cuando el layout cambia después de la primera build.
  ///
  /// QUÉ: compara el layout actual con el anterior y, si cambió,
  /// vuelve a serializar e inyectar los datos en el WebView.
  ///
  /// POR QUÉ: sin didUpdateWidget, el grafo 3D solo se renderizaba
  /// en la primera build. Si el layout cambiaba después (nuevo scan,
  /// recálculo FR con más nodos), el WebView seguía mostrando
  /// los datos viejos.
  @override
  void didUpdateWidget(covariant GraphView3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.layout != oldWidget.layout) {
      _injectData();
    }
  }

  /// Crea y configura el WebViewController con los canales JavaScript
  /// para recibir eventos de tap en nodos y logs de consola.
  WebViewController _createController() {
    final controller = WebViewController();

    /// Callback que se dispara cuando la página HTML termina de cargar.
    /// Si hay datos pendientes de [_pendingData], se inyectan aquí.
    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!mounted) return;
          setState(() {
            _pageLoaded = true;
            _isLoading = false; // T2.5: salir del estado loading (R6)
          });
          if (_pendingData != null) {
            _controller.runJavaScript(
                'window.loadGraphData($_pendingData)');
            _pendingData = null;
          }
        },
      ),
    );

    // Canal de comunicación JS → Dart para detección de tap en nodos.
    // graph_3d.js llama a onNodeTapped.postMessage(nodeId) al tocar una esfera.
    controller.addJavaScriptChannel(
      'onNodeTapped',
      onMessageReceived: (JavaScriptMessage message) {
        final nodeId = int.tryParse(message.message);
        if (nodeId != null) {
          widget.onNodeTapped?.call(nodeId);
        }
      },
    );

    // Canal de logs de consola JS → Dart para depuración.
    // Captura console.log/error/warn del WebView para diagnosticar
    // errores en la escena Three.js sin necesidad de DevTools.
    controller.addJavaScriptChannel(
      'onConsoleLog',
      onMessageReceived: (JavaScriptMessage message) {
        debugPrint('[3D WebView] ${message.message}');
      },
    );

    return controller;
  }

  /// Carga el HTML del grafo 3D desde los assets e inyecta los datos.
  /// Si la página ya cargó, inyecta directamente; si no, almacena en
  /// [_pendingData] para que [onPageFinished] la inyecte.
  ///
  /// T2.5: Envolver en try/catch para capturar fallos de carga del asset.
  /// Si el asset no existe o hay error de plataforma, se activa
  /// [_hasError] y se muestra el estado de error (R8).
  Future<void> _loadContent() async {
    try {
      await _controller.loadFlutterAsset('assets/three_graph/graph_3d.html');
      _injectData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// Serializa el [LayoutResult] a JSON y lo inyecta en el WebView
  /// llamando a `window.loadGraphData(json)` en el contexto JavaScript.
  ///
  /// Si la página aún no terminó de cargar ([_pageLoaded] = false),
  /// almacena el JSON en [_pendingData] para inyectarlo en
  /// [onPageFinished].
  void _injectData() {
    final json = jsonEncode(layoutResultToJson(widget.layout));
    if (_pageLoaded) {
      _controller.runJavaScript('window.loadGraphData($json)');
    } else {
      _pendingData = json;
    }
  }

  /// Construye el widget según el estado actual:
  ///
  /// 1. **_isLoading = true**: muestra CircularProgressIndicator + "Cargando…" (R6)
  /// 2. **_hasError = true**: muestra mensaje de error + texto "Error al cargar…" (R8)
  /// 3. **layout.nodes.isEmpty y _pageLoaded**: muestra "No hay nodos…" (R7)
  /// 4. **default**: WebViewWidget con Three.js
  @override
  Widget build(BuildContext context) {
    // T2.6: Estado de error (R8) — prioridad más alta
    if (_hasError) {
      return _buildErrorState();
    }

    // T2.6: Estado de carga (R6)
    if (_isLoading) {
      return _buildLoadingState();
    }

    // T2.6: Estado vacío (R7) — sin nodos para visualizar
    if (widget.layout.nodes.isEmpty) {
      return _buildEmptyState();
    }

    // T2.6: Estado normal — WebView con Three.js
    return WebViewWidget(controller: _controller);
  }

  /// Construye el estado de carga: spinner + texto "Cargando…" (R6).
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

  /// Construye el estado vacío: texto informativo (R7).
  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'No hay nodos para visualizar en 3D',
        style: TextStyle(fontSize: 14, color: Colors.grey),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Construye el estado de error: mensaje descriptivo (R8).
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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

  /// T2.7: Libera recursos del WebView al destruir el widget (R10).
  ///
  /// QUÉ: remueve los canales JavaScript registrados para evitar
  /// callbacks a un widget ya desmontado, y limpia el caché
  /// del WebView para liberar memoria.
  ///
  /// POR QUÉ: sin dispose explícito, los JavaScriptChannel siguen
  /// activos y pueden intentar llamar a setState() en un widget
  /// ya destruido, causando memory leaks y excepciones.
  @override
  void dispose() {
    // Remover canales JS para evitar callbacks a widget desmontado
    try {
      _controller.removeJavaScriptChannel('onNodeTapped');
    } catch (_) {
      // Ignorar si el canal ya no existe
    }
    try {
      _controller.removeJavaScriptChannel('onConsoleLog');
    } catch (_) {
      // Ignorar si el canal ya no existe
    }

    // Limpiar caché del WebView para liberar memoria
    try {
      _controller.clearCache();
    } catch (_) {
      // Ignorar errores de plataforma en tests
    }

    super.dispose();
  }
}

/// Serializa un [LayoutResult] al formato JSON esperado por graph_3d.js.
///
/// La función `window.loadGraphData(json)` en el WebView recibe este mapa
/// para renderizar nodos (esferas) y aristas (líneas) en Three.js.
///
/// Estructura generada:
/// ```json
/// {
///   "nodes": [{"id", "x", "y", "z", "radius", "color", "label", "isSelf"}],
///   "edges": [{"fromId", "toId", "thickness"}]
/// }
/// ```
///
/// El campo `z` usa 0 por defecto (PR4 — PR5 agregará coordenada Z real).
/// El `color` se formatea como hex string `#RRGGBB`.
/// El `label` usa la prioridad: name > suggestedName > "Desconocido".
Map<String, dynamic> layoutResultToJson(LayoutResult layout) {
  return {
    'nodes': layout.nodes.map((n) => {
      'id': n.id,
      'x': n.x,
      'y': n.y,
      'z': n.z, // T5.5: coordenada Z calculada por FR 3D
      'radius': n.radius,
      'color': '#${n.color.toRadixString(16).padLeft(8, '0').substring(2)}',
      'label': n.label,
      'isSelf': n.isSelf,
      // REQ-VR-01: color del perfil para el anillo del self-node en 3D.
      // Se convierte de ARGB int (0xFFE91E63) a hex string sin alpha ("#E91E63").
      'userColor': n.userColor != null
          ? '#${n.userColor!.toRadixString(16).padLeft(8, '0').substring(2)}'
          : null,
    }).toList(),
    'edges': layout.edges.map((e) => {
      'fromId': e.fromId,
      'toId': e.toId,
      'thickness': e.thickness,
    }).toList(),
  };
}
