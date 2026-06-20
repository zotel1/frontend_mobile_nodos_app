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

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    _loadContent();
  }

  /// Crea y configura el WebViewController con el canal JavaScript
  /// para recibir eventos de tap en nodos desde el WebView.
  WebViewController _createController() {
    final controller = WebViewController();

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

    return controller;
  }

  /// Carga el HTML del grafo 3D desde los assets e inyecta los datos.
  Future<void> _loadContent() async {
    await _controller.loadFlutterAsset('assets/three_graph/graph_3d.html');
    _injectData();
  }

  /// Serializa el [LayoutResult] a JSON y lo inyecta en el WebView
  /// llamando a `window.loadGraphData(json)` en el contexto JavaScript.
  void _injectData() {
    final json = jsonEncode(layoutResultToJson(widget.layout));
    _controller.runJavaScript('window.loadGraphData($json)');
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
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
      'z': 0, // PR5 agregará n.z
      'radius': n.radius,
      'color': '#${n.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
      'label': n.label,
      'isSelf': n.isSelf,
    }).toList(),
    'edges': layout.edges.map((e) => {
      'fromId': e.fromId,
      'toId': e.toId,
      'thickness': e.thickness,
    }).toList(),
  };
}
