/**
 * graph_3d.js
 *
 * Visualizador 3D del grafo de Nodos App usando Three.js.
 *
 * Responsabilidades:
 * - renderizar los mismos nodos y conexiones de la vista 2D;
 * - mantener color, tamaño, self-node y selección;
 * - distinguir conexiones directas y transitivas;
 * - representar dirección mediante flechas;
 * - permitir rotación, zoom y pan;
 * - detectar taps reales sin confundirlos con gestos de cámara;
 * - ajustar automáticamente la cámara al grafo.
 *
 * Three.js UMD build debe cargarse previamente mediante three.min.js.
 */
(function () {
  'use strict';

  // ─────────────────────────────────────────────────────────────
  // CONSTANTES VISUALES
  // ─────────────────────────────────────────────────────────────

  const BACKGROUND_COLOR = 0x1a1a2e;

  const DIRECT_EDGE_COLOR = 0x7e8a9a;
  const TRANSITIVE_EDGE_COLOR = 0x667080;

  const SELECTION_COLOR = 0xff2d9a;
  const SELF_FALLBACK_COLOR = '#42A5F5';

  const STATE = {
    NONE: -1,
    ROTATE: 0,
    DOLLY: 1,
    PAN: 2
  };

  // Distancia máxima en píxeles entre pointer-down y pointer-up
  // para considerar el gesto como un tap.
  const TAP_MOVE_THRESHOLD = 10;

  // ─────────────────────────────────────────────────────────────
  // ORBIT CONTROLS
  // ─────────────────────────────────────────────────────────────

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

    this._panOffset = new THREE.Vector3();

    this._start = null;
    this._pinchDist = null;

    const scope = this;

    function onMouseDown(event) {
      event.preventDefault();

      if (event.button === 0) {
        scope._state = STATE.ROTATE;
      } else if (event.button === 1) {
        scope._state = STATE.DOLLY;
      } else {
        scope._state = STATE.PAN;
      }

      scope._start = {
        x: event.clientX,
        y: event.clientY
      };
    }

    function onMouseMove(event) {
      if (
        scope._state === STATE.NONE ||
        !scope._start
      ) {
        return;
      }

      const dx =
        event.clientX - scope._start.x;

      const dy =
        event.clientY - scope._start.y;

      scope._start = {
        x: event.clientX,
        y: event.clientY
      };

      if (scope._state === STATE.ROTATE) {
        const height =
          Math.max(scope.domElement.clientHeight, 1);

        scope._sphericalDelta.theta -=
          (2 * Math.PI * dx / height) *
          scope.rotateSpeed;

        scope._sphericalDelta.phi -=
          (2 * Math.PI * dy / height) *
          scope.rotateSpeed;
      } else if (scope._state === STATE.PAN) {
        scope._panOffset.x -=
          dx * scope.panSpeed;

        scope._panOffset.y +=
          dy * scope.panSpeed;
      } else if (scope._state === STATE.DOLLY) {
        scope._sphericalDelta.radius -=
          dy * scope.zoomSpeed;
      }
    }

    function onMouseUp() {
      scope._state = STATE.NONE;
      scope._start = null;
    }

    function onMouseWheel(event) {
      event.preventDefault();

      scope._sphericalDelta.radius +=
        event.deltaY *
        0.01 *
        scope.zoomSpeed;
    }

    function onTouchStart(event) {
      if (event.touches.length === 1) {
        scope._state = STATE.ROTATE;

        scope._start = {
          x: event.touches[0].clientX,
          y: event.touches[0].clientY
        };

        scope._pinchDist = null;

        return;
      }

      if (event.touches.length === 2) {
        scope._state = STATE.PAN;

        const first = event.touches[0];
        const second = event.touches[1];

        scope._start = {
          x: (first.clientX + second.clientX) / 2,
          y: (first.clientY + second.clientY) / 2
        };

        const dx =
          second.clientX - first.clientX;

        const dy =
          second.clientY - first.clientY;

        scope._pinchDist =
          Math.sqrt(dx * dx + dy * dy);
      }
    }

    function onTouchMove(event) {
      event.preventDefault();

      if (
        scope._state === STATE.ROTATE &&
        event.touches.length === 1 &&
        scope._start
      ) {
        const touch = event.touches[0];

        const dx =
          touch.clientX - scope._start.x;

        const dy =
          touch.clientY - scope._start.y;

        scope._start = {
          x: touch.clientX,
          y: touch.clientY
        };

        const height =
          Math.max(scope.domElement.clientHeight, 1);

        scope._sphericalDelta.theta -=
          (2 * Math.PI * dx / height) *
          scope.rotateSpeed;

        scope._sphericalDelta.phi -=
          (2 * Math.PI * dy / height) *
          scope.rotateSpeed;

        return;
      }

      if (
        scope._state === STATE.PAN &&
        event.touches.length === 2
      ) {
        const first = event.touches[0];
        const second = event.touches[1];

        const centerX =
          (first.clientX + second.clientX) / 2;

        const centerY =
          (first.clientY + second.clientY) / 2;

        if (scope._start) {
          const dx =
            centerX - scope._start.x;

          const dy =
            centerY - scope._start.y;

          scope._panOffset.x -=
            dx * scope.panSpeed;

          scope._panOffset.y +=
            dy * scope.panSpeed;
        }

        scope._start = {
          x: centerX,
          y: centerY
        };

        const pinchDx =
          second.clientX - first.clientX;

        const pinchDy =
          second.clientY - first.clientY;

        const pinchDistance =
          Math.sqrt(
            pinchDx * pinchDx +
            pinchDy * pinchDy
          );

        if (
          scope._pinchDist != null &&
          scope._pinchDist > 0
        ) {
          scope._sphericalDelta.radius -=
            (pinchDistance - scope._pinchDist) *
            0.02 *
            scope.zoomSpeed;
        }

        scope._pinchDist =
          pinchDistance;
      }
    }

    function onTouchEnd() {
      scope._state = STATE.NONE;
      scope._start = null;
      scope._pinchDist = null;
    }

    domElement.addEventListener(
      'mousedown',
      onMouseDown
    );

    domElement.addEventListener(
      'mousemove',
      onMouseMove
    );

    domElement.addEventListener(
      'mouseup',
      onMouseUp
    );

    domElement.addEventListener(
      'mouseleave',
      onMouseUp
    );

    domElement.addEventListener(
      'wheel',
      onMouseWheel,
      { passive: false }
    );

    domElement.addEventListener(
      'touchstart',
      onTouchStart,
      { passive: false }
    );

    domElement.addEventListener(
      'touchmove',
      onTouchMove,
      { passive: false }
    );

    domElement.addEventListener(
      'touchend',
      onTouchEnd
    );

    domElement.addEventListener(
      'touchcancel',
      onTouchEnd
    );
  }

  OrbitControls.prototype.update = function () {
    const offset =
      new THREE.Vector3();

    const position =
      this.camera.position;

    offset
      .copy(position)
      .sub(this.target);

    this._spherical.setFromVector3(
      offset
    );

    this._spherical.theta +=
      this._sphericalDelta.theta;

    this._spherical.phi +=
      this._sphericalDelta.phi;

    this._spherical.radius *=
      1 +
      this._sphericalDelta.radius *
      0.01;

    this._spherical.radius =
      Math.max(
        this.minDistance,
        Math.min(
          this.maxDistance,
          this._spherical.radius
        )
      );

    this._spherical.phi =
      Math.max(
        0.1,
        Math.min(
          Math.PI - 0.1,
          this._spherical.phi
        )
      );

    offset.setFromSpherical(
      this._spherical
    );

    this.target.add(
      this._panOffset
    );

    position
      .copy(this.target)
      .add(offset);

    this.camera.lookAt(
      this.target
    );

    if (this.enableDamping) {
      const damping =
        1 - this.dampingFactor;

      this._sphericalDelta.theta *=
        damping;

      this._sphericalDelta.phi *=
        damping;

      this._sphericalDelta.radius *=
        damping;

      this._panOffset.multiplyScalar(
        damping
      );
    } else {
      this._sphericalDelta.theta = 0;
      this._sphericalDelta.phi = 0;
      this._sphericalDelta.radius = 0;

      this._panOffset.set(
        0,
        0,
        0
      );
    }
  };

  // ─────────────────────────────────────────────────────────────
  // ESCENA
  // ─────────────────────────────────────────────────────────────

  let scene;
  let camera;
  let renderer;
  let controls;
  let group;

  let emptyOverlay = null;

  function initScene() {
    const container =
      document.getElementById('container');

    const width =
      Math.max(window.innerWidth, 1);

    const height =
      Math.max(window.innerHeight, 1);

    renderer =
      new THREE.WebGLRenderer({
        antialias: true,
        alpha: false
      });

    renderer.setSize(
      width,
      height
    );

    renderer.setPixelRatio(
      Math.min(
        window.devicePixelRatio || 1,
        2
      )
    );

    renderer.setClearColor(
      BACKGROUND_COLOR,
      1
    );

    container.appendChild(
      renderer.domElement
    );

    scene =
      new THREE.Scene();

    camera =
      new THREE.PerspectiveCamera(
        45,
        width / height,
        1,
        8000
      );

    camera.position.set(
      0,
      -800,
      600
    );

    camera.lookAt(
      0,
      0,
      0
    );

    // Iluminación suave.
    const ambientLight =
      new THREE.AmbientLight(
        0xffffff,
        1.15
      );

    scene.add(
      ambientLight
    );

    const directionalLight =
      new THREE.DirectionalLight(
        0xffffff,
        0.85
      );

    directionalLight.position.set(
      500,
      -300,
      700
    );

    scene.add(
      directionalLight
    );

    controls =
      new OrbitControls(
        camera,
        renderer.domElement
      );

    controls.target.set(
      0,
      0,
      0
    );

    controls.update();

    group =
      new THREE.Group();

    scene.add(
      group
    );

    configurePicking();

    window.addEventListener(
      'resize',
      onResize
    );

    animate();
  }

  function onResize() {
    if (
      !camera ||
      !renderer
    ) {
      return;
    }

    const width =
      Math.max(window.innerWidth, 1);

    const height =
      Math.max(window.innerHeight, 1);

    camera.aspect =
      width / height;

    camera.updateProjectionMatrix();

    renderer.setSize(
      width,
      height
    );
  }

  function animate() {
    requestAnimationFrame(
      animate
    );

    if (controls) {
      controls.update();
    }

    if (
      renderer &&
      scene &&
      camera
    ) {
      renderer.render(
        scene,
        camera
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PICKING / TAP
  // ─────────────────────────────────────────────────────────────

  function configurePicking() {
    const raycaster =
      new THREE.Raycaster();

    let pointerStart = null;
    let pointerMoved = false;

    function getPoint(
      clientX,
      clientY
    ) {
      const rect =
        renderer.domElement
          .getBoundingClientRect();

      return new THREE.Vector2(
        (
          (clientX - rect.left) /
          rect.width
        ) * 2 - 1,

        -(
          (
            clientY - rect.top
          ) /
          rect.height
        ) * 2 + 1
      );
    }

    function selectAt(
      clientX,
      clientY
    ) {
      const pointer =
        getPoint(
          clientX,
          clientY
        );

      raycaster.setFromCamera(
        pointer,
        camera
      );

      // Solo los objetos marcados como pickable
      // pueden convertirse en selección.
      const candidates = [];

      group.traverse(function (object) {
        if (
          object.userData &&
          object.userData.pickable === true
        ) {
          candidates.push(object);
        }
      });

      const intersections =
        raycaster.intersectObjects(
          candidates,
          false
        );

      if (
        intersections.length === 0
      ) {
        return;
      }

      const object =
        intersections[0].object;

      const nodeId =
        object.userData.nodeId;

      if (
        nodeId == null
      ) {
        return;
      }

      if (
        window.onNodeTapped &&
        window.onNodeTapped.postMessage
      ) {
        window.onNodeTapped.postMessage(
          String(nodeId)
        );
      }
    }

    renderer.domElement.addEventListener(
      'pointerdown',
      function (event) {
        if (
          event.pointerType === 'mouse' &&
          event.button !== 0
        ) {
          return;
        }

        pointerStart = {
          x: event.clientX,
          y: event.clientY
        };

        pointerMoved = false;
      }
    );

    renderer.domElement.addEventListener(
      'pointermove',
      function (event) {
        if (!pointerStart) {
          return;
        }

        const dx =
          event.clientX -
          pointerStart.x;

        const dy =
          event.clientY -
          pointerStart.y;

        if (
          Math.sqrt(
            dx * dx +
            dy * dy
          ) >
          TAP_MOVE_THRESHOLD
        ) {
          pointerMoved = true;
        }
      }
    );

    renderer.domElement.addEventListener(
      'pointerup',
      function (event) {
        if (!pointerStart) {
          return;
        }

        if (!pointerMoved) {
          selectAt(
            event.clientX,
            event.clientY
          );
        }

        pointerStart = null;
        pointerMoved = false;
      }
    );

    renderer.domElement.addEventListener(
      'pointercancel',
      function () {
        pointerStart = null;
        pointerMoved = false;
      }
    );
  }

  // ─────────────────────────────────────────────────────────────
  // EMPTY STATE
  // ─────────────────────────────────────────────────────────────

  function showEmptyMessage(
    visible
  ) {
    if (!emptyOverlay) {
      emptyOverlay =
        document.createElement('div');

      emptyOverlay.id =
        'empty-overlay';

      emptyOverlay.style.cssText =
        'position:absolute;' +
        'top:50%;' +
        'left:50%;' +
        'transform:translate(-50%,-50%);' +
        'color:#9e9e9e;' +
        'font-size:18px;' +
        'font-family:sans-serif;' +
        'pointer-events:none;' +
        'z-index:10;' +
        'text-align:center;';

      emptyOverlay.textContent =
        'Sin nodos detectados';

      document
        .getElementById('container')
        .appendChild(emptyOverlay);
    }

    emptyOverlay.style.display =
      visible
        ? 'block'
        : 'none';
  }

  // ─────────────────────────────────────────────────────────────
  // CLEANUP
  // ─────────────────────────────────────────────────────────────

  function disposeMaterial(
    material
  ) {
    if (!material) {
      return;
    }

    if (
      Array.isArray(material)
    ) {
      material.forEach(
        disposeMaterial
      );

      return;
    }

    material.dispose();
  }

  function disposeObject(
    object
  ) {
    // Primero liberar descendientes.
    while (
      object.children &&
      object.children.length > 0
    ) {
      const child =
        object.children[0];

      object.remove(child);

      disposeObject(child);
    }

    if (object.geometry) {
      object.geometry.dispose();
    }

    if (object.material) {
      disposeMaterial(
        object.material
      );
    }
  }

  function clearGraph() {
    if (!group) {
      return;
    }

    while (
      group.children.length > 0
    ) {
      const child =
        group.children[0];

      group.remove(child);

      disposeObject(child);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // EDGES
  // ─────────────────────────────────────────────────────────────

  function renderEdges(
    data,
    nodeMap
  ) {
    if (!data.edges) {
      return;
    }

    data.edges.forEach(
      function (edge) {
        const from =
          nodeMap[edge.fromId];

        const to =
          nodeMap[edge.toId];

        if (
          !from ||
          !to ||
          from.id === to.id
        ) {
          return;
        }

        const startCenter =
          new THREE.Vector3(
            from.x,
            from.y,
            from.z || 0
          );

        const endCenter =
          new THREE.Vector3(
            to.x,
            to.y,
            to.z || 0
          );

        const direction =
          new THREE.Vector3()
            .subVectors(
              endCenter,
              startCenter
            );

        const distance =
          direction.length();

        if (distance <= 0.001) {
          return;
        }

        direction.normalize();

        const fromRadius =
          Math.max(
            Number(from.radius) || 15,
            1
          );

        const toRadius =
          Math.max(
            Number(to.radius) || 15,
            1
          );

        const start =
          startCenter
            .clone()
            .add(
              direction
                .clone()
                .multiplyScalar(
                  fromRadius + 2
                )
            );

        // Dejamos espacio para la punta de flecha.
        const arrowLength =
          Math.max(
            7,
            Math.min(
              toRadius * 0.45,
              14
            )
          );

        const end =
          endCenter
            .clone()
            .add(
              direction
                .clone()
                .multiplyScalar(
                  -(toRadius + arrowLength)
                )
            );

        const isTransitive =
          edge.edgeType ===
          'transitive';

        renderEdgeLine(
          start,
          end,
          isTransitive
        );

        renderArrowHead(
          endCenter,
          direction,
          toRadius,
          arrowLength,
          isTransitive
        );
      }
    );
  }

  /// Línea estructural de una arista.
  ///
  /// THREE.Line es intencional:
  /// buscamos una conexión fina que no compita visualmente con los nodos.
  function renderEdgeLine(
    start,
    end,
    isTransitive
  ) {
    const geometry =
      new THREE.BufferGeometry()
        .setFromPoints([
          start,
          end
        ]);

    const color =
      isTransitive
        ? TRANSITIVE_EDGE_COLOR
        : DIRECT_EDGE_COLOR;

    let material;

    if (isTransitive) {
      material =
        new THREE.LineDashedMaterial({
          color: color,
          transparent: true,
          opacity: 0.38,
          dashSize: 8,
          gapSize: 7
        });
    } else {
      material =
        new THREE.LineBasicMaterial({
          color: color,
          transparent: true,
          opacity: 0.62
        });
    }

    const line =
      new THREE.Line(
        geometry,
        material
      );

    if (isTransitive) {
      line.computeLineDistances();
    }

    group.add(
      line
    );
  }

  /// Crea la flecha `from → to`.
  ///
  /// ConeGeometry utiliza Y como eje longitudinal, por lo que orientamos
  /// el cono desde (0,1,0) hacia la dirección de la conexión.
  function renderArrowHead(
    targetCenter,
    direction,
    targetRadius,
    arrowLength,
    isTransitive
  ) {
    const arrowRadius =
      Math.max(
        2.5,
        Math.min(
          arrowLength * 0.38,
          5
        )
      );

    const geometry =
      new THREE.ConeGeometry(
        arrowRadius,
        arrowLength,
        12
      );

    const color =
      isTransitive
        ? TRANSITIVE_EDGE_COLOR
        : DIRECT_EDGE_COLOR;

    const material =
      new THREE.MeshBasicMaterial({
        color: color,
        transparent: true,
        opacity:
          isTransitive
            ? 0.42
            : 0.68
      });

    const cone =
      new THREE.Mesh(
        geometry,
        material
      );

    const centerDistance =
      targetRadius +
      arrowLength / 2 +
      1;

    cone.position.copy(
      targetCenter
        .clone()
        .add(
          direction
            .clone()
            .multiplyScalar(
              -centerDistance
            )
        )
    );

    const defaultAxis =
      new THREE.Vector3(
        0,
        1,
        0
      );

    cone.quaternion.setFromUnitVectors(
      defaultAxis,
      direction
    );

    group.add(
      cone
    );
  }

  // ─────────────────────────────────────────────────────────────
  // NODES
  // ─────────────────────────────────────────────────────────────

  function renderNodes(
    data
  ) {
    data.nodes.forEach(
      function (node) {
        const radius =
          Math.max(
            Number(node.radius) || 15,
            1
          );

        const geometry =
          new THREE.SphereGeometry(
            radius,
            32,
            20
          );

        const material =
          new THREE.MeshPhongMaterial({
            color:
              new THREE.Color(
                node.color ||
                '#4CAF50'
              ),

            shininess: 18,

            specular:
              new THREE.Color(
                '#303744'
              )
          });

        const mesh =
          new THREE.Mesh(
            geometry,
            material
          );

        mesh.position.set(
          node.x,
          node.y,
          node.z || 0
        );

        // Solo la esfera principal participa del picking.
        mesh.userData.pickable = true;
        mesh.userData.nodeId = node.id;
        mesh.userData.label = node.label;

        group.add(
          mesh
        );

        if (node.isSelf) {
          renderSelfIndicator(
            node,
            radius
          );
        }

        if (
          data.selectedNodeId != null &&
          node.id === data.selectedNodeId
        ) {
          renderSelectionIndicator(
            node,
            radius
          );
        }
      }
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SELF NODE
  // ─────────────────────────────────────────────────────────────

  function renderSelfIndicator(
    node,
    radius
  ) {
    const center =
      new THREE.Vector3(
        node.x,
        node.y,
        node.z || 0
      );

    const selfColor =
      new THREE.Color(
        node.userColor ||
        SELF_FALLBACK_COLOR
      );

    // Halo esférico translúcido.
    const haloGeometry =
      new THREE.SphereGeometry(
        radius + 7,
        28,
        18
      );

    const haloMaterial =
      new THREE.MeshBasicMaterial({
        color: selfColor,
        transparent: true,
        opacity: 0.10,
        depthWrite: false,
        side: THREE.DoubleSide
      });

    const halo =
      new THREE.Mesh(
        haloGeometry,
        haloMaterial
      );

    halo.position.copy(
      center
    );

    group.add(
      halo
    );

    // Anillo de identidad.
    const ringGeometry =
      new THREE.TorusGeometry(
        radius + 5,
        1.8,
        10,
        48
      );

    const ringMaterial =
      new THREE.MeshBasicMaterial({
        color: selfColor,
        transparent: true,
        opacity: 0.90
      });

    const ring =
      new THREE.Mesh(
        ringGeometry,
        ringMaterial
      );

    ring.position.copy(
      center
    );

    // Orientación diagonal para que el aro siga siendo visible
    // desde la perspectiva inicial.
    ring.rotation.x =
      Math.PI / 2.7;

    ring.rotation.y =
      Math.PI / 7;

    group.add(
      ring
    );

    // Pequeño marcador superior equivalente al 2D.
    const markerGeometry =
      new THREE.SphereGeometry(
        Math.max(
          radius * 0.12,
          2.5
        ),
        16,
        10
      );

    const markerMaterial =
      new THREE.MeshBasicMaterial({
        color: selfColor
      });

    const marker =
      new THREE.Mesh(
        markerGeometry,
        markerMaterial
      );

    marker.position.set(
      node.x,
      node.y,
      (node.z || 0) +
        radius +
        6
    );

    group.add(
      marker
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SELECTION
  // ─────────────────────────────────────────────────────────────

  function renderSelectionIndicator(
    node,
    radius
  ) {
    const center =
      new THREE.Vector3(
        node.x,
        node.y,
        node.z || 0
      );

    // Halo magenta exterior.
    const haloGeometry =
      new THREE.SphereGeometry(
        radius + 12,
        32,
        20
      );

    const haloMaterial =
      new THREE.MeshBasicMaterial({
        color:
          SELECTION_COLOR,

        transparent: true,

        opacity: 0.12,

        depthWrite: false,

        side:
          THREE.DoubleSide
      });

    const halo =
      new THREE.Mesh(
        haloGeometry,
        haloMaterial
      );

    halo.position.copy(
      center
    );

    group.add(
      halo
    );

    // Aro principal.
    const ringGeometry =
      new THREE.TorusGeometry(
        radius + 8,
        2.4,
        12,
        64
      );

    const ringMaterial =
      new THREE.MeshBasicMaterial({
        color:
          SELECTION_COLOR,

        transparent: true,

        opacity: 0.95
      });

    const ring =
      new THREE.Mesh(
        ringGeometry,
        ringMaterial
      );

    ring.position.copy(
      center
    );

    ring.rotation.x =
      Math.PI / 2.7;

    ring.rotation.y =
      Math.PI / 7;

    group.add(
      ring
    );
  }

  // ─────────────────────────────────────────────────────────────
  // CAMERA
  // ─────────────────────────────────────────────────────────────

  function fitCamera(
    nodes
  ) {
    if (
      !nodes ||
      nodes.length === 0
    ) {
      return;
    }

    let minX = Infinity;
    let minY = Infinity;
    let minZ = Infinity;

    let maxX = -Infinity;
    let maxY = -Infinity;
    let maxZ = -Infinity;

    let selfNode = null;

    nodes.forEach(
      function (node) {
        const x =
          Number(node.x) || 0;

        const y =
          Number(node.y) || 0;

        const z =
          Number(node.z) || 0;

        const radius =
          Math.max(
            Number(node.radius) || 15,
            1
          );

        minX =
          Math.min(
            minX,
            x - radius
          );

        minY =
          Math.min(
            minY,
            y - radius
          );

        minZ =
          Math.min(
            minZ,
            z - radius
          );

        maxX =
          Math.max(
            maxX,
            x + radius
          );

        maxY =
          Math.max(
            maxY,
            y + radius
          );

        maxZ =
          Math.max(
            maxZ,
            z + radius
          );

        if (node.isSelf) {
          selfNode = node;
        }
      }
    );

    const center =
      new THREE.Vector3(
        (minX + maxX) / 2,
        (minY + maxY) / 2,
        (minZ + maxZ) / 2
      );

    let radius = 0;

    nodes.forEach(
      function (node) {
        const position =
          new THREE.Vector3(
            Number(node.x) || 0,
            Number(node.y) || 0,
            Number(node.z) || 0
          );

        const nodeRadius =
          Math.max(
            Number(node.radius) || 15,
            1
          );

        radius =
          Math.max(
            radius,
            position.distanceTo(
              center
            ) +
            nodeRadius
          );
      }
    );

    // Un solo nodo también necesita un encuadre razonable.
    radius =
      Math.max(
        radius,
        80
      );

    const verticalFov =
      THREE.MathUtils.degToRad(
        camera.fov
      );

    const fitHeightDistance =
      radius /
      Math.tan(
        verticalFov / 2
      );

    const horizontalFov =
      2 *
      Math.atan(
        Math.tan(
          verticalFov / 2
        ) *
        camera.aspect
      );

    const fitWidthDistance =
      radius /
      Math.tan(
        horizontalFov / 2
      );

    // Margen para labels/halos y para que el grafo no toque
    // los extremos de la pantalla.
    const cameraDistance =
      Math.max(
        fitHeightDistance,
        fitWidthDistance
      ) * 1.25;

    const target =
      selfNode
        ? new THREE.Vector3(
            Number(selfNode.x) || 0,
            Number(selfNode.y) || 0,
            Number(selfNode.z) || 0
          )
        : center.clone();

    controls.target.copy(
      target
    );

    // Dirección isométrica inicial.
    const cameraDirection =
      new THREE.Vector3(
        0.15,
        -1,
        0.72
      ).normalize();

    camera.position.copy(
      target
        .clone()
        .add(
          cameraDirection.multiplyScalar(
            cameraDistance
          )
        )
    );

    controls.minDistance =
      Math.max(
        radius * 0.25,
        30
      );

    controls.maxDistance =
      Math.max(
        radius * 8,
        cameraDistance * 4,
        1000
      );

    camera.near =
      Math.max(
        cameraDistance / 1000,
        0.5
      );

    camera.far =
      Math.max(
        controls.maxDistance * 1.5,
        cameraDistance * 8,
        5000
      );

    camera.updateProjectionMatrix();

    camera.lookAt(
      target
    );

    controls.update();

    _log(
      'Camera auto-fit: ' +
      'radius=' +
      Math.round(radius) +
      ' camDist=' +
      Math.round(cameraDistance) +
      ' maxDistance=' +
      Math.round(
        controls.maxDistance
      )
    );
  }

  // ─────────────────────────────────────────────────────────────
  // API PÚBLICA
  // ─────────────────────────────────────────────────────────────

  /**
   * Contrato recibido desde Flutter:
   *
   * {
   *   selectedNodeId: number | null,
   *
   *   nodes: [{
   *     id,
   *     x,
   *     y,
   *     z,
   *     radius,
   *     color,
   *     label,
   *     isSelf,
   *     userColor,
   *     estimatedDistance
   *   }],
   *
   *   edges: [{
   *     fromId,
   *     toId,
   *     thickness,
   *     edgeType
   *   }]
   * }
   */
  window.loadGraphData =
    function (data) {
      try {
        if (!renderer) {
          initScene();
        }

        if (
          !data ||
          !Array.isArray(data.nodes) ||
          data.nodes.length === 0
        ) {
          _log(
            'loadGraphData: sin nodos'
          );

          showEmptyMessage(
            true
          );

          clearGraph();

          return;
        }

        showEmptyMessage(
          false
        );

        _log(
          'loadGraphData: renderizando ' +
          data.nodes.length +
          ' nodos y ' +
          (
            Array.isArray(data.edges)
              ? data.edges.length
              : 0
          ) +
          ' aristas; selected=' +
          (
            data.selectedNodeId != null
              ? data.selectedNodeId
              : 'none'
          )
        );

        clearGraph();

        const nodeMap = {};

        data.nodes.forEach(
          function (node) {
            if (
              node.id != null
            ) {
              nodeMap[node.id] =
                node;
            }
          }
        );

        // Back-to-front conceptual:
        // conexiones primero, nodos después.
        renderEdges(
          data,
          nodeMap
        );

        renderNodes(
          data
        );

        fitCamera(
          data.nodes
        );
      } catch (error) {
        _log(
          'loadGraphData ERROR: ' +
          (
            error &&
            error.message
              ? error.message
              : String(error)
          )
        );
      }
    };

  // Mantener referencia global para el bridge/debug.
  window.THREE = THREE;

  // ─────────────────────────────────────────────────────────────
  // LOG
  // ─────────────────────────────────────────────────────────────

  function _log(
    message
  ) {
    if (
      window.onConsoleLog &&
      window.onConsoleLog.postMessage
    ) {
      window.onConsoleLog.postMessage(
        String(message)
      );
    } else {
      console.log(
        message
      );
    }
  }
})();