/**
 * graph_3d.js — Visualizador 3D de grafo de nodos BLE usando Three.js
 *
 * Renderiza nodos como esferas y aristas como líneas en un espacio 3D.
 * Incluye OrbitControls inline para rotación/zoom/pan táctil.
 * Expone window.loadGraphData(json) para recibir datos desde Dart.
 * Emite nodeId vía JavaScriptChannel('onNodeTapped') al tocar un nodo.
 *
 * Three.js UMD build (v0.160) debe cargarse antes como three.min.js
 */
(function () {
  'use strict';

  // ─── OrbitControls inline (minimal, touch-aware) ────────────────────
  const STATE = { NONE: -1, ROTATE: 0, DOLLY: 1, PAN: 2 };
  const EPS = 0.000001;
  const _v = new THREE.Vector3();
  const _q = new THREE.Quaternion();

  function OrbitControls(camera, domElement) {
    this.camera = camera;
    this.domElement = domElement;
    this.target = new THREE.Vector3(0, 0, 0);
    this.enableDamping = true;
    this.dampingFactor = 0.08;
    this.rotateSpeed = 0.5;
    this.zoomSpeed = 1.2;
    this.panSpeed = 0.7;
    this.minDistance = 50;
    this.maxDistance = 2000;

    this._state = STATE.NONE;
    this._spherical = new THREE.Spherical();
    this._sphericalDelta = new THREE.Spherical();
    this._scale = 1;
    this._panOffset = new THREE.Vector3();

    const scope = this;

    function onMouseDown(e) {
      e.preventDefault();
      const btn = e.button === 0 ? STATE.ROTATE : e.button === 1 ? STATE.DOLLY : STATE.PAN;
      scope._state = btn;
      scope._start = { x: e.clientX, y: e.clientY };
    }

    function onMouseMove(e) {
      if (scope._state === STATE.NONE) return;
      const dx = e.clientX - scope._start.x;
      const dy = e.clientY - scope._start.y;
      scope._start = { x: e.clientX, y: e.clientY };

      if (scope._state === STATE.ROTATE) {
        scope._sphericalDelta.theta -= (2 * Math.PI * dx) / scope.domElement.clientHeight * scope.rotateSpeed;
        scope._sphericalDelta.phi -= (2 * Math.PI * dy) / scope.domElement.clientHeight * scope.rotateSpeed;
      } else if (scope._state === STATE.PAN) {
        scope._panOffset.x -= dx * scope.panSpeed;
        scope._panOffset.y += dy * scope.panSpeed;
      } else if (scope._state === STATE.DOLLY) {
        scope._sphericalDelta.radius -= dy * scope.zoomSpeed;
        if (scope._sphericalDelta.radius < 0) scope._sphericalDelta.radius = 0;
      }
    }

    function onMouseUp() { scope._state = STATE.NONE; }

    function onMouseWheel(e) {
      e.preventDefault();
      scope._sphericalDelta.radius += e.deltaY * 0.01 * scope.zoomSpeed;
    }

    // Touch handlers
    function onTouchStart(e) {
      if (e.touches.length === 1) {
        scope._state = STATE.ROTATE;
        scope._start = { x: e.touches[0].clientX, y: e.touches[0].clientY };
      } else if (e.touches.length === 2) {
        scope._state = STATE.PAN;
        const dx = e.touches[1].clientX - e.touches[0].clientX;
        const dy = e.touches[1].clientY - e.touches[0].clientY;
        scope._pinchDist = Math.sqrt(dx * dx + dy * dy);
      }
    }

    function onTouchMove(e) {
      e.preventDefault();
      if (scope._state === STATE.ROTATE && e.touches.length === 1) {
        const dx = e.touches[0].clientX - scope._start.x;
        const dy = e.touches[0].clientY - scope._start.y;
        scope._start = { x: e.touches[0].clientX, y: e.touches[0].clientY };
        scope._sphericalDelta.theta -= (2 * Math.PI * dx) / scope.domElement.clientHeight * scope.rotateSpeed;
        scope._sphericalDelta.phi -= (2 * Math.PI * dy) / scope.domElement.clientHeight * scope.rotateSpeed;
      } else if (scope._state === STATE.PAN && e.touches.length === 2) {
        const dx = e.touches[0].clientX - scope._start.x;
        const dy = e.touches[0].clientY - scope._start.y;
        scope._start = { x: e.touches[0].clientX, y: e.touches[0].clientY };
        scope._panOffset.x -= dx * scope.panSpeed;
        scope._panOffset.y += dy * scope.panSpeed;
        // Pinch zoom
        const ndx = e.touches[1].clientX - e.touches[0].clientX;
        const ndy = e.touches[1].clientY - e.touches[0].clientY;
        const nd = Math.sqrt(ndx * ndx + ndy * ndy);
        if (scope._pinchDist) {
          scope._sphericalDelta.radius -= (nd - scope._pinchDist) * 0.02 * scope.zoomSpeed;
        }
        scope._pinchDist = nd;
      }
    }

    function onTouchEnd(e) {
      scope._state = STATE.NONE;
      scope._pinchDist = null;
    }

    domElement.addEventListener('mousedown', onMouseDown);
    domElement.addEventListener('mousemove', onMouseMove);
    domElement.addEventListener('mouseup', onMouseUp);
    domElement.addEventListener('wheel', onMouseWheel, { passive: false });
    domElement.addEventListener('touchstart', onTouchStart, { passive: false });
    domElement.addEventListener('touchmove', onTouchMove, { passive: false });
    domElement.addEventListener('touchend', onTouchEnd);
    domElement.addEventListener('touchcancel', onTouchEnd);
  }

  OrbitControls.prototype.update = function () {
    const offset = new THREE.Vector3();
    const position = this.camera.position;
    offset.copy(position).sub(this.target);
    this._spherical.setFromVector3(offset);

    this._spherical.theta += this._sphericalDelta.theta;
    this._spherical.phi += this._sphericalDelta.phi;
    this._spherical.radius *= 1 + this._sphericalDelta.radius * 0.01;
    this._spherical.radius = Math.max(this.minDistance, Math.min(this.maxDistance, this._spherical.radius));
    this._spherical.phi = Math.max(0.1, Math.min(Math.PI - 0.1, this._spherical.phi));

    offset.setFromSpherical(this._spherical);
    this.target.add(this._panOffset);
    position.copy(this.target).add(offset);
    this.camera.lookAt(this.target);

    if (this.enableDamping) {
      this._sphericalDelta.theta *= (1 - this.dampingFactor);
      this._sphericalDelta.phi *= (1 - this.dampingFactor);
      this._sphericalDelta.radius *= (1 - this.dampingFactor);
      this._panOffset.multiplyScalar(1 - this.dampingFactor);
    } else {
      this._sphericalDelta.set(0, 0, 0);
      this._panOffset.set(0, 0, 0);
    }
  };

  // ─── Escena Three.js ─────────────────────────────────────────────────
  let scene, camera, renderer, controls, group;

  function initScene() {
    const container = document.getElementById('container');
    const w = window.innerWidth;
    const h = window.innerHeight;

    // Renderer
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setClearColor(0x1a1a2e, 1);
    container.appendChild(renderer.domElement);

    // Scene
    scene = new THREE.Scene();

    // Camera
    camera = new THREE.PerspectiveCamera(45, w / h, 1, 5000);
    camera.position.set(0, -800, 600);
    camera.lookAt(0, 0, 0);

    // Iluminación
    scene.add(new THREE.AmbientLight(0x404060, 1.5));
    const dirLight = new THREE.DirectionalLight(0xffffff, 1);
    dirLight.position.set(500, 500, 500);
    scene.add(dirLight);

    // OrbitControls
    controls = new OrbitControls(camera, renderer.domElement);
    controls.target.set(0, 0, 0);
    controls.update();

    // Grupo principal para nodos y aristas
    group = new THREE.Group();
    scene.add(group);

    // Raycaster para detección de tap
    const raycaster = new THREE.Raycaster();
    raycaster.params.Points.threshold = 10;

    function onTap(e) {
      e.preventDefault();
      const rect = renderer.domElement.getBoundingClientRect();
      const x = ((e.clientX || (e.touches && e.touches[0].clientX)) - rect.left) / rect.width * 2 - 1;
      const y = -((e.clientY || (e.touches && e.touches[0].clientY)) - rect.top) / rect.height * 2 + 1;
      const mouse = new THREE.Vector2(x, y);

      raycaster.setFromCamera(mouse, camera);
      const intersects = raycaster.intersectObjects(group.children, true);

      if (intersects.length > 0) {
        let obj = intersects[0].object;
        while (obj && obj.userData.nodeId == null) {
          obj = obj.parent;
        }
        if (obj && obj.userData.nodeId != null) {
          // Enviar nodeId a Dart vía JavaScriptChannel
          if (window.onNodeTapped && window.onNodeTapped.postMessage) {
            window.onNodeTapped.postMessage(String(obj.userData.nodeId));
          }
        }
      }
    }

    renderer.domElement.addEventListener('click', onTap);
    renderer.domElement.addEventListener('touchend', function (e) {
      // Solo procesar tap si no hubo arrastre (orbit control)
      if (controls._state === STATE.NONE) onTap(e);
    });

    // Resize
    window.addEventListener('resize', function () {
      camera.aspect = window.innerWidth / window.innerHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(window.innerWidth, window.innerHeight);
    });

    // Loop de render
    function animate() {
      requestAnimationFrame(animate);
      controls.update();
      renderer.render(scene, camera);
    }
    animate();
  }

  // ─── API pública: carga datos del grafo ──────────────────────────────
  /**
   * @param {Object} data — { nodes: [{id,x,y,z,radius,color,label,isSelf}], edges: [{fromId,toId,thickness}] }
   */
  // Overlay para mensaje de estado vacío (R6.3)
  let emptyOverlay = null;

  function showEmptyMessage(visible) {
    if (!emptyOverlay) {
      emptyOverlay = document.createElement('div');
      emptyOverlay.id = 'empty-overlay';
      emptyOverlay.style.cssText =
        'position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);' +
        'color:#9e9e9e;font-size:20px;font-family:sans-serif;' +
        'pointer-events:none;z-index:10;text-align:center;';
      emptyOverlay.textContent = 'Sin nodos detectados';
      document.getElementById('container').appendChild(emptyOverlay);
    }
    emptyOverlay.style.display = visible ? 'block' : 'none';
  }

  window.loadGraphData = function (data) {
    try {
    if (!renderer) initScene();
    if (!data || !data.nodes || data.nodes.length === 0) {
      _log('loadGraphData: sin nodos, mostrando mensaje de estado vacío');
      showEmptyMessage(true);
      // Limpiar escena anterior si existía
      while (group.children.length > 0) {
        group.remove(group.children[0]);
      }
      return;
    }
    showEmptyMessage(false);

    _log('loadGraphData: renderizando ' + data.nodes.length + ' nodos y ' + 
         (data.edges ? data.edges.length : 0) + ' aristas');

    // Limpiar escena anterior
    while (group.children.length > 0) {
      const child = group.children[0];
      if (child.geometry) child.geometry.dispose();
      if (child.material) {
        if (Array.isArray(child.material)) {
          child.material.forEach(function (m) { m.dispose(); });
        } else {
          child.material.dispose();
        }
      }
      group.remove(child);
    }

    // Crear aristas con TubeGeometry para visibilidad garantizada.
    // THREE.Line tiene linewidth fijo de 1px en WebGL sin importar el valor
    // seteado. TubeGeometry produce tubos cilíndricos visibles a cualquier
    // zoom y distancia. PR7: reemplaza THREE.Line → THREE.TubeGeometry.
    if (data.edges) {
      const nodeMap = {};
      data.nodes.forEach(function (n) { nodeMap[n.id] = n; });

      data.edges.forEach(function (e) {
        const from = nodeMap[e.fromId];
        const to = nodeMap[e.toId];
        if (!from || !to) return;

        const start = new THREE.Vector3(from.x, from.y, from.z || 0);
        const end = new THREE.Vector3(to.x, to.y, to.z || 0);

        // Crear curva CatmullRom entre ambos puntos para TubeGeometry
        const curve = new THREE.CatmullRomCurve3([start, end]);
        const tubeRadius = 2.0; // grosor del tubo
        const tubularSegments = 16; // segmentos a lo largo del tubo
        const radialSegments = 8; // segmentos alrededor de la sección
        const geometry = new THREE.TubeGeometry(
            curve, tubularSegments, tubeRadius, radialSegments, false);
        const material = new THREE.MeshPhongMaterial({
          color: 0x4fc3f7,
          transparent: true,
          opacity: 0.35,
          emissive: 0x000000,
        });
        const tube = new THREE.Mesh(geometry, material);
        group.add(tube);
      });
    }

    // Crear nodos como esferas
    data.nodes.forEach(function (n) {
      const geometry = new THREE.SphereGeometry(n.radius || 15, 32, 16);
      const material = new THREE.MeshPhongMaterial({
        color: new THREE.Color(n.color || '#4CAF50'),
        shininess: 30,
        emissive: new THREE.Color(n.isSelf ? '#1a237e' : '#000000'),
        emissiveIntensity: n.isSelf ? 0.6 : 0,
      });
      const mesh = new THREE.Mesh(geometry, material);
      mesh.position.set(n.x, n.y, n.z || 0);
      mesh.userData.nodeId = n.id;
      mesh.userData.label = n.label;

      // Anillo de glow para self node (REQ-VR-01)
      // Usa userColor del perfil en lugar de color hardcodeado.
      // Fallback a #42a5f5 si userColor no está disponible.
      if (n.isSelf) {
        const ringGeo = new THREE.TorusGeometry((n.radius || 15) * 1.25, 3, 16, 32);
        const ringColor = n.userColor || '#42a5f5';
        const ringMat = new THREE.MeshBasicMaterial({
          color: new THREE.Color(ringColor),
          transparent: true,
          opacity: 0.7
        });
        const ring = new THREE.Mesh(ringGeo, ringMat);
        mesh.add(ring);
      }

      group.add(mesh);
    });

    // ── Cámara auto-fit (REQ-CA-01) ──
    // Calcula BoundingBox + BoundingSphere a partir de todos los nodos
    // para ajustar cámara, far plane y controls.target dinámicamente.
    if (data.nodes.length > 0) {
      // 1. BoundingBox: min/max de x, y, z
      let minX = Infinity, minY = Infinity, minZ = Infinity;
      let maxX = -Infinity, maxY = -Infinity, maxZ = -Infinity;
      let selfNode = null;

      data.nodes.forEach(function (n) {
        if (n.x < minX) minX = n.x;
        if (n.y < minY) minY = n.y;
        const nz = n.z || 0;
        if (nz < minZ) minZ = nz;
        if (n.x > maxX) maxX = n.x;
        if (n.y > maxY) maxY = n.y;
        if (nz > maxZ) maxZ = nz;
        if (n.isSelf) selfNode = n;
      });

      // 2. BoundingSphere: centro = promedio min/max, radio = max distancia
      const cx = (minX + maxX) / 2;
      const cy = (minY + maxY) / 2;
      const cz = (minZ + maxZ) / 2;
      const center = new THREE.Vector3(cx, cy, cz);

      let maxDist = 0;
      data.nodes.forEach(function (n) {
        const dx = n.x - cx;
        const dy = n.y - cy;
        const dz = (n.z || 0) - cz;
        const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (d > maxDist) maxDist = d;
      });

      // 3. maxDistance: radio × 4, mínimo 2000
      const maxDistance = Math.max(maxDist * 4, 2000);

      // 4. camera.far: maxDistance × 1.5, tope 8000 (mobile Z-buffer)
      camera.far = Math.min(maxDistance * 1.5, 8000);
      camera.updateProjectionMatrix();

      // 5. Posicionar cámara: distancia = radio × 2.5, mínimo 500
      const camDistance = Math.max(maxDist * 2.5, 500);
      camera.position.set(0, -camDistance, camDistance * 0.75);

      // 6. controls.target = posición del self-node (REQ-CA-01 S1-S3)
      //    Si no hay self-node, usar centroide.
      if (selfNode) {
        controls.target.set(selfNode.x, selfNode.y, selfNode.z || 0);
      } else {
        controls.target.copy(center);
      }
      controls.update();

      _log('Camera auto-fit: radius=' + Math.round(maxDist) +
           ' maxDist=' + Math.round(maxDistance) +
           ' far=' + Math.round(camera.far) +
           ' camDist=' + Math.round(camDistance));
    }
    } catch (err) {
      _log('loadGraphData ERROR: ' + (err && err.message ? err.message : String(err)));
    }
  };

  // Mantener referencia para el bridge de comunicación Dart→JS
  window.THREE = THREE;

  /// Envía un mensaje de log al canal onConsoleLog de Dart.
  /// Si el canal no está disponible (tests), usa console.log como fallback.
  function _log(msg) {
    if (window.onConsoleLog && window.onConsoleLog.postMessage) {
      window.onConsoleLog.postMessage(String(msg));
    } else {
      console.log(msg);
    }
  }
})();
