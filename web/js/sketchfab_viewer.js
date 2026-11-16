/**
 * Sketchfab-grade WebGL 3D Viewer for RIG-CAR
 * Multi-format 3D engine powered by Three.js
 * Supports .glb, .gltf, .obj, .stl, .fbx, and .zip (Sketchfab download packs)
 * with full PBR textures, environment lighting, and 60 FPS hardware acceleration.
 */
(function() {
  'use strict';

  let renderer, scene, camera, controls;
  let currentModel = null;
  let modelPivotGroup = null;
  let gridGroup = null;
  let forwardArrowGroup = null;
  let showForwardArrow = true;
  let currentGridStyle = 'cad';
  const gridStyleMap = {};
  let groundShadow = null;
  let dirLightKey, dirLightFill, dirLightRim, hemiLight;
  let originalMaterials = new Map();
  let wireframeOverlayGroup = null;
  let markersGroup = null;
  let isInitialized = false;
  let containerEl = null;
  let animId = null;
  let modelBBox = null;
  let modelCenter = null;
  let modelRadius = 4.0;
  let currentRenderMode = 'solid'; // 'solid' | 'wireframe' | 'hybrid'
  let currentLighting = 'studio'; // 'studio' | 'daylight' | 'night' | 'flat'
  let pendingModelBuffer = null;
  let createdBlobUrls = [];

  function cleanBlobUrls() {
    if (createdBlobUrls.length > 0) {
      createdBlobUrls.forEach(url => {
        try { URL.revokeObjectURL(url); } catch (_) {}
      });
      createdBlobUrls = [];
    }
  }

  function ensureArrayBuffer(input) {
    if (!input) return null;
    if (input instanceof ArrayBuffer) {
      return input;
    }
    // Dart ByteBuffer wrapper (e.g. { o: ArrayBuffer } in dart2js)
    if (input.o && input.o instanceof ArrayBuffer) {
      return input.o;
    }
    if (input._buffer && input._buffer instanceof ArrayBuffer) {
      return input._buffer;
    }
    if (input._parent && input._parent.buffer && input._parent.buffer instanceof ArrayBuffer) {
      return input._parent.buffer;
    }
    // Uint8Array or other TypedArray / ArrayBufferView
    if (ArrayBuffer.isView(input) || (input.buffer && input.buffer instanceof ArrayBuffer)) {
      const buf = input.buffer;
      const offset = typeof input.byteOffset === 'number' ? input.byteOffset : 0;
      const length = typeof input.byteLength === 'number' ? input.byteLength : buf.byteLength;
      if (offset === 0 && length === buf.byteLength) {
        return buf;
      }
      return buf.slice(offset, offset + length);
    }
    // Generic iterable / array of bytes
    if (Array.isArray(input) || (typeof input.length === 'number' && typeof input[0] === 'number')) {
      const u8 = new Uint8Array(input);
      return u8.buffer;
    }
    return input;
  }

  function init(container) {
    if (isInitialized && containerEl === container) return;

    // Re-attach the existing scene when Flutter swaps platform views (for
    // example Workbench -> Test Drive) instead of rebuilding and reloading.
    if (isInitialized && renderer && scene && camera) {
      containerEl = container;
      const rw = container.clientWidth || 800;
      const rh = container.clientHeight || 500;
      while (container.firstChild) {
        container.removeChild(container.firstChild);
      }
      container.appendChild(renderer.domElement);
      renderer.setSize(rw, rh);
      camera.aspect = rw / rh;
      camera.updateProjectionMatrix();
      return;
    }

    containerEl = container;

    const width = container.clientWidth || 800;
    const height = container.clientHeight || 500;

    // 1. Scene
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0c1318);

    // 2. Camera
    camera = new THREE.PerspectiveCamera(45, width / height, 0.05, 2000);
    camera.position.set(4.5, 2.2, 5.0);

    // 3. Renderer
    renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: true,
      powerPreference: 'high-performance'
    });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2.0));
    renderer.outputEncoding = THREE.sRGBEncoding;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.05;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    while (container.firstChild) {
      container.removeChild(container.firstChild);
    }
    container.appendChild(renderer.domElement);
    renderer.domElement.style.width = '100%';
    renderer.domElement.style.height = '100%';
    renderer.domElement.style.display = 'block';
    renderer.domElement.style.touchAction = 'none';
    renderer.domElement.style.userSelect = 'none';
    renderer.domElement.style.cursor = 'grab';

    // 4. OrbitControls
    controls = new THREE.OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.05;
    controls.screenSpacePanning = true;
    controls.maxPolarAngle = Math.PI * 0.95;
    controls.minDistance = 0.2;
    controls.maxDistance = 500.0;
    controls.target.set(0, 0.6, 0);

    controls.addEventListener('change', function() {
      notifyCameraChange(false);
    });

    let pointerDownPos = { x: 0, y: 0 };
    controls.domElement.addEventListener('pointerdown', (e) => {
      pointerDownPos = { x: e.clientX, y: e.clientY };
      renderer.domElement.style.cursor = 'grabbing';
    });
    controls.domElement.addEventListener('pointerup', (e) => {
      renderer.domElement.style.cursor = 'grab';
      const dist = Math.hypot(e.clientX - pointerDownPos.x, e.clientY - pointerDownPos.y);
      if (dist < 6 && currentModel && camera) {
        const rect = renderer.domElement.getBoundingClientRect();
        const mouse = new THREE.Vector2(
          ((e.clientX - rect.left) / rect.width) * 2 - 1,
          -((e.clientY - rect.top) / rect.height) * 2 + 1
        );
        const raycaster = new THREE.Raycaster();
        raycaster.setFromCamera(mouse, camera);
        const intersects = raycaster.intersectObjects(currentModel.children, true);
        if (intersects.length > 0) {
          const hitMesh = intersects[0].object;
          const meshName = hitMesh.name || '';
          window.dispatchEvent(new CustomEvent('sketchfab-node-select', {
            detail: { meshName: meshName, x: intersects[0].point.x, y: intersects[0].point.y, z: intersects[0].point.z }
          }));
        }
      }
    });

    // 5. Lighting Rig (Sketchfab Studio 3-Point PBR Lighting)
    hemiLight = new THREE.HemisphereLight(0xffffff, 0x18241d, 1.0);
    hemiLight.position.set(0, 20, 0);
    scene.add(hemiLight);

    dirLightKey = new THREE.DirectionalLight(0xffffff, 1.6);
    dirLightKey.position.set(6, 9, 6);
    dirLightKey.castShadow = true;
    dirLightKey.shadow.mapSize.width = 1024;
    dirLightKey.shadow.mapSize.height = 1024;
    dirLightKey.shadow.camera.near = 1.0;
    dirLightKey.shadow.camera.far = 45;
    dirLightKey.shadow.camera.left = -4.2;
    dirLightKey.shadow.camera.right = 4.2;
    dirLightKey.shadow.camera.top = 4.2;
    dirLightKey.shadow.camera.bottom = -4.2;
    dirLightKey.shadow.bias = -0.0003;
    scene.add(dirLightKey);

    dirLightFill = new THREE.DirectionalLight(0xaad8e6, 0.7);
    dirLightFill.position.set(-6, 4, -4);
    scene.add(dirLightFill);

    dirLightRim = new THREE.DirectionalLight(0xffeedd, 0.9);
    dirLightRim.position.set(0, 5, -8);
    scene.add(dirLightRim);

    // 6. Floor Grid & Contact Shadow
    createGround(scene);

    // 7. Markers group
    markersGroup = new THREE.Group();
    scene.add(markersGroup);

    // 8. Resize Observer
    const ro = new ResizeObserver(() => {
      onWindowResize();
    });
    ro.observe(container);

    // 9. Animation Loop
    isInitialized = true;
    animate();

    // 10. Load any pending buffer or fallback demo car
    if (pendingModelBuffer) {
      const p = pendingModelBuffer;
      pendingModelBuffer = null;
      loadModel(p.buffer, p.fileName, p.callback);
    } else {
      loadDemoCar();
    }
  }

  function createGround(sc) {
    if (gridGroup) {
      sc.remove(gridGroup);
      disposeObject(gridGroup);
      for (const k in gridStyleMap) delete gridStyleMap[k];
    }
    gridGroup = new THREE.Group();
    sc.add(gridGroup);

    if (forwardArrowGroup) {
      sc.remove(forwardArrowGroup);
      disposeObject(forwardArrowGroup);
      forwardArrowGroup = null;
    }
    forwardArrowGroup = buildForwardArrowHelper();
    forwardArrowGroup.visible = showForwardArrow;
    sc.add(forwardArrowGroup);

    if (groundShadow) sc.remove(groundShadow);

    // Soft Radial Contact Shadow Plane
    const shadowCanvas = document.createElement('canvas');
    shadowCanvas.width = 256;
    shadowCanvas.height = 256;
    const ctx = shadowCanvas.getContext('2d');
    const grad = ctx.createRadialGradient(128, 128, 20, 128, 128, 120);
    grad.addColorStop(0, 'rgba(0, 0, 0, 0.70)');
    grad.addColorStop(0.5, 'rgba(0, 0, 0, 0.25)');
    grad.addColorStop(1, 'rgba(0, 0, 0, 0)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 256, 256);

    const shadowTex = new THREE.CanvasTexture(shadowCanvas);
    const shadowGeo = new THREE.PlaneGeometry(4.0, 4.0);
    const shadowMat = new THREE.MeshBasicMaterial({
      map: shadowTex,
      transparent: true,
      depthWrite: false,
      opacity: 0.45
    });
    groundShadow = new THREE.Mesh(shadowGeo, shadowMat);
    groundShadow.rotation.x = -Math.PI / 2;
    groundShadow.position.y = 0.0001;
    sc.add(groundShadow);

    // Instantiate and show active grid style
    setGridStyle(currentGridStyle);
  }

  function onWindowResize() {
    if (!containerEl || !renderer || !camera) return;
    const width = containerEl.clientWidth || 800;
    const height = containerEl.clientHeight || 500;
    if (width === 0 || height === 0) return;
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height);
  }

  function animate() {
    animId = requestAnimationFrame(animate);
    if (!testDriveActive && controls) controls.update();
    if (renderer && scene && camera) {
      renderer.render(scene, camera);
    }
  }

  let lastCameraDispatchTime = 0;
  function notifyCameraChange(force) {
    if (!camera || !controls) return;
    const now = performance.now();
    if (!force && (now - lastCameraDispatchTime < 16)) return;
    lastCameraDispatchTime = now;

    const target = controls.target || new THREE.Vector3(0, 0.6, 0);
    const offset = new THREE.Vector3().subVectors(camera.position, target);
    const radius = Math.max(1e-4, offset.length());
    const elevation = Math.asin(Math.max(-1, Math.min(1, offset.y / radius)));
    const azimuth = Math.atan2(offset.x, offset.z);

    const event = new CustomEvent('sketchfab-camera-orbit', {
      detail: {
        azimuth: azimuth,
        elevation: elevation,
        distance: radius
      }
    });
    window.dispatchEvent(event);
  }

  /**
   * Universal Model Loader supporting GLB, GLTF, OBJ, STL, FBX, and ZIP.
   */
  function loadModel(rawBuffer, fileName, callback) {
    if (!scene) {
      pendingModelBuffer = { buffer: rawBuffer, fileName: fileName, callback: callback };
      return;
    }

    const arrayBuffer = ensureArrayBuffer(rawBuffer);
    if (!arrayBuffer || !(arrayBuffer instanceof ArrayBuffer)) {
      console.error('SketchfabViewer: Invalid buffer passed to loadModel', rawBuffer);
      if (callback) callback({ success: false, error: 'Invalid buffer' });
      return;
    }

    cleanBlobUrls();

    const name = (fileName || '').toLowerCase();
    const u8 = new Uint8Array(arrayBuffer, 0, Math.min(64, arrayBuffer.byteLength));

    // Check magic bytes
    const isZip = u8[0] === 0x50 && u8[1] === 0x4B && u8[2] === 0x03 && u8[3] === 0x04;
    const isGlb = u8[0] === 0x67 && u8[1] === 0x6C && u8[2] === 0x54 && u8[3] === 0x46; // 'glTF'
    const isFbx = arrayBuffer.byteLength > 20 &&
      (name.endsWith('.fbx') || String.fromCharCode.apply(null, u8.subarray(0, 18)).startsWith('Kaydara FBX'));

    console.log('SketchfabViewer: loadModel for file:', fileName, 'byteLength:', arrayBuffer.byteLength);

    if (isZip || name.endsWith('.zip')) {
      loadZip(arrayBuffer, callback);
    } else if (isGlb || name.endsWith('.glb')) {
      loadGlb(arrayBuffer, callback);
    } else if (name.endsWith('.gltf') || (u8[0] === 0x7B /* '{' */)) {
      loadGltf(arrayBuffer, callback);
    } else if (name.endsWith('.obj')) {
      loadObj(arrayBuffer, callback);
    } else if (name.endsWith('.stl')) {
      loadStl(arrayBuffer, callback);
    } else if (isFbx || name.endsWith('.fbx')) {
      loadFbx(arrayBuffer, callback);
    } else {
      // Auto-detect: GLB/GLTF -> OBJ -> STL -> FBX
      loadGlb(arrayBuffer, function(res) {
        if (res && res.success) {
          if (callback) callback(res);
        } else {
          loadObj(arrayBuffer, function(resObj) {
            if (resObj && resObj.success) {
              if (callback) callback(resObj);
            } else {
              loadStl(arrayBuffer, callback);
            }
          });
        }
      });
    }
  }

  function loadGlb(arrayBuffer, callback) {
    const loader = new THREE.GLTFLoader();
    loader.parse(
      arrayBuffer,
      '',
      function(gltf) {
        applyLoadedModel(gltf.scene || gltf.scenes[0], callback);
      },
      function(error) {
        console.error('SketchfabViewer: Error parsing GLB:', error);
        if (callback) callback({ success: false, error: error });
      }
    );
  }

  function loadGltf(arrayBuffer, callback) {
    const text = new TextDecoder('utf-8').decode(new Uint8Array(arrayBuffer));
    const loader = new THREE.GLTFLoader();
    loader.parse(
      text,
      '',
      function(gltf) {
        applyLoadedModel(gltf.scene || gltf.scenes[0], callback);
      },
      function(error) {
        console.error('SketchfabViewer: Error parsing GLTF JSON:', error);
        if (callback) callback({ success: false, error: error });
      }
    );
  }

  function loadObj(arrayBuffer, callback) {
    if (typeof THREE.OBJLoader === 'undefined') {
      console.error('SketchfabViewer: OBJLoader not available');
      if (callback) callback({ success: false, error: 'OBJLoader missing' });
      return;
    }
    const text = new TextDecoder('utf-8').decode(new Uint8Array(arrayBuffer));
    try {
      const loader = new THREE.OBJLoader();
      const obj = loader.parse(text);

      // Enhance with studio automotive PBR materials
      obj.traverse(function(child) {
        if (child.isMesh) {
          const name = (child.name || '').toLowerCase();
          const isGlass = name.includes('glass') || name.includes('windshield') || name.includes('window');
          const isWheel = name.includes('wheel') || name.includes('tire') || name.includes('rubber');
          const isChrome = name.includes('rim') || name.includes('chrome') || name.includes('mirror');

          child.material = new THREE.MeshStandardMaterial({
            color: isGlass ? 0x223344 : (isWheel ? 0x1f2224 : (isChrome ? 0xd0d4d8 : 0xcccccc)),
            metalness: isGlass ? 0.9 : (isWheel ? 0.15 : (isChrome ? 0.95 : 0.65)),
            roughness: isGlass ? 0.1 : (isWheel ? 0.8 : (isChrome ? 0.1 : 0.28)),
            transparent: isGlass,
            opacity: isGlass ? 0.55 : 1.0,
            depthWrite: true,
            side: THREE.DoubleSide
          });
        }
      });
      applyLoadedModel(obj, callback);
    } catch (e) {
      console.error('SketchfabViewer: Error parsing OBJ:', e);
      if (callback) callback({ success: false, error: e });
    }
  }

  function loadStl(arrayBuffer, callback) {
    if (typeof THREE.STLLoader === 'undefined') {
      console.error('SketchfabViewer: STLLoader not available');
      if (callback) callback({ success: false, error: 'STLLoader missing' });
      return;
    }
    try {
      const loader = new THREE.STLLoader();
      const geometry = loader.parse(arrayBuffer);
      geometry.computeVertexNormals();

      const material = new THREE.MeshStandardMaterial({
        color: 0xc8cdd0,
        metalness: 0.55,
        roughness: 0.32,
        side: THREE.DoubleSide
      });
      const mesh = new THREE.Mesh(geometry, material);
      const group = new THREE.Group();
      group.add(mesh);
      applyLoadedModel(group, callback);
    } catch (e) {
      console.error('SketchfabViewer: Error parsing STL:', e);
      if (callback) callback({ success: false, error: e });
    }
  }

  function loadFbx(arrayBuffer, callback) {
    if (typeof THREE.FBXLoader === 'undefined') {
      console.error('SketchfabViewer: FBXLoader not available');
      if (callback) callback({ success: false, error: 'FBXLoader missing' });
      return;
    }
    try {
      const loader = new THREE.FBXLoader();
      const group = loader.parse(arrayBuffer, '');
      applyLoadedModel(group, callback);
    } catch (e) {
      console.error('SketchfabViewer: Error parsing FBX:', e);
      if (callback) callback({ success: false, error: e });
    }
  }

  function loadZip(arrayBuffer, callback) {
    if (typeof JSZip === 'undefined') {
      console.error('SketchfabViewer: JSZip not available');
      if (callback) callback({ success: false, error: 'JSZip missing' });
      return;
    }

    JSZip.loadAsync(arrayBuffer).then(async function(zip) {
      let glbFile = null;
      let gltfFile = null;
      let fbxFile = null;
      let objFile = null;
      let stlFile = null;

      const fileMap = {};

      zip.forEach(function(relativePath, file) {
        if (file.dir) return;
        const low = relativePath.toLowerCase();
        fileMap[low] = file;
        const base = low.split('/').pop();
        if (base.endsWith('.glb') && !glbFile) glbFile = file;
        if (base.endsWith('.gltf') && !gltfFile) gltfFile = file;
        if (base.endsWith('.fbx') && !fbxFile) fbxFile = file;
        if (base.endsWith('.obj') && !objFile) objFile = file;
        if (base.endsWith('.stl') && !stlFile) stlFile = file;
      });

      if (glbFile) {
        console.log('SketchfabViewer: Extracted GLB from ZIP:', glbFile.name);
        const buf = await glbFile.async('arraybuffer');
        loadGlb(buf, callback);
      } else if (gltfFile) {
        console.log('SketchfabViewer: Extracted GLTF from ZIP with textures:', gltfFile.name);
        const urlMap = {};
        for (const [path, file] of Object.entries(fileMap)) {
          const blob = new Blob([await file.async('arraybuffer')]);
          const url = URL.createObjectURL(blob);
          createdBlobUrls.push(url);
          urlMap[path] = url;
          const baseName = path.split('/').pop();
          urlMap[baseName] = url;
        }

        const manager = new THREE.LoadingManager();
        manager.setURLModifier(function(url) {
          const base = url.split('/').pop().split('\\').pop().toLowerCase();
          if (urlMap[base]) return urlMap[base];
          return url;
        });

        const gltfText = await gltfFile.async('text');
        const loader = new THREE.GLTFLoader(manager);
        loader.parse(gltfText, '', function(gltf) {
          applyLoadedModel(gltf.scene || gltf.scenes[0], callback);
        }, function(err) {
          console.error('SketchfabViewer: Error parsing GLTF from ZIP:', err);
          if (callback) callback({ success: false, error: err });
        });
      } else if (fbxFile) {
        console.log('SketchfabViewer: Extracted FBX from ZIP:', fbxFile.name);
        const buf = await fbxFile.async('arraybuffer');
        loadFbx(buf, callback);
      } else if (objFile) {
        console.log('SketchfabViewer: Extracted OBJ from ZIP:', objFile.name);
        const buf = await objFile.async('arraybuffer');
        loadObj(buf, callback);
      } else if (stlFile) {
        console.log('SketchfabViewer: Extracted STL from ZIP:', stlFile.name);
        const buf = await stlFile.async('arraybuffer');
        loadStl(buf, callback);
      } else {
        console.error('SketchfabViewer: No supported 3D model found inside zip archive');
        if (callback) callback({ success: false, error: 'No 3D model found in zip' });
      }
    }).catch(function(err) {
      console.error('SketchfabViewer: Error reading zip archive:', err);
      if (callback) callback({ success: false, error: err });
    });
  }

  function createDemoCarGroup() {
    const carGroup = new THREE.Group();
    carGroup.name = 'Apex_GT_Coupe';

    // 1. Chassis Body Geometry (Procedural Apex GT Coupe)
    const bodyPoints = [
      new THREE.Vector3(-0.90, 0.18, -1.85), // 0: FL bottom
      new THREE.Vector3(0.90, 0.18, -1.85),  // 1: FR bottom
      new THREE.Vector3(0.90, 0.18, 1.85),   // 2: RR bottom
      new THREE.Vector3(-0.90, 0.18, 1.85),  // 3: RL bottom
      new THREE.Vector3(-0.85, 0.65, -1.65), // 4: FL hood
      new THREE.Vector3(0.85, 0.65, -1.65),  // 5: FR hood
      new THREE.Vector3(-0.80, 0.82, -0.60), // 6: FL windshield
      new THREE.Vector3(0.80, 0.82, -0.60),  // 7: FR windshield
      new THREE.Vector3(-0.65, 1.28, -0.15), // 8: FL roof front
      new THREE.Vector3(0.65, 1.28, -0.15),  // 9: FR roof front
      new THREE.Vector3(-0.65, 1.28, 0.75),  // 10: RL roof rear
      new THREE.Vector3(0.65, 1.28, 0.75),   // 11: RR roof rear
      new THREE.Vector3(-0.80, 0.82, 1.25),  // 12: RL rear window
      new THREE.Vector3(0.80, 0.82, 1.25),   // 13: RR rear window
      new THREE.Vector3(-0.85, 0.72, 1.80),  // 14: RL trunk
      new THREE.Vector3(0.85, 0.72, 1.80)    // 15: RR trunk
    ];

    const bodyIndices = [
      4, 5, 1,   4, 1, 0,   4, 6, 7,   4, 7, 5,
      6, 7, 9,   6, 9, 8,   8, 9, 11,  8, 11, 10,
      10, 11, 13, 10, 13, 12, 12, 13, 15, 12, 15, 14,
      14, 15, 2,  14, 2, 3,  0, 4, 6,   0, 6, 3,
      6, 8, 10,  6, 10, 12, 3, 6, 12,  3, 12, 14, 1, 7, 5,
      1, 2, 7,   2, 13, 7,  7, 11, 9,  7, 13, 11, 2, 15, 13,
      0, 1, 2,   0, 2, 3
    ];

    const positions = [];
    bodyIndices.forEach(idx => {
      const p = bodyPoints[idx];
      positions.push(p.x, p.y, p.z);
    });

    const bodyGeo = new THREE.BufferGeometry();
    bodyGeo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
    bodyGeo.computeVertexNormals();

    const bodyMat = new THREE.MeshStandardMaterial({
      color: 0x142820,
      metalness: 0.75,
      roughness: 0.28,
      side: THREE.DoubleSide
    });
    const chassisMesh = new THREE.Mesh(bodyGeo, bodyMat);
    chassisMesh.name = 'Chassis';
    chassisMesh.castShadow = true;
    chassisMesh.receiveShadow = true;
    carGroup.add(chassisMesh);

    // Windshield & Canopy Glass Mesh
    const glassIndices = [
      6, 7, 9,   6, 9, 8,
      8, 9, 11,  8, 11, 10,
      10, 11, 13, 10, 13, 12
    ];
    const glassPos = [];
    glassIndices.forEach(idx => {
      const p = bodyPoints[idx];
      glassPos.push(p.x, p.y + 0.002, p.z);
    });
    const glassGeo = new THREE.BufferGeometry();
    glassGeo.setAttribute('position', new THREE.Float32BufferAttribute(glassPos, 3));
    glassGeo.computeVertexNormals();
    const glassMat = new THREE.MeshStandardMaterial({
      color: 0x34d399,
      metalness: 0.9,
      roughness: 0.1,
      transparent: true,
      opacity: 0.45,
      side: THREE.DoubleSide
    });
    const glassMesh = new THREE.Mesh(glassGeo, glassMat);
    glassMesh.name = 'Windshield';
    carGroup.add(glassMesh);

    // 4 Wheels
    const wheelConfigs = [
      { name: 'Wheel_FL', x: -0.85, y: 0.34, z: -1.35 },
      { name: 'Wheel_FR', x: 0.85, y: 0.34, z: -1.35 },
      { name: 'Wheel_RL', x: -0.85, y: 0.34, z: 1.35 },
      { name: 'Wheel_RR', x: 0.85, y: 0.34, z: 1.35 }
    ];

    const tireMat = new THREE.MeshStandardMaterial({
      color: 0x181e1b,
      metalness: 0.15,
      roughness: 0.85
    });

    const rimMat = new THREE.MeshStandardMaterial({
      color: 0x10b981,
      metalness: 0.85,
      roughness: 0.2
    });

    const discMat = new THREE.MeshStandardMaterial({
      color: 0x6ee7b7,
      metalness: 0.9,
      roughness: 0.15
    });

    wheelConfigs.forEach(cfg => {
      const wGroup = new THREE.Group();
      wGroup.name = cfg.name;
      wGroup.position.set(cfg.x, cfg.y, cfg.z);

      // Tire cylinder (Radius 0.34m, width 0.26m)
      const tireGeo = new THREE.CylinderGeometry(0.34, 0.34, 0.26, 24);
      tireGeo.rotateZ(Math.PI / 2);
      const tireMesh = new THREE.Mesh(tireGeo, tireMat.clone());
      tireMesh.name = cfg.name + '_Tire';
      tireMesh.castShadow = true;
      tireMesh.receiveShadow = true;
      wGroup.add(tireMesh);

      // Rim barrel (Radius 0.22m, width 0.262m)
      const rimGeo = new THREE.CylinderGeometry(0.22, 0.22, 0.262, 24);
      rimGeo.rotateZ(Math.PI / 2);
      const rimMesh = new THREE.Mesh(rimGeo, rimMat.clone());
      rimMesh.name = cfg.name + '_Rim';
      wGroup.add(rimMesh);

      // Center brake rotor / cap (Radius 0.14m, width 0.264m)
      const discGeo = new THREE.CylinderGeometry(0.14, 0.14, 0.264, 16);
      discGeo.rotateZ(Math.PI / 2);
      const discMesh = new THREE.Mesh(discGeo, discMat.clone());
      discMesh.name = cfg.name + '_Disc';
      wGroup.add(discMesh);

      carGroup.add(wGroup);
    });

    return carGroup;
  }

  function loadDemoCar(callback) {
    if (!scene) return;
    const carGroup = createDemoCarGroup();
    applyLoadedModel(carGroup, callback);
  }

  /**
   * Unified Post-Processing Pipeline for all loaded models.
   */
  function applyLoadedModel(model, callback) {
    if (!scene) return;
    clearWheelDataAndMarkers();
    detectedWheelData = null;
    highlightWheelMeshes(false);
    if (modelPivotGroup) {
      scene.remove(modelPivotGroup);
      disposeObject(modelPivotGroup);
      modelPivotGroup = null;
    }
    if (currentModel) {
      scene.remove(currentModel);
      disposeObject(currentModel);
      currentModel = null;
    }
    originalMaterials.clear();

    currentModel = model;
    modelPivotGroup = new THREE.Group();
    modelPivotGroup.name = 'ModelPivotGroup';
    modelPivotGroup.position.set(0, 0, 0);
    modelPivotGroup.rotation.set(0, 0, 0);
    modelPivotGroup.scale.set(1, 1, 1);

    let meshCount = 0;
    let triCount = 0;

    // Process materials and textures
    model.traverse(function(child) {
      if (child.isMesh) {
        meshCount++;
        if (child.geometry && child.geometry.attributes && child.geometry.attributes.position) {
          const pos = child.geometry.attributes.position;
          if (child.geometry.index) {
            triCount += Math.floor(child.geometry.index.count / 3);
          } else {
            triCount += Math.floor(pos.count / 3);
          }
        }

        child.castShadow = true;
        child.receiveShadow = true;

        if (child.material) {
          const mats = Array.isArray(child.material) ? child.material : [child.material];
          mats.forEach(mat => {
            // Enable anisotropic filtering on all textures
            const textures = [
              mat.map, mat.normalMap, mat.roughnessMap,
              mat.metalnessMap, mat.aoMap, mat.emissiveMap
            ];
            textures.forEach(tex => {
              if (tex) {
                tex.encoding = THREE.sRGBEncoding;
                tex.anisotropy = renderer ? renderer.capabilities.getMaxAnisotropy() : 8;
              }
            });

            // Glass / windshield handling
            const name = (mat.name || '').toLowerCase();
            const isGlass = name.includes('glass') || name.includes('windshield') ||
                            name.includes('window') || name.includes('wnd') ||
                            name.includes('visor');
            if (isGlass || (mat.transparent && mat.opacity < 0.98)) {
              mat.transparent = true;
              mat.depthWrite = true;
              mat.side = THREE.DoubleSide;
              if (mat.opacity >= 1.0) mat.opacity = 0.55;
            } else {
              // Double-sided for thin aero panels (spoilers, wings, diffusers)
              mat.side = THREE.DoubleSide;
            }

            originalMaterials.set(mat.uuid, mat.clone());
          });
        }
      }
    });

    // Compute BBox and center
    model.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(model);
    modelBBox = box;
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());

    const maxDim = Math.max(size.x, Math.max(size.y, size.z));
    // Normalize unit scale if author exported in millimeters (>20) or decimeters
    if (maxDim > 20.0 || (maxDim < 0.2 && maxDim > 0)) {
      const s = 4.2 / maxDim;
      model.scale.set(s, s, s);
      model.updateMatrixWorld(true);
      box.setFromObject(model);
      box.getSize(size);
      box.getCenter(center);
    }

    // Center on floor (y=0)
    model.position.x = -center.x;
    model.position.y = -box.min.y;
    model.position.z = -center.z;
    model.updateMatrixWorld(true);

    modelRadius = Math.max(Math.max(size.x, Math.max(size.y, size.z)) * 0.5, 0.5);
    modelCenter = new THREE.Vector3(0, size.y * 0.5, 0);

    // Adjust shadow plane to vehicle size
    if (groundShadow) {
      groundShadow.scale.set(Math.max(size.x * 0.45, 1.8), Math.max(size.z * 0.45, 3.6), 1);
      groundShadow.position.set(0, 0.0005, 0);
    }

    modelPivotGroup.add(model);
    scene.add(modelPivotGroup);

    // Fit camera to vehicle
    resetCamera();

    // Apply current render mode
    applyRenderMode(currentRenderMode);

    console.log('SketchfabViewer: Model successfully rendered! Meshes:', meshCount, 'Triangles:', triCount);
    if (callback) callback({ success: true, size: size, center: center });
  }

  function rotateModel(yawAngle) {
    if (!modelPivotGroup) {
      if (currentModel) {
        currentModel.rotation.y += yawAngle;
        currentModel.updateMatrixWorld(true);
      }
      return;
    }
    modelPivotGroup.rotation.y += yawAngle;
    modelPivotGroup.updateMatrixWorld(true);
    if (wireframeOverlayGroup) {
      applyRenderMode(currentRenderMode);
    }
    console.log('SketchfabViewer: Rotated model by yaw:', yawAngle, 'new rotation Y:', modelPivotGroup.rotation.y);
  }

  function flipModel() {
    rotateModel(Math.PI);
  }

  function purgeUnderWheelMeshesAndSnapToGround(detectedWheels) {
    if (!currentModel) return 0;
    currentModel.updateMatrixWorld(true);

    // 1. Calculate lowest tire contact level across detected wheels
    let minTireY = Infinity;
    const wheelMeshesSet = new Set();

    const wheelsObj = detectedWheels || (detectedWheelData ? detectedWheelData.wheels : null);
    if (wheelsObj) {
      Object.values(wheelsObj).forEach(w => {
        if (w && w.y != null && w.radius != null) {
          minTireY = Math.min(minTireY, w.y - w.radius);
        }
        if (w && w.meshes) {
          w.meshes.forEach(m => wheelMeshesSet.add(m));
        }
      });
    }

    if (detectedWheelData && detectedWheelData.allWheelMeshes) {
      detectedWheelData.allWheelMeshes.forEach(m => wheelMeshesSet.add(m));
    }

    if (!isFinite(minTireY)) {
      const carBox = new THREE.Box3().setFromObject(currentModel);
      minTireY = carBox.min.y;
    }

    const underWheelPattern = /(shadow|ground|floor|plane|turntable|pedestal|stage|platform|base|backdrop|grid|plinth|stand)/i;
    const toRemove = [];

    currentModel.traverse(function(child) {
      if (!child.isMesh) return;
      if (wheelMeshesSet.has(child)) return;

      const mName = (child.name || '').toLowerCase();
      const namedShadowOrFloor = underWheelPattern.test(mName);

      child.updateWorldMatrix(true, false);
      const b = new THREE.Box3().setFromObject(child);
      const h = b.max.y - b.min.y;

      // Sits under or flush with wheel contact level + 0.045m tolerance
      const sitsUnderWheel = b.max.y <= minTireY + 0.045;
      const isFlatThin = h <= 0.08;

      if ((sitsUnderWheel && isFlatThin) || (namedShadowOrFloor && sitsUnderWheel)) {
        toRemove.push(child);
      }
    });

    toRemove.forEach(mesh => {
      if (mesh.parent) {
        mesh.parent.remove(mesh);
      }
      disposeObject(mesh);
    });

    console.log('SketchfabViewer: Purged', toRemove.length, 'under-wheel shadow/floor meshes');

    // 2. Snap model so lowest tire vertex sits EXACTLY at Y = 0.0m (Zero ground clearance!)
    currentModel.updateMatrixWorld(true);
    let trueLowestTireY = Infinity;

    wheelMeshesSet.forEach(m => {
      m.updateWorldMatrix(true, false);
      const b = new THREE.Box3().setFromObject(m);
      if (isFinite(b.min.y)) {
        trueLowestTireY = Math.min(trueLowestTireY, b.min.y);
      }
    });

    if (isFinite(trueLowestTireY)) {
      currentModel.position.y -= trueLowestTireY;
    } else {
      const box = new THREE.Box3().setFromObject(modelPivotGroup || currentModel);
      currentModel.position.y -= box.min.y;
    }

    if (modelPivotGroup) modelPivotGroup.updateMatrixWorld(true);
    currentModel.updateMatrixWorld(true);

    if (wireframeOverlayGroup) {
      applyRenderMode(currentRenderMode);
    }
    console.log('SketchfabViewer: Snapped lowest tire contact to ground Y = 0.00m (adjusted by', -trueLowestTireY, ')');

    return toRemove.length;
  }

  function snapToGround() {
    return purgeUnderWheelMeshesAndSnapToGround(detectedWheelData ? detectedWheelData.wheels : null);
  }

  function applyScale(targetLength) {
    if (!modelPivotGroup || !currentModel) return;
    modelPivotGroup.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(modelPivotGroup);
    const size = box.getSize(new THREE.Vector3());
    const currentLength = Math.max(size.z, size.x);
    if (currentLength > 0.01 && targetLength > 0.01) {
      const factor = targetLength / currentLength;
      modelPivotGroup.scale.multiplyScalar(factor);
      modelPivotGroup.updateMatrixWorld(true);
      const scaledBox = new THREE.Box3().setFromObject(modelPivotGroup);
      const center = scaledBox.getCenter(new THREE.Vector3());
      currentModel.position.x -= center.x;
      currentModel.position.z -= center.z;
      snapToGround();
      resetCamera();
      if (wireframeOverlayGroup) {
        applyRenderMode(currentRenderMode);
      }
      console.log('SketchfabViewer: Scaled model to length:', targetLength, 'factor:', factor);
    }
  }

  function resetCamera() {
    if (!camera || !controls) return;
    const dist = Math.max(modelRadius * 2.6, 2.5);
    camera.position.set(dist * 0.85, dist * 0.45, dist * 0.85);
    controls.target.copy(modelCenter || new THREE.Vector3(0, 0.7, 0));
    camera.near = Math.max(0.01, dist * 0.01);
    camera.far = Math.max(500, dist * 50);
    camera.updateProjectionMatrix();
    controls.update();
    notifyCameraChange(true);
  }

  function setCameraPreset(preset) {
    if (!camera || !controls) return;
    const dist = Math.max(modelRadius * 2.6, 2.5);
    const cy = modelCenter ? modelCenter.y : 0.7;

    const p = (preset || '').toLowerCase().trim();
    switch (p) {
      case 'iso':
        camera.position.set(dist * 0.85, dist * 0.45, dist * 0.85);
        break;
      case 'front':
      case '-z':
      case '-z_axis':
        camera.position.set(0, cy, -dist);
        break;
      case 'back':
      case 'rear':
      case 'z':
      case '+z':
      case '+z_axis':
        camera.position.set(0, cy, dist);
        break;
      case 'left':
      case '-x':
      case '-x_axis':
        camera.position.set(-dist, cy, 0);
        break;
      case 'right':
      case 'x':
      case '+x':
      case '+x_axis':
        camera.position.set(dist, cy, 0);
        break;
      case 'top':
      case 'y':
      case '+y':
      case '+y_axis':
        camera.position.set(0, dist * 1.5, 0.001);
        break;
      case 'bottom':
      case '-y':
      case '-y_axis':
        camera.position.set(0, -dist * 1.5, 0.001);
        break;
    }
    controls.target.set(0, cy, 0);
    camera.updateProjectionMatrix();
    controls.update();
    notifyCameraChange(true);
  }

  function applyRenderMode(mode) {
    if (testDriveActive) return;
    currentRenderMode = mode;
    if (!currentModel) return;

    if (wireframeOverlayGroup) {
      scene.remove(wireframeOverlayGroup);
      disposeObject(wireframeOverlayGroup);
      wireframeOverlayGroup = null;
    }

    currentModel.traverse(function(child) {
      if (child.isMesh && child.material) {
        const mats = Array.isArray(child.material) ? child.material : [child.material];
        mats.forEach(mat => {
          const orig = originalMaterials.get(mat.uuid);
          if (mode === 'wireframe') {
            mat.wireframe = true;
          } else {
            mat.wireframe = false;
            if (orig) {
              mat.map = orig.map;
              mat.color.copy(orig.color);
            }
          }
        });
      }
    });

    if (mode === 'hybrid') {
      wireframeOverlayGroup = new THREE.Group();
      currentModel.traverse(function(child) {
        if (child.isMesh && child.geometry) {
          const wireGeo = new THREE.WireframeGeometry(child.geometry);
          const wireMat = new THREE.LineBasicMaterial({
            color: 0x10b981,
            transparent: true,
            opacity: 0.25
          });
          const wireMesh = new THREE.LineSegments(wireGeo, wireMat);
          wireMesh.matrix.copy(child.matrixWorld);
          wireMesh.matrixAutoUpdate = false;
          wireframeOverlayGroup.add(wireMesh);
        }
      });
      scene.add(wireframeOverlayGroup);
    }
  }

  function setLighting(lighting) {
    if (testDriveActive) return;
    currentLighting = lighting;
    if (!dirLightKey || !dirLightFill || !dirLightRim || !hemiLight || !scene) return;

    switch (lighting.toLowerCase()) {
      case 'daylight':
        scene.background.set(0x1a262c);
        hemiLight.color.set(0xffffff);
        hemiLight.groundColor.set(0x607d8b);
        hemiLight.intensity = 1.1;
        dirLightKey.color.set(0xfffaed);
        dirLightKey.intensity = 1.6;
        dirLightFill.intensity = 0.8;
        dirLightRim.intensity = 0.5;
        renderer.toneMappingExposure = 1.15;
        break;
      case 'night':
        scene.background.set(0x050706);
        hemiLight.color.set(0x334466);
        hemiLight.groundColor.set(0x111111);
        hemiLight.intensity = 0.35;
        dirLightKey.color.set(0x88bbff);
        dirLightKey.intensity = 0.7;
        dirLightFill.intensity = 0.3;
        dirLightRim.intensity = 1.2;
        renderer.toneMappingExposure = 0.95;
        break;
      case 'flat':
        scene.background.set(0x111714);
        hemiLight.color.set(0xffffff);
        hemiLight.groundColor.set(0xffffff);
        hemiLight.intensity = 1.6;
        dirLightKey.intensity = 0.0;
        dirLightFill.intensity = 0.0;
        dirLightRim.intensity = 0.0;
        renderer.toneMappingExposure = 1.0;
        break;
      case 'sunset':
        scene.background.set(0x1c1207);
        hemiLight.color.set(0xffd9b0);
        hemiLight.groundColor.set(0x2a1a12);
        hemiLight.intensity = 0.85;
        dirLightKey.color.set(0xffb066);
        dirLightKey.intensity = 1.5;
        dirLightFill.intensity = 0.45;
        dirLightRim.intensity = 0.6;
        renderer.toneMappingExposure = 1.05;
        break;
      case 'studio':
      default:
        scene.background.set(0x0c1318);
        hemiLight.color.set(0xffffff);
        hemiLight.groundColor.set(0x18241d);
        hemiLight.intensity = 1.0;
        dirLightKey.color.set(0xffffff);
        dirLightKey.intensity = 1.6;
        dirLightFill.intensity = 0.7;
        dirLightRim.intensity = 0.9;
        renderer.toneMappingExposure = 1.05;
        break;
    }
  }

  function setTurntable(enabled) {
    if (!controls) return;
    controls.autoRotate = !!enabled;
    controls.autoRotateSpeed = 2.0;
  }

  function buildForwardArrowHelper() {
    const grp = new THREE.Group();
    grp.name = 'forward_direction_arrow';

    // 1. Center dashed track from 0 to -2.1
    const trackPoints = [];
    for (let z = -0.4; z >= -2.0; z -= 0.4) {
      trackPoints.push(new THREE.Vector3(0, 0.0008, z));
      trackPoints.push(new THREE.Vector3(0, 0.0008, z - 0.25));
    }
    const trackGeo = new THREE.BufferGeometry().setFromPoints(trackPoints);
    const trackMat = new THREE.LineBasicMaterial({
      color: 0x34d399,
      transparent: true,
      opacity: 0.65,
      depthWrite: false
    });
    grp.add(new THREE.LineSegments(trackGeo, trackMat));

    // 2. Main Arrowhead & Shaft Geometry (Pointing towards -Z)
    const pos = [
      // Triangle 1: Tip, Left Barb, Left Notch
      0, 0.0012, -4.40,   -0.60, 0.0012, -3.65,   -0.22, 0.0012, -3.82,
      // Triangle 2: Tip, Right Notch, Right Barb
      0, 0.0012, -4.40,    0.22, 0.0012, -3.82,    0.60, 0.0012, -3.65,
      // Triangle 3: Tip, Left Notch, Right Notch
      0, 0.0012, -4.40,   -0.22, 0.0012, -3.82,    0.22, 0.0012, -3.82,
      // Triangle 4: Left Notch, Shaft Bottom-Left, Shaft Bottom-Right
      -0.22, 0.0012, -3.82,  -0.22, 0.0012, -2.10,   0.22, 0.0012, -2.10,
      // Triangle 5: Left Notch, Shaft Bottom-Right, Right Notch
      -0.22, 0.0012, -3.82,   0.22, 0.0012, -2.10,   0.22, 0.0012, -3.82
    ];
    const arrowGeo = new THREE.BufferGeometry();
    arrowGeo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    arrowGeo.computeVertexNormals();

    const arrowMat = new THREE.MeshBasicMaterial({
      color: 0x10b981,
      transparent: true,
      opacity: 0.55,
      side: THREE.DoubleSide,
      depthWrite: false
    });
    grp.add(new THREE.Mesh(arrowGeo, arrowMat));

    // 3. Arrow Perimeter Glowing Border
    const borderPoints = [
      new THREE.Vector3(0, 0.0016, -4.40),
      new THREE.Vector3(-0.60, 0.0016, -3.65),
      new THREE.Vector3(-0.22, 0.0016, -3.82),
      new THREE.Vector3(-0.22, 0.0016, -2.10),
      new THREE.Vector3(0.22, 0.0016, -2.10),
      new THREE.Vector3(0.22, 0.0016, -3.82),
      new THREE.Vector3(0.60, 0.0016, -3.65),
      new THREE.Vector3(0, 0.0016, -4.40)
    ];
    const borderGeo = new THREE.BufferGeometry().setFromPoints(borderPoints);
    const borderMat = new THREE.LineBasicMaterial({
      color: 0x6ee7b7,
      transparent: true,
      opacity: 0.95,
      depthWrite: false
    });
    grp.add(new THREE.Line(borderGeo, borderMat));

    // 4. Inner Glowing Chevrons (>>>)
    const chPoints = [
      new THREE.Vector3(-0.32, 0.0018, -2.85),
      new THREE.Vector3(0, 0.0018, -3.20),
      new THREE.Vector3(0, 0.0018, -3.20),
      new THREE.Vector3(0.32, 0.0018, -2.85),
      new THREE.Vector3(-0.32, 0.0018, -2.35),
      new THREE.Vector3(0, 0.0018, -2.70),
      new THREE.Vector3(0, 0.0018, -2.70),
      new THREE.Vector3(0.32, 0.0018, -2.35)
    ];
    const chGeo = new THREE.BufferGeometry().setFromPoints(chPoints);
    const chMat = new THREE.LineBasicMaterial({
      color: 0xa7f3d0,
      transparent: true,
      opacity: 0.90,
      depthWrite: false
    });
    grp.add(new THREE.LineSegments(chGeo, chMat));

    // 5. Stylized Ground Badge Pill: "▲ FORWARD (-Z)"
    const badgeCanvas = document.createElement('canvas');
    badgeCanvas.width = 512;
    badgeCanvas.height = 128;
    const ctx = badgeCanvas.getContext('2d');
    if (ctx) {
      ctx.fillStyle = 'rgba(10, 17, 14, 0.92)';
      ctx.strokeStyle = '#10b981';
      ctx.lineWidth = 6;
      ctx.beginPath();
      if (ctx.roundRect) {
        ctx.roundRect(16, 16, 480, 96, 48);
      } else {
        ctx.rect(16, 16, 480, 96);
      }
      ctx.fill();
      ctx.stroke();

      ctx.fillStyle = '#6ee7b7';
      ctx.font = 'bold 44px monospace, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('▲ FORWARD (-Z)', 256, 64);
    }
    const badgeTex = new THREE.CanvasTexture(badgeCanvas);
    const badgeGeo = new THREE.PlaneGeometry(1.5, 0.38);
    const badgeMat = new THREE.MeshBasicMaterial({
      map: badgeTex,
      transparent: true,
      depthWrite: false
    });
    const badgeMesh = new THREE.Mesh(badgeGeo, badgeMat);
    badgeMesh.rotation.x = -Math.PI / 2;
    badgeMesh.position.set(0, 0.002, -4.75);
    grp.add(badgeMesh);

    return grp;
  }

  function setForwardArrowVisible(visible) {
    showForwardArrow = !!visible;
    if (forwardArrowGroup) {
      forwardArrowGroup.visible = showForwardArrow;
    }
  }

  function buildCadGrid() {
    const grp = new THREE.Group();
    // 10m x 10m CAD grid with 20 subdivisions (0.5m spacing), matching Flutter CAD grid
    const grid = new THREE.GridHelper(10, 20, 0x10b981, 0x182c22);
    grid.position.y = 0.0004;
    if (grid.material) {
      grid.material.transparent = true;
      grid.material.opacity = 0.75;
      grid.material.depthWrite = false;
    }
    grp.add(grid);

    // Major axis lines (X axis in emerald & Z axis in vibrant emerald)
    const axisMatX = new THREE.LineBasicMaterial({
      color: 0x34d399,
      transparent: true,
      opacity: 0.85,
      depthWrite: false
    });
    const axisGeoX = new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(-5, 0.0005, 0),
      new THREE.Vector3(5, 0.0005, 0)
    ]);
    grp.add(new THREE.Line(axisGeoX, axisMatX));

    const axisMatZ = new THREE.LineBasicMaterial({
      color: 0x10b981,
      transparent: true,
      opacity: 0.95,
      depthWrite: false
    });
    const axisGeoZ = new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(0, 0.0005, -5),
      new THREE.Vector3(0, 0.0005, 5)
    ]);
    grp.add(new THREE.Line(axisGeoZ, axisMatZ));

    // Outer boundary frame (10m x 10m: hw = 5)
    const hw = 5.0;
    const framePoints = [
      new THREE.Vector3(-hw, 0.0004, -hw),
      new THREE.Vector3(hw, 0.0004, -hw),
      new THREE.Vector3(hw, 0.0004, hw),
      new THREE.Vector3(-hw, 0.0004, hw),
      new THREE.Vector3(-hw, 0.0004, -hw)
    ];
    const frameGeo = new THREE.BufferGeometry().setFromPoints(framePoints);
    const frameMat = new THREE.LineBasicMaterial({
      color: 0x10b981,
      transparent: true,
      opacity: 0.5,
      depthWrite: false
    });
    grp.add(new THREE.Line(frameGeo, frameMat));
    return grp;
  }

  function buildRadialGrid() {
    const grp = new THREE.Group();
    const radii = [0.8, 1.6, 2.5, 3.5, 4.8, 6.5];
    const segments = 64;

    // Dark turntable stage floor
    const stageGeo = new THREE.CircleGeometry(radii[radii.length - 1], 64);
    const stageMat = new THREE.MeshBasicMaterial({
      color: 0x05140e,
      transparent: true,
      opacity: 0.45,
      depthWrite: false
    });
    const stage = new THREE.Mesh(stageGeo, stageMat);
    stage.rotation.x = -Math.PI / 2;
    stage.position.y = 0.0002;
    grp.add(stage);

    // Concentric turntable rings
    for (let rIdx = 0; rIdx < radii.length; rIdx++) {
      const r = radii[rIdx];
      const isOuter = (rIdx === radii.length - 1);
      const points = [];
      for (let i = 0; i <= segments; i++) {
        const theta = (i / segments) * Math.PI * 2;
        points.push(new THREE.Vector3(Math.cos(theta) * r, 0.0004, Math.sin(theta) * r));
      }
      const ringGeo = new THREE.BufferGeometry().setFromPoints(points);
      const ringMat = new THREE.LineBasicMaterial({
        color: isOuter ? 0x34d399 : 0x10b981,
        transparent: true,
        opacity: isOuter ? 0.8 : 0.35,
        depthWrite: false
      });
      grp.add(new THREE.Line(ringGeo, ringMat));
    }

    // 12 Radial turntable spokes
    const spokeCount = 12;
    const maxR = radii[radii.length - 1];
    const spokePoints = [];
    const spokePointsCard = [];

    for (let i = 0; i < spokeCount; i++) {
      const theta = (i / spokeCount) * Math.PI * 2;
      const isCard = (i % 3 === 0);
      const target = isCard ? spokePointsCard : spokePoints;
      target.push(
        new THREE.Vector3(0, 0.0004, 0),
        new THREE.Vector3(Math.cos(theta) * maxR, 0.0004, Math.sin(theta) * maxR)
      );
    }

    if (spokePoints.length > 0) {
      const geo = new THREE.BufferGeometry().setFromPoints(spokePoints);
      const mat = new THREE.LineBasicMaterial({
        color: 0x34d399,
        transparent: true,
        opacity: 0.22,
        depthWrite: false
      });
      grp.add(new THREE.LineSegments(geo, mat));
    }

    if (spokePointsCard.length > 0) {
      const geoCard = new THREE.BufferGeometry().setFromPoints(spokePointsCard);
      const matCard = new THREE.LineBasicMaterial({
        color: 0x10b981,
        transparent: true,
        opacity: 0.65,
        depthWrite: false
      });
      grp.add(new THREE.LineSegments(geoCard, matCard));
    }

    // Degree tick marks on 4.8m ring
    const tickR1 = 4.65;
    const tickR2 = 4.95;
    const tickCount = 36;
    const tickPoints = [];
    for (let i = 0; i < tickCount; i++) {
      const theta = (i / tickCount) * Math.PI * 2;
      tickPoints.push(
        new THREE.Vector3(Math.cos(theta) * tickR1, 0.0004, Math.sin(theta) * tickR1),
        new THREE.Vector3(Math.cos(theta) * tickR2, 0.0004, Math.sin(theta) * tickR2)
      );
    }
    const tickGeo = new THREE.BufferGeometry().setFromPoints(tickPoints);
    const tickMat = new THREE.LineBasicMaterial({
      color: 0x34d399,
      transparent: true,
      opacity: 0.45,
      depthWrite: false
    });
    grp.add(new THREE.LineSegments(tickGeo, tickMat));

    return grp;
  }

  function buildHexGrid() {
    const grp = new THREE.Group();
    const r = 0.65;
    const dx = 1.5 * r;
    const dz = 1.7320508 * r;
    const range = 6;
    const maxDist = 7.2;

    const centerPoints = [];
    const outerPoints = [];
    const edgeMap = new Set();

    function addEdge(x1, z1, x2, z2, isCenter) {
      const k1 = Math.round(x1 * 1000) + '_' + Math.round(z1 * 1000);
      const k2 = Math.round(x2 * 1000) + '_' + Math.round(z2 * 1000);
      const key = k1 < k2 ? (k1 + ':' + k2) : (k2 + ':' + k1);
      if (edgeMap.has(key)) return;
      edgeMap.add(key);

      const target = isCenter ? centerPoints : outerPoints;
      target.push(
        new THREE.Vector3(x1, 0.0004, z1),
        new THREE.Vector3(x2, 0.0004, z2)
      );
    }

    for (let q = -range; q <= range; q++) {
      for (let rCol = -range; rCol <= range; rCol++) {
        const cx = q * dx;
        const cz = (rCol * dz) + (Math.abs(q) % 2 === 1 ? dz * 0.5 : 0.0);
        const dist = Math.sqrt(cx * cx + cz * cz);
        if (dist > maxDist) continue;

        const isCenter = dist < 2.2;

        for (let i = 0; i < 6; i++) {
          const a0 = i * Math.PI / 3.0;
          const a1 = (i + 1) * Math.PI / 3.0;
          const x0 = cx + r * Math.cos(a0);
          const z0 = cz + r * Math.sin(a0);
          const x1 = cx + r * Math.cos(a1);
          const z1 = cz + r * Math.sin(a1);
          addEdge(x0, z0, x1, z1, isCenter);
        }
      }
    }

    if (centerPoints.length > 0) {
      const centerGeo = new THREE.BufferGeometry().setFromPoints(centerPoints);
      const centerMat = new THREE.LineBasicMaterial({
        color: 0x34d399,
        transparent: true,
        opacity: 0.7,
        depthWrite: false
      });
      grp.add(new THREE.LineSegments(centerGeo, centerMat));
    }

    if (outerPoints.length > 0) {
      const outerGeo = new THREE.BufferGeometry().setFromPoints(outerPoints);
      const outerMat = new THREE.LineBasicMaterial({
        color: 0x10b981,
        transparent: true,
        opacity: 0.3,
        depthWrite: false
      });
      grp.add(new THREE.LineSegments(outerGeo, outerMat));
    }

    return grp;
  }

  function buildCheckerGrid() {
    const grp = new THREE.Group();
    const size = 20;

    const canvas = document.createElement('canvas');
    canvas.width = 256;
    canvas.height = 256;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#0a1d15';
    ctx.fillRect(0, 0, 256, 256);
    ctx.fillStyle = '#040d09';
    ctx.fillRect(0, 0, 128, 128);
    ctx.fillRect(128, 128, 128, 128);

    ctx.strokeStyle = 'rgba(16, 185, 129, 0.12)';
    ctx.lineWidth = 2;
    ctx.strokeRect(0, 0, 128, 128);
    ctx.strokeRect(128, 0, 128, 128);
    ctx.strokeRect(0, 128, 128, 128);
    ctx.strokeRect(128, 128, 128, 128);

    const tex = new THREE.CanvasTexture(canvas);
    tex.wrapS = THREE.RepeatWrapping;
    tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(size / 2, size / 2);

    const floorGeo = new THREE.PlaneGeometry(size, size);
    const floorMat = new THREE.MeshBasicMaterial({
      map: tex,
      transparent: true,
      opacity: 0.85,
      depthWrite: false
    });
    const floor = new THREE.Mesh(floorGeo, floorMat);
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = 0.0002;
    grp.add(floor);

    const grid = new THREE.GridHelper(size, size, 0x10b981, 0x1b382a);
    grid.position.y = 0.0004;
    if (grid.material) {
      grid.material.transparent = true;
      grid.material.opacity = 0.45;
      grid.material.depthWrite = false;
    }
    grp.add(grid);

    const crossPoints = [
      new THREE.Vector3(-size / 2, 0.0005, 0),
      new THREE.Vector3(size / 2, 0.0005, 0),
      new THREE.Vector3(0, 0.0005, -size / 2),
      new THREE.Vector3(0, 0.0005, size / 2)
    ];
    const crossGeo = new THREE.BufferGeometry().setFromPoints(crossPoints);
    const crossMat = new THREE.LineBasicMaterial({
      color: 0x34d399,
      transparent: true,
      opacity: 0.85,
      depthWrite: false
    });
    grp.add(new THREE.LineSegments(crossGeo, crossMat));

    const hw = size / 2;
    const borderPoints = [
      new THREE.Vector3(-hw, 0.0005, -hw),
      new THREE.Vector3(hw, 0.0005, -hw),
      new THREE.Vector3(hw, 0.0005, hw),
      new THREE.Vector3(-hw, 0.0005, hw),
      new THREE.Vector3(-hw, 0.0005, -hw)
    ];
    const borderGeo = new THREE.BufferGeometry().setFromPoints(borderPoints);
    const borderMat = new THREE.LineBasicMaterial({
      color: 0x10b981,
      transparent: true,
      opacity: 0.6,
      depthWrite: false
    });
    grp.add(new THREE.Line(borderGeo, borderMat));

    return grp;
  }

  function getOrCreateGrid(style) {
    if (gridStyleMap[style]) {
      return gridStyleMap[style];
    }
    let grp = null;
    switch (style) {
      case 'radial':
        grp = buildRadialGrid();
        break;
      case 'hex':
        grp = buildHexGrid();
        break;
      case 'checker':
        grp = buildCheckerGrid();
        break;
      case 'cad':
      default:
        grp = buildCadGrid();
        break;
    }
    if (grp) {
      gridStyleMap[style] = grp;
      if (gridGroup) gridGroup.add(grp);
    }
    return grp;
  }

  function setGridStyle(style) {
    if (testDriveActive) return;
    const s = (style || 'cad').toLowerCase();
    currentGridStyle = s;

    if (!gridGroup) return;

    if (s === 'off') {
      gridGroup.visible = false;
      return;
    }

    gridGroup.visible = true;

    for (const key in gridStyleMap) {
      if (gridStyleMap[key]) {
        gridStyleMap[key].visible = false;
      }
    }

    const target = getOrCreateGrid(s);
    if (target) {
      target.visible = true;
    }
  }

  function setWheelMarkers(wheels) {
    if (!markersGroup) return;
    while (markersGroup.children.length > 0) {
      disposeObject(markersGroup.children[0]);
      markersGroup.remove(markersGroup.children[0]);
    }
    // No floating circle/cylinder/torus markers - wheel geometry is highlighted directly via materials
  }

  let detectedWheelData = null;

  function clearWheelDataAndMarkers() {
    detectedWheelData = null;
    if (markersGroup) {
      while (markersGroup.children.length > 0) {
        disposeObject(markersGroup.children[0]);
        markersGroup.remove(markersGroup.children[0]);
      }
    }
    if (currentModel) {
      currentModel.traverse(function(child) {
        if (child.isMesh && child.userData.origMaterial) {
          child.material = child.userData.origMaterial;
          delete child.userData.origMaterial;
        }
        if (child.isMesh && child.userData.cyanOverride) {
          delete child.userData.cyanOverride;
        }
      });
    }
  }

  function detectWheels(options) {
    if (!currentModel) return null;
    currentModel.updateMatrixWorld(true);

    const groundTol = (options && options.groundTolerance != null) ? options.groundTolerance : 0.08;
    const inbTol = (options && options.inboardCaptureWidth != null) ? options.inboardCaptureWidth : 0.02;

    // Step 1: World-Space Bounds & Axis Setup
    const carBox = new THREE.Box3().setFromObject(currentModel);
    const carSize = carBox.getSize(new THREE.Vector3());
    const carCenter = carBox.getCenter(new THREE.Vector3());

    const fAxis = carSize.z >= carSize.x ? 'z' : 'x';
    const lAxis = fAxis === 'z' ? 'x' : 'z';
    const carLength = Math.max(0.001, carSize[fAxis]);
    const carWidth = Math.max(0.001, carSize[lAxis]);
    const carHeight = Math.max(0.001, carSize.y);
    const groundY = carBox.min.y;

    // Collect all loose parts with accurate world-space bounding boxes
    const allParts = [];
    currentModel.traverse(function(child) {
      if (child.isMesh) {
        child.updateWorldMatrix(true, false);
        const box = new THREE.Box3().setFromObject(child);
        const size = box.getSize(new THREE.Vector3());
        const center = box.getCenter(new THREE.Vector3());

        const dForward = size[fAxis];
        const dUp = size.y;
        const dLat = size[lAxis];
        const diameter = Math.max(dForward, dUp);
        const circularity = diameter > 1e-5 ? Math.min(dForward, dUp) / diameter : 0.0;
        const heightAboveGround = Math.max(0, box.min.y - groundY);
        const groundScore = Math.max(0, 1.0 - heightAboveGround / Math.max(1e-4, groundTol * carHeight));
        const outerLatDist = Math.max(Math.abs(box.min[lAxis] - carCenter[lAxis]), Math.abs(box.max[lAxis] - carCenter[lAxis]));
        const outerScore = Math.min(1.0, outerLatDist / Math.max(1e-4, 0.48 * carWidth));
        const sizeScore = Math.min(1.0, diameter / Math.max(1e-4, 0.22 * carLength));

        const cName = (child.name || '').toLowerCase();
        const namedWheel = cName.includes('wheel') || cName.includes('tire') || cName.includes('tyre') || cName.includes('rim');

        // Step 2 Anchor Ring Candidates:
        // Circular parts in the outer lateral track near the ground
        const isAnchorRing = (
          (diameter >= 0.08 * carLength && diameter <= 0.36 * carLength) &&
          (circularity >= (namedWheel ? 0.60 : 0.75)) &&
          (center.y < groundY + 0.35 * carHeight) &&
          (Math.abs(center[lAxis] - carCenter[lAxis]) > 0.25 * carWidth) &&
          // Thin across the axle: rejects axle shafts and chassis crossmembers.
          (dLat <= 0.25 * carWidth && dLat <= 1.25 * diameter)
        );

        allParts.push({
          mesh: child,
          name: child.name || ('mesh_' + allParts.length),
          box: box,
          size: size,
          center: center,
          dForward: dForward,
          dUp: dUp,
          dLat: dLat,
          diameter: diameter,
          circularity: circularity,
          groundScore: groundScore,
          outerScore: outerScore,
          sizeScore: sizeScore,
          named: namedWheel,
          isAnchorRing: isAnchorRing
        });
      }
    });

    // Step 2: Group Coaxial Circular Parts into Hub Clusters in 4 Quadrants
    const quadrantRings = { FL: [], FR: [], RL: [], RR: [] };
    allParts.filter(p => p.isAnchorRing).forEach(part => {
      const isFront = part.center[fAxis] <= carCenter[fAxis];
      const isLeft = part.center[lAxis] <= carCenter[lAxis];
      const corner = (isFront ? 'F' : 'R') + (isLeft ? 'L' : 'R');
      quadrantRings[corner].push(part);
    });

    const maxSpinAxisDist = 0.05 * carLength;

    function buildHubClusters(ringParts) {
      if (!ringParts.length) return [];
      const n = ringParts.length;
      const parent = ringParts.map((_, i) => i);
      function findRoot(i) {
        let root = i;
        while (parent[root] !== root) root = parent[root];
        let curr = i;
        while (parent[curr] !== root) {
          const next = parent[curr];
          parent[curr] = root;
          curr = next;
        }
        return root;
      }
      function unionRoots(i, j) {
        const rootI = findRoot(i);
        const rootJ = findRoot(j);
        if (rootI !== rootJ) parent[rootJ] = rootI;
      }

      for (let i = 0; i < n; i++) {
        for (let j = i + 1; j < n; j++) {
          const dist2D = Math.hypot(
            ringParts[i].center[fAxis] - ringParts[j].center[fAxis],
            ringParts[i].center.y - ringParts[j].center.y
          );
          // Coaxial only: wide axle shafts must not merge a whole axle.
          const latDist = Math.abs(ringParts[i].center[lAxis] - ringParts[j].center[lAxis]);
          if (dist2D <= maxSpinAxisDist && latDist <= 0.14 * carWidth) {
            unionRoots(i, j);
          }
        }
      }

      const clusterMap = new Map();
      for (let i = 0; i < n; i++) {
        const root = findRoot(i);
        if (!clusterMap.has(root)) clusterMap.set(root, []);
        clusterMap.get(root).push(ringParts[i]);
      }

      const clusters = [];
      for (const rings of clusterMap.values()) {
        const clusterBox = new THREE.Box3();
        rings.forEach(r => clusterBox.union(r.box));

        const cSize = clusterBox.getSize(new THREE.Vector3());
        const cCenter = clusterBox.getCenter(new THREE.Vector3());
        const outerDiameter = Math.max(cSize[fAxis], cSize.y);
        const clusterWidth = cSize[lAxis];
        const heightAboveGround = Math.max(0, clusterBox.min.y - groundY);
        const groundScore = Math.max(0, 1.0 - heightAboveGround / Math.max(1e-4, 0.08 * carHeight));
        const circularity = outerDiameter > 1e-5 ? Math.min(cSize[fAxis], cSize.y) / outerDiameter : 0.0;
        const outerLatDist = Math.max(
          Math.abs(clusterBox.min[lAxis] - carCenter[lAxis]),
          Math.abs(clusterBox.max[lAxis] - carCenter[lAxis])
        );
        const outerScore = Math.min(1.0, outerLatDist / Math.max(1e-4, 0.48 * carWidth));
        const sizeScore = Math.min(1.0, outerDiameter / Math.max(1e-4, 0.22 * carLength));
        const hasNamed = rings.some(r => r.named);

        const touchesGround = heightAboveGround <= (groundTol * carHeight + 1e-4);
        const validDiameter = outerDiameter >= 0.10 * carLength && outerDiameter <= 0.38 * carLength;

        const score = 0.35 * groundScore + 0.25 * circularity + 0.25 * outerScore + 0.15 * sizeScore + (hasNamed ? 0.3 : 0.0);

        clusters.push({
          rings: rings,
          clusterBox: clusterBox,
          outerDiameter: outerDiameter,
          clusterWidth: clusterWidth,
          clusterCenter: cCenter,
          groundScore: groundScore,
          circularity: circularity,
          outerScore: outerScore,
          sizeScore: sizeScore,
          score: score,
          touchesGround: touchesGround,
          validDiameter: validDiameter,
          hasNamed: hasNamed
        });
      }

      // Prefer clusters that touch ground and have valid diameter
      clusters.sort((a, b) => {
        const aValid = a.touchesGround && a.validDiameter;
        const bValid = b.touchesGround && b.validDiameter;
        if (aValid && !bValid) return -1;
        if (!aValid && bValid) return 1;
        return b.score - a.score;
      });

      return clusters;
    }

    const quadrantClusters = {
      FL: buildHubClusters(quadrantRings.FL),
      FR: buildHubClusters(quadrantRings.FR),
      RL: buildHubClusters(quadrantRings.RL),
      RR: buildHubClusters(quadrantRings.RR)
    };

    function matchClusterAxlePair(leftClusters, rightClusters) {
      if (!leftClusters.length && !rightClusters.length) return [null, null];
      if (!leftClusters.length) return [null, rightClusters[0]];
      if (!rightClusters.length) return [leftClusters[0], null];

      let bestL = leftClusters[0], bestR = rightClusters[0], bestScore = -Infinity;
      for (const l of leftClusters) {
        for (const r of rightClusters) {
          const maxD = Math.max(l.outerDiameter, r.outerDiameter);
          const diffD = maxD > 1e-4 ? Math.abs(l.outerDiameter - r.outerDiameter) / maxD : 0;
          const maxW = Math.max(l.clusterWidth, r.clusterWidth);
          const diffW = maxW > 1e-4 ? Math.abs(l.clusterWidth - r.clusterWidth) / maxW : 0;
          const diffPos = Math.abs(l.clusterCenter[fAxis] - r.clusterCenter[fAxis]);

          let bonus = 0;
          if (diffD <= 0.06) bonus += 0.5;
          if (diffW <= 0.08) bonus += 0.5;
          if (diffPos <= 0.05 * carLength) bonus += 0.5;

          const pairScore = l.score + r.score + bonus;
          if (pairScore > bestScore) {
            bestScore = pairScore;
            bestL = l;
            bestR = r;
          }
        }
      }
      return [bestL, bestR];
    }

    const [flCluster, frCluster] = matchClusterAxlePair(quadrantClusters.FL, quadrantClusters.FR);
    const [rlCluster, rrCluster] = matchClusterAxlePair(quadrantClusters.RL, quadrantClusters.RR);

    const winningClusters = { FL: flCluster, FR: frCluster, RL: rlCluster, RR: rrCluster };

    // Step 3A: Lock the True Tire & Rim Envelope First (coreWheelBox)
    // Step 3B: Two-Zone Capture (Outer Tire Envelope + Inner Brake/Hub Pocket)
    // Step 4: Sub-Classify spinMeshes vs. caliperHubMeshes & Preserve Tire R/W
    const allWheelMeshes = new Set();
    const wheelsResult = {};
    const brakeDiscsParts = [];
    const suspensionKnuckleParts = [];

    Object.entries(winningClusters).forEach(([corner, cluster]) => {
      if (!cluster) return;
      // Step 3A: Lock the True Tire & Rim Envelope First (coreWheelBox)
      const coreWheelBox = cluster.clusterBox;
      const hubF = (coreWheelBox.min[fAxis] + coreWheelBox.max[fAxis]) / 2;
      const hubY = (coreWheelBox.min.y + coreWheelBox.max.y) / 2;
      const tireRadius = Math.max(coreWheelBox.max[fAxis] - coreWheelBox.min[fAxis], coreWheelBox.max.y - coreWheelBox.min.y) / 2;
      const tireWidth = Math.min(coreWheelBox.max[lAxis] - coreWheelBox.min[lAxis], tireRadius * 1.15);
      const minLat = coreWheelBox.min[lAxis];
      const maxLat = coreWheelBox.max[lAxis];
      const hubCenter = coreWheelBox.getCenter(new THREE.Vector3());

      const cornerMeshes = new Set();
      const spinMeshes = [];
      const caliperHubMeshes = [];

      // Always include winning cluster rings (Tire, Rim)
      cluster.rings.forEach(r => {
        cornerMeshes.add(r.mesh);
        spinMeshes.push(r.mesh);
      });

      // Step 3B: Two-Zone Capture across all loose parts
      const inboardAllowance = Math.max(0.45 * tireWidth, Math.max(0.02, inbTol) * carWidth);

      allParts.forEach(part => {
        if (cluster.rings.some(r => r.mesh === part.mesh)) return;

        // Zone 1 — Tire, Rim, Spokes, Lug Nuts & Center Caps:
        // 1. Radially inside the tire in side view (fAxis, y):
        const fitsRadiallyZone1 = (
          part.box.min[fAxis] >= hubF - tireRadius * 1.04 &&
          part.box.max[fAxis] <= hubF + tireRadius * 1.04 &&
          part.box.min.y >= hubY - tireRadius * 1.04 &&
          part.box.max.y <= hubY + tireRadius * 1.04
        );
        // 2. Laterally inside the tire sidewalls:
        const fitsLatZone1 = (
          part.box.min[lAxis] >= minLat - 0.05 * tireWidth &&
          part.box.max[lAxis] <= maxLat + 0.05 * tireWidth
        );
        const isZone1 = fitsRadiallyZone1 && fitsLatZone1;

        // Zone 2 — Inner Brake Disc, Caliper & Hub Frame Pocket:
        // 1. Fits Inside the Rim Barrel in Side View (fAxis, y):
        const fitsRadiallyZone2 = (
          part.box.min[fAxis] >= hubF - tireRadius * 0.95 &&
          part.box.max[fAxis] <= hubF + tireRadius * 0.95 &&
          part.box.min.y >= hubY - tireRadius * 0.95 &&
          part.box.max.y <= hubY + tireRadius * 0.95
        );
        // 2. Expanded Inboard Hub Pocket (lAxis):
        const fitsLatZone2 = (
          part.box.min[lAxis] >= minLat - inboardAllowance &&
          part.box.max[lAxis] <= maxLat + inboardAllowance
        );
        // 3. Compactness Guard (blocks long suspension wishbones, tie rods, axles):
        const isCompact = part.size[lAxis] <= tireWidth * 1.15;
        const touchesHub = (
          part.box.max[lAxis] >= minLat - 0.15 * tireWidth &&
          part.box.min[lAxis] <= maxLat + 0.15 * tireWidth
        );
        const inOuterTrack = Math.abs(part.center[lAxis] - carCenter[lAxis]) >= 0.26 * carWidth;

        const isZone2 = fitsRadiallyZone2 && fitsLatZone2 && isCompact && touchesHub && inOuterTrack;

        if (isZone1 || isZone2) {
          cornerMeshes.add(part.mesh);

          // Step 4: Sub-classify spinMeshes vs caliperHubMeshes
          const isCoaxial = (
            Math.abs(part.center.y - hubY) < 0.10 * tireRadius &&
            Math.abs(part.center[fAxis] - hubF) < 0.10 * tireRadius
          );

          if (!isCoaxial || (isZone2 && part.circularity < 0.78)) {
            caliperHubMeshes.push(part.mesh); // Brake Caliper / Hub Frame
          } else {
            spinMeshes.push(part.mesh); // Tire, Rim, Spokes, Brake Rotor
            if (isZone2) {
              brakeDiscsParts.push(part.mesh);
            }
          }
        } else if (fitsRadiallyZone1 && !fitsLatZone2) {
          if (Math.abs(part.center.y - hubY) < 0.25 * carHeight &&
              Math.abs(part.center[fAxis] - hubF) < 0.15 * carLength) {
            suspensionKnuckleParts.push(part.mesh);
          }
        }
      });

      const cornerMeshList = Array.from(cornerMeshes);
      cornerMeshList.forEach(m => allWheelMeshes.add(m));

      // Primary mesh for naming: ring with largest diameter in this cluster
      let primaryPart = cluster.rings[0];
      let maxPartDiam = -1;
      cluster.rings.forEach(r => {
        if (r.diameter > maxPartDiam) {
          maxPartDiam = r.diameter;
          primaryPart = r;
        }
      });

      // Step 4: Keep R and W strictly locked to coreWheelBox (prevents caliper inflation!)
      wheelsResult[corner] = {
        name: primaryPart ? primaryPart.name : ('Wheel_' + corner),
        mesh: primaryPart ? primaryPart.mesh : cornerMeshList[0],
        x: hubCenter.x,
        y: hubCenter.y,
        z: hubCenter.z,
        radius: tireRadius,         // Preserved from coreWheelBox!
        width: tireWidth,           // Preserved from coreWheelBox!
        circularity: cluster.circularity,
        subMeshCount: cornerMeshList.length,
        meshes: cornerMeshList,
        spinMeshes: spinMeshes,
        caliperHubMeshes: caliperHubMeshes,
        partNames: cornerMeshList.map(m => m.name || '').filter(Boolean),
        spinPartNames: spinMeshes.map(m => m.name || '').filter(Boolean),
        caliperHubPartNames: caliperHubMeshes.map(m => m.name || '').filter(Boolean)
      };
    });

    // Auto-delete any under-wheel shadow planes/floors and snap tire contact to Y = 0.0m
    purgeUnderWheelMeshesAndSnapToGround(wheelsResult);

    function buildHighlightedMeshBox(m) {
      m.updateWorldMatrix(true, false);
      const b = new THREE.Box3().setFromObject(m);
      const c = b.getCenter(new THREE.Vector3());
      const s = b.getSize(new THREE.Vector3());
      return {
        name: (m.name || '').toLowerCase(),
        parentName: (m.parent && m.parent.name ? m.parent.name : '').toLowerCase(),
        cx: c.x,
        cy: c.y,
        cz: c.z,
        sx: s.x,
        sy: s.y,
        sz: s.z
      };
    }

    // Re-synchronize wheel hub coordinates and record exact 3D boxes of every
    // highlighted wheel mesh so Dart maps the exact same parts in Test Drive.
    Object.keys(wheelsResult).forEach(corner => {
      const w = wheelsResult[corner];
      const spinList = (w.spinMeshes && w.spinMeshes.length) ? w.spinMeshes : (w.meshes || []);
      const calList = w.caliperHubMeshes || [];
      const targetMeshes = spinList.length > 0 ? spinList : (w.meshes || []);
      if (targetMeshes.length > 0) {
        const b = new THREE.Box3();
        targetMeshes.forEach(m => {
          m.updateWorldMatrix(true, false);
          b.union(new THREE.Box3().setFromObject(m));
        });
        const c = b.getCenter(new THREE.Vector3());
        w.x = c.x;
        w.y = c.y;
        w.z = c.z;
      } else if (w.mesh) {
        w.mesh.updateWorldMatrix(true, false);
        const b = new THREE.Box3().setFromObject(w.mesh);
        const c = b.getCenter(new THREE.Vector3());
        w.x = c.x;
        w.y = c.y;
        w.z = c.z;
      }
      w.spinMeshBoxes = spinList.map(buildHighlightedMeshBox);
      w.caliperMeshBoxes = calList.map(buildHighlightedMeshBox);
    });

    // Staggered check (2+2 vs 4x)
    let isStaggered = false;
    if (wheelsResult.FL && wheelsResult.RL) {
      const diffDiam = Math.abs(wheelsResult.FL.radius - wheelsResult.RL.radius) / Math.max(wheelsResult.FL.radius, wheelsResult.RL.radius);
      const diffW = Math.abs(wheelsResult.FL.width - wheelsResult.RL.width) / Math.max(wheelsResult.FL.width, wheelsResult.RL.width);
      if (diffDiam > 0.06 || diffW > 0.06) {
        isStaggered = true;
      }
    }

    const allCaliperHubMeshes = [];
    Object.values(wheelsResult).forEach(w => {
      if (w.caliperHubMeshes) allCaliperHubMeshes.push(...w.caliperHubMeshes);
    });

    detectedWheelData = {
      wheels: wheelsResult,
      allWheelMeshes: Array.from(allWheelMeshes),
      isStaggered: isStaggered,
      loosePartsCount: allParts.length,
      candidateGroups: [
        { id: 1, name: 'Outer Tires + Rims (4 corners · Grounded)', count: Object.keys(wheelsResult).length, role: 'Spin (Wheel)', isEnabled: true, meshes: Array.from(allWheelMeshes) },
        { id: 2, name: 'Brake Calipers & Hub Frames (Captured in Wheel Group)', count: allCaliperHubMeshes.length, role: 'Steer Only (Knuckle/Caliper)', isEnabled: true, meshes: allCaliperHubMeshes },
        { id: 3, name: 'Suspension Uprights / Knuckles (Inboard Chassis)', count: suspensionKnuckleParts.length, role: 'Static (Chassis)', isEnabled: false, meshes: suspensionKnuckleParts }
      ]
    };

    return detectedWheelData;
  }

  // Shared highlight materials: allocated once so hover/rescan never leaks a
  // new GPU material per mesh on every pass.
  let sharedWheelHighlightMat = null;
  let sharedCyanHighlightMat = null;

  function wheelHighlightMaterial() {
    if (!sharedWheelHighlightMat) {
      sharedWheelHighlightMat = new THREE.MeshStandardMaterial({
        color: 0x10b981,
        emissive: 0x059669,
        emissiveIntensity: 0.5,
        roughness: 0.2,
        metalness: 0.8
      });
    }
    return sharedWheelHighlightMat;
  }

  function cyanHighlightMaterial() {
    if (!sharedCyanHighlightMat) {
      sharedCyanHighlightMat = new THREE.MeshStandardMaterial({
        color: 0x00e5ff,
        emissive: 0x008ba3,
        emissiveIntensity: 0.7,
        roughness: 0.2,
        metalness: 0.8
      });
    }
    return sharedCyanHighlightMat;
  }

  function highlightWheelMeshes(wheelNodeNames) {
    if (!currentModel) return;

    // Reset previous overrides if any
    currentModel.traverse(function(child) {
      if (child.isMesh && child.userData.origMaterial) {
        child.material = child.userData.origMaterial;
        delete child.userData.origMaterial;
      }
    });

    // If wheelNodeNames is false, null, undefined, or an empty list, NEVER highlight any meshes!
    if (!wheelNodeNames || wheelNodeNames === false || (Array.isArray(wheelNodeNames) && wheelNodeNames.length === 0)) {
      return;
    }

    let targets = null;
    if (detectedWheelData && detectedWheelData.allWheelMeshes && detectedWheelData.allWheelMeshes.length > 0) {
      targets = new Set(detectedWheelData.allWheelMeshes);
    }

    currentModel.traverse(function(child) {
      if (child.isMesh) {
        let isWheel = false;
        if (targets) {
          isWheel = targets.has(child);
        } else if (Array.isArray(wheelNodeNames) && wheelNodeNames.length > 0) {
          const names = wheelNodeNames.map(n => (n || '').toLowerCase());
          const cName = (child.name || '').toLowerCase();
          isWheel = names.some(n => cName.includes(n));
        }

        if (isWheel) {
          if (!child.userData.origMaterial) {
            child.userData.origMaterial = child.material;
          }
          child.material = wheelHighlightMaterial();
        }
      }
    });
  }

  function highlightMeshesCyan(meshNamesOrList) {
    if (!currentModel) return;
    currentModel.traverse(function(child) {
      if (child.isMesh && child.userData.cyanOverride) {
        child.material = child.userData.origMaterial || child.material;
        delete child.userData.cyanOverride;
      }
    });

    if (!meshNamesOrList) return;

    const nameList = Array.isArray(meshNamesOrList)
      ? meshNamesOrList.map(n => (typeof n === 'string' ? n.toLowerCase() : ''))
      : [String(meshNamesOrList).toLowerCase()];

    currentModel.traverse(function(child) {
      if (child.isMesh) {
        const cName = (child.name || '').toLowerCase();
        const matches = nameList.some(n => cName.includes(n) || (child.uuid && child.uuid === n));
        if (matches) {
          if (!child.userData.origMaterial) {
            child.userData.origMaterial = child.material;
          }
          child.userData.cyanOverride = true;
          child.material = cyanHighlightMaterial();
        }
      }
    });
  }

  function disposeObject(obj) {
    if (!obj) return;
    obj.traverse(function(child) {
      if (child.geometry) child.geometry.dispose();
      if (child.material) {
        const mats = Array.isArray(child.material) ? child.material : [child.material];
        mats.forEach(m => {
          if (m === sharedWheelHighlightMat || m === sharedCyanHighlightMat) return;
          if (m.map) m.map.dispose();
          m.dispose();
        });
      }
    });
  }

  let audioCtx = null;
  let currentPreviewOsc = null;
  let currentPreviewSource = null;
  // Multi-Layer Engine & Exhaust Synthesizer
  let engineOscA = null;
  let engineOscB = null;
  let engineOscSub = null;
  let enginePreSatGain = null;
  let engineWaveShaper = null;
  let engineFilter = null;
  let engineFlutterOsc = null;
  let engineFlutterGain = null;
  let engineTurboOsc = null;
  let engineTurboGain = null;
  let engineGain = null;
  let sirenOsc = null;
  let sirenLfo = null;
  let sirenGain = null;
  let lastAudioRpm = 0;
  let lastAudioThrottle = 0;
  let lastShiftBarkTime = 0;
  let lastOverrunTime = 0;

  // Realistic Tire Scrub & Screech Synthesizer
  let sharedWhiteNoiseBuffer = null;
  let skidSource = null;
  let skidNoiseFilter = null;
  let skidNoiseGain = null;
  let skidToneA = null;
  let skidToneB = null;
  let skidToneGain = null;
  let skidMasterGain = null;

  function ensureAudioContext() {
    if (!audioCtx) {
      audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }
    if (audioCtx.state === 'suspended') audioCtx.resume();
    return audioCtx;
  }

  function toAudioArrayBuffer(data) {
    if (!data) return null;
    if (data instanceof ArrayBuffer) return data;
    if (ArrayBuffer.isView(data)) {
      return data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
    }
    if (Array.isArray(data)) return new Uint8Array(data).buffer;
    if (data.buffer instanceof ArrayBuffer) {
      return data.buffer.slice(data.byteOffset || 0, (data.byteOffset || 0) + data.byteLength);
    }
    return null;
  }

  function playAudioPreview(slotId, pitchMultiplier, bytes) {
    try {
      const ctx = ensureAudioContext();
      stopAudioPreview();

      // Step 4 uploads: decode and play the actual authored audio bytes.
      const raw = toAudioArrayBuffer(bytes);
      if (raw && raw.byteLength > 44) {
        ctx.decodeAudioData(
          raw.slice(0),
          function(buffer) {
            try {
              const src = ctx.createBufferSource();
              src.buffer = buffer;
              src.playbackRate.value = Math.max(0.25, Math.min(4.0, pitchMultiplier || 1.0));
              src.connect(ctx.destination);
              src.start();
              currentPreviewSource = src;
            } catch (e) {
              console.warn('Audio preview playback error:', e);
            }
          },
          function(err) { console.warn('decodeAudioData failed:', err); }
        );
        return;
      }

      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      const id = String(slotId || '').toLowerCase();
      const baseFreq = id.includes('rpm') ? 220 : id.includes('idle') ? 110 : id.includes('skid') ? 440 : 150;
      osc.type = id.includes('skid') ? 'sawtooth' : 'triangle';
      osc.frequency.setValueAtTime(baseFreq * (pitchMultiplier || 1.0), audioCtx.currentTime);
      gain.gain.setValueAtTime(0.12, audioCtx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 1.0);
      osc.connect(gain);
      gain.connect(audioCtx.destination);
      osc.start();
      osc.stop(audioCtx.currentTime + 1.0);
      currentPreviewOsc = osc;
    } catch (e) {
      console.warn('Audio preview error:', e);
    }
  }

  function stopAudioPreview() {
    if (currentPreviewOsc) {
      try { currentPreviewOsc.stop(); } catch(e) {}
      currentPreviewOsc = null;
    }
    if (currentPreviewSource) {
      try { currentPreviewSource.stop(); } catch(e) {}
      currentPreviewSource = null;
    }
  }

  // ── Web Audio Engine, Exhaust, Siren, and Skid Synthesizers ───────────────────
  // Audio synthesis runs natively on the browser AudioRenderThread (<0.02ms overhead).
  const ENGINE_PROFILES = {
    v10: { fundamental: 34, harmonic: 2.02, filter: 2600, gain: 0.16 },
    v8: { fundamental: 27, harmonic: 1.5, filter: 1500, gain: 0.18 },
    turbo_i4: { fundamental: 24, harmonic: 2.5, filter: 2000, gain: 0.14 },
    ev: { fundamental: 90, harmonic: 3.0, filter: 5200, gain: 0.10 }
  };

  function makeDistortionCurve(k) {
    const n_samples = 512;
    const curve = new Float32Array(n_samples);
    const amount = (k !== undefined) ? k : 1.8;
    for (let i = 0; i < n_samples; ++i) {
      const x = (i * 2) / n_samples - 1;
      curve[i] = Math.tanh(amount * x);
    }
    return curve;
  }

  function getWhiteNoiseBuffer(ctx) {
    if (sharedWhiteNoiseBuffer) return sharedWhiteNoiseBuffer;
    const len = ctx.sampleRate;
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < len; i++) {
      data[i] = Math.random() * 2 - 1;
    }
    sharedWhiteNoiseBuffer = buf;
    return sharedWhiteNoiseBuffer;
  }

  function triggerExhaustPop(ctx, intensity) {
    try {
      if (!ctx || ctx.state === 'suspended') return;
      const t = ctx.currentTime;
      const popOsc = ctx.createOscillator();
      const popGain = ctx.createGain();
      const popFilter = ctx.createBiquadFilter();

      popOsc.type = 'triangle';
      popOsc.frequency.setValueAtTime(85 + Math.random() * 40, t);
      popOsc.frequency.exponentialRampToValueAtTime(26, t + 0.05);

      popFilter.type = 'lowpass';
      popFilter.frequency.setValueAtTime(420, t);

      const amp = Math.min(0.24, 0.08 * (intensity || 1.0));
      popGain.gain.setValueAtTime(amp, t);
      popGain.gain.exponentialRampToValueAtTime(0.0001, t + 0.06);

      popOsc.connect(popFilter);
      popFilter.connect(popGain);
      popGain.connect(ctx.destination);

      popOsc.start(t);
      popOsc.stop(t + 0.07);
    } catch (e) {}
  }

  function triggerOverrunBurble(ctx) {
    try {
      const popCount = 2 + Math.floor(Math.random() * 3);
      for (let i = 0; i < popCount; i++) {
        const delay = 0.04 + i * (0.07 + Math.random() * 0.05);
        setTimeout(function () {
          triggerExhaustPop(ctx, 0.75 + Math.random() * 0.45);
        }, delay * 1000);
      }
    } catch (e) {}
  }

  function updateEngineAndSirenAudio(rpm, throttle, profile, sirenEnabled) {
    try {
      const ctx = ensureAudioContext();
      const cfg = ENGINE_PROFILES[String(profile || 'v10').toLowerCase()] || ENGINE_PROFILES.v10;
      const rev = Math.max(0, Math.min(1.0, (rpm || 0) / 7800));
      const load = Math.max(0, Math.min(1.0, Math.abs(throttle || 0)));
      const fundamental = cfg.fundamental + rev * 210;
      const targetGain = 0.004 + rev * 0.032 + load * cfg.gain * 0.55;

      const now = ctx.currentTime;

      // Upshift ignition-cut bark detection: sudden RPM drop under load
      if (lastAudioRpm > 3200 && (lastAudioRpm - (rpm || 0)) > 950 && (now - lastShiftBarkTime) > 0.40) {
        lastShiftBarkTime = now;
        triggerExhaustPop(ctx, 1.25);
      }

      // Off-throttle overrun burble/crackle detection: rapid lift-off at high RPM
      if (lastAudioThrottle > 0.40 && load < 0.08 && (rpm || 0) > 3600 && (now - lastOverrunTime) > 0.70) {
        lastOverrunTime = now;
        triggerOverrunBurble(ctx);
      }

      lastAudioRpm = rpm || 0;
      lastAudioThrottle = load;

      if (!engineOscA) {
        engineGain = ctx.createGain();
        engineGain.gain.setValueAtTime(0.0001, now);

        // Pre-saturation gain
        enginePreSatGain = ctx.createGain();
        enginePreSatGain.gain.setValueAtTime(0.70, now);

        // WaveShaper soft saturation (tanh curve, 2x oversampled)
        engineWaveShaper = ctx.createWaveShaper();
        engineWaveShaper.curve = makeDistortionCurve(1.8);
        engineWaveShaper.oversample = '2x';

        // Resonant lowpass filter
        engineFilter = ctx.createBiquadFilter();
        engineFilter.type = 'lowpass';
        engineFilter.frequency.setValueAtTime(cfg.filter, now);
        engineFilter.Q.setValueAtTime(2.4, now);

        // 3 harmonic oscillators: fundamental, harmonic, sub-bass
        engineOscA = ctx.createOscillator();
        engineOscB = ctx.createOscillator();
        engineOscSub = ctx.createOscillator();
        engineOscA.type = 'sawtooth';
        engineOscB.type = 'triangle';
        engineOscSub.type = 'triangle';

        // Connect harmonic layer into preSat -> waveshaper -> filter -> engineGain
        engineOscA.connect(enginePreSatGain);
        engineOscB.connect(enginePreSatGain);
        engineOscSub.connect(enginePreSatGain);
        enginePreSatGain.connect(engineWaveShaper);
        engineWaveShaper.connect(engineFilter);
        engineFilter.connect(engineGain);

        // Throatiness LFO modulating filter cutoff
        engineFlutterOsc = ctx.createOscillator();
        engineFlutterGain = ctx.createGain();
        engineFlutterOsc.type = 'sine';
        engineFlutterOsc.frequency.setValueAtTime(10, now);
        engineFlutterGain.gain.setValueAtTime(80, now);
        engineFlutterOsc.connect(engineFlutterGain);
        engineFlutterGain.connect(engineFilter.frequency);

        // High-frequency Turbo spool oscillator
        engineTurboOsc = ctx.createOscillator();
        engineTurboGain = ctx.createGain();
        engineTurboOsc.type = 'sine';
        engineTurboOsc.frequency.setValueAtTime(1600, now);
        engineTurboGain.gain.setValueAtTime(0.0001, now);
        engineTurboOsc.connect(engineTurboGain);
        engineTurboGain.connect(engineGain);

        // Master connect to destination
        engineGain.connect(ctx.destination);

        engineOscA.start();
        engineOscB.start();
        engineOscSub.start();
        engineFlutterOsc.start();
        engineTurboOsc.start();
      }

      // Live parameter modulation on Web Audio thread (<0.02ms overhead)
      engineOscA.frequency.setTargetAtTime(fundamental, now, 0.04);
      engineOscB.frequency.setTargetAtTime(fundamental * cfg.harmonic, now, 0.04);
      engineOscSub.frequency.setTargetAtTime(fundamental * 0.5, now, 0.04);

      const filterCutoff = cfg.filter * (0.55 + rev * 0.85);
      engineFilter.frequency.setTargetAtTime(filterCutoff, now, 0.06);

      // Throatiness LFO speed and depth track revs
      engineFlutterOsc.frequency.setTargetAtTime(8 + rev * 22, now, 0.06);
      engineFlutterGain.gain.setTargetAtTime(50 + rev * 160, now, 0.06);

      // Turbo spool tracks boost and positive throttle
      const turboFreq = 1600 + rev * 3200 + load * 400;
      const turboAmp = (cfg === ENGINE_PROFILES.ev) ? 0.0 : (load * (0.003 + rev * 0.020));
      engineTurboOsc.frequency.setTargetAtTime(turboFreq, now, 0.08);
      engineTurboGain.gain.setTargetAtTime(turboAmp, now, 0.08);

      engineGain.gain.setTargetAtTime(targetGain, now, 0.06);

      if (sirenEnabled) {
        if (!sirenOsc) {
          sirenGain = ctx.createGain();
          sirenOsc = ctx.createOscillator();
          sirenLfo = ctx.createOscillator();
          const lfoGain = ctx.createGain();
          sirenOsc.type = 'square';
          sirenOsc.frequency.setValueAtTime(880, ctx.currentTime);
          sirenLfo.type = 'sine';
          sirenLfo.frequency.setValueAtTime(0.55, ctx.currentTime);
          lfoGain.gain.setValueAtTime(420, ctx.currentTime);
          sirenLfo.connect(lfoGain);
          lfoGain.connect(sirenOsc.frequency);
          sirenGain.gain.setValueAtTime(0.0001, ctx.currentTime);
          sirenOsc.connect(sirenGain);
          sirenGain.connect(ctx.destination);
          sirenOsc.start();
          sirenLfo.start();
        }
        sirenGain.gain.setTargetAtTime(0.035, ctx.currentTime, 0.15);
      } else if (sirenGain) {
        sirenGain.gain.setTargetAtTime(0.0001, ctx.currentTime, 0.1);
      }
    } catch (e) {}
  }

  function stopEngineAndSirenAudio() {
    if (!audioCtx) return;
    if (engineGain) engineGain.gain.setTargetAtTime(0.0001, audioCtx.currentTime, 0.08);
    if (sirenGain) sirenGain.gain.setTargetAtTime(0.0001, audioCtx.currentTime, 0.08);
    [engineOscA, engineOscB, engineOscSub, engineFlutterOsc, engineTurboOsc, sirenOsc, sirenLfo].forEach(function(osc) {
      if (osc) { try { osc.stop(audioCtx.currentTime + 0.25); } catch (e) {} }
    });
    engineOscA = null;
    engineOscB = null;
    engineOscSub = null;
    enginePreSatGain = null;
    engineWaveShaper = null;
    engineFilter = null;
    engineFlutterOsc = null;
    engineFlutterGain = null;
    engineTurboOsc = null;
    engineTurboGain = null;
    engineGain = null;
    sirenOsc = null;
    sirenLfo = null;
    sirenGain = null;
  }

  function updateSkidAudio(isDrifting, enabled) {
    if (!enabled || !isDrifting) {
      if (skidMasterGain && audioCtx) {
        skidMasterGain.gain.setTargetAtTime(0.0001, audioCtx.currentTime, 0.05);
      }
      return;
    }
    try {
      const ctx = ensureAudioContext();
      if (!skidMasterGain) {
        skidMasterGain = ctx.createGain();
        skidMasterGain.gain.setValueAtTime(0.0001, ctx.currentTime);
        skidMasterGain.connect(ctx.destination);

        // Abrasive asphalt scrub: looped white noise through resonant bandpass filter
        const noiseBuf = getWhiteNoiseBuffer(ctx);
        skidSource = ctx.createBufferSource();
        skidSource.buffer = noiseBuf;
        skidSource.loop = true;

        skidNoiseFilter = ctx.createBiquadFilter();
        skidNoiseFilter.type = 'bandpass';
        skidNoiseFilter.frequency.setValueAtTime(1150, ctx.currentTime);
        skidNoiseFilter.Q.setValueAtTime(1.8, ctx.currentTime);

        skidNoiseGain = ctx.createGain();
        skidNoiseGain.gain.setValueAtTime(0.07, ctx.currentTime);

        skidSource.connect(skidNoiseFilter);
        skidNoiseFilter.connect(skidNoiseGain);
        skidNoiseGain.connect(skidMasterGain);
        skidSource.start();

        // Dual detuned slip-angle squeal oscillators (760Hz & 815Hz)
        skidToneA = ctx.createOscillator();
        skidToneB = ctx.createOscillator();
        skidToneA.type = 'sawtooth';
        skidToneB.type = 'triangle';
        skidToneA.frequency.setValueAtTime(760, ctx.currentTime);
        skidToneB.frequency.setValueAtTime(815, ctx.currentTime);

        skidToneGain = ctx.createGain();
        skidToneGain.gain.setValueAtTime(0.05, ctx.currentTime);

        skidToneA.connect(skidToneGain);
        skidToneB.connect(skidToneGain);
        skidToneGain.connect(skidMasterGain);

        skidToneA.start();
        skidToneB.start();
      }
      skidMasterGain.gain.setTargetAtTime(0.12, ctx.currentTime, 0.04);
      skidNoiseGain.gain.setTargetAtTime(0.075, ctx.currentTime, 0.04);
      skidToneGain.gain.setTargetAtTime(0.055, ctx.currentTime, 0.04);
    } catch (e) {}
  }

  function stopSkidAudio() {
    if (!audioCtx) return;
    if (skidMasterGain) skidMasterGain.gain.setTargetAtTime(0.0001, audioCtx.currentTime, 0.06);
    [skidSource, skidToneA, skidToneB].forEach(function (node) {
      if (node) { try { node.stop(audioCtx.currentTime + 0.15); } catch (e) {} }
    });
    skidSource = null;
    skidNoiseFilter = null;
    skidNoiseGain = null;
    skidToneA = null;
    skidToneB = null;
    skidToneGain = null;
    skidMasterGain = null;
  }

  // ── WebGL Test Drive Mode ─────────────────────────────────────────────────
  // Drives the already-loaded Three.js scene with the Dart-side physics state,
  // keeping full PBR materials, decals and the exact wheel meshes.
  let testDriveActive = false;
  let testDriveGroup = null;
  let testDriveBodyGroup = null;
  let testDriveTrackGroup = null;
  let testDriveRoadAnchor = null;
  let testDriveWheelPivots = {};
  let testDriveModelSnapshot = null;

  function snapshotTransform(mesh) {
    return {
      mesh: mesh,
      parent: mesh.parent,
      pos: mesh.position.clone(),
      quat: mesh.quaternion.clone(),
      scale: mesh.scale.clone()
    };
  }

  function restoreTransform(item) {
    if (!item || !item.mesh) return;
    if (item.parent) {
      item.parent.attach(item.mesh);
    }
    item.mesh.position.copy(item.pos);
    item.mesh.quaternion.copy(item.quat);
    item.mesh.scale.copy(item.scale);
  }

  // ── Procedural WebGL World Parity: Sky Dome, Fog & Dynamic Track Styles ──
  let testDriveSkyDome = null;
  let testDriveEnvRT = null;
  let testDriveOrigEnv = null;
  let testDriveOrigFog = null;
  let testDriveLighting = 'sunset';
  let testDriveTrackStyle = 'circuit';

  function createAsphaltTextures() {
    const c = document.createElement('canvas');
    c.width = 512;
    c.height = 512;
    const ctx = c.getContext('2d');

    // Base dark charcoal asphalt
    ctx.fillStyle = '#1e2226';
    ctx.fillRect(0, 0, 512, 512);

    // Mineral aggregate grain
    for (let i = 0; i < 16000; i++) {
      const x = Math.random() * 512;
      const y = Math.random() * 512;
      const v = 22 + Math.floor(Math.random() * 28);
      ctx.fillStyle = `rgb(${v},${v + 2},${v + 5})`;
      ctx.fillRect(x, y, 2, 2);
    }

    // Subtle longitudinal tire-wear lanes
    const laneGradL = ctx.createLinearGradient(120, 0, 210, 0);
    laneGradL.addColorStop(0, 'rgba(10,12,14,0)');
    laneGradL.addColorStop(0.5, 'rgba(10,12,14,0.28)');
    laneGradL.addColorStop(1, 'rgba(10,12,14,0)');
    ctx.fillStyle = laneGradL;
    ctx.fillRect(120, 0, 90, 512);

    const laneGradR = ctx.createLinearGradient(302, 0, 392, 0);
    laneGradR.addColorStop(0, 'rgba(10,12,14,0)');
    laneGradR.addColorStop(0.5, 'rgba(10,12,14,0.28)');
    laneGradR.addColorStop(1, 'rgba(10,12,14,0)');
    ctx.fillStyle = laneGradR;
    ctx.fillRect(302, 0, 90, 512);

    const map = new THREE.CanvasTexture(c);
    map.wrapS = THREE.RepeatWrapping;
    map.wrapT = THREE.RepeatWrapping;
    map.repeat.set(1, 36);
    if (renderer && renderer.capabilities) {
      map.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
    }
    return map;
  }

  function createTurfTexture(lightingName) {
    const l = String(lightingName || 'sunset').toLowerCase();
    const c = document.createElement('canvas');
    c.width = 512;
    c.height = 512;
    const ctx = c.getContext('2d');

    ctx.fillStyle = l === 'day' ? '#233d27' : (l === 'night' ? '#08100b' : '#262b1b');
    ctx.fillRect(0, 0, 512, 512);

    for (let i = 0; i < 12000; i++) {
      const x = Math.random() * 512;
      const y = Math.random() * 512;
      const g = l === 'day' ? (48 + Math.random() * 34) : (l === 'night' ? (10 + Math.random() * 14) : (36 + Math.random() * 26));
      const r = l === 'sunset' ? g * 0.95 : g * 0.72;
      const b = g * 0.55;
      ctx.fillStyle = `rgb(${r|0},${g|0},${b|0})`;
      ctx.fillRect(x, y, 2, 3);
    }

    const tex = new THREE.CanvasTexture(c);
    tex.wrapS = THREE.RepeatWrapping;
    tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(90, 90);
    return tex;
  }

  function createSkyDomeMaterial(lightingName) {
    const l = String(lightingName || 'sunset').toLowerCase();
    const c = document.createElement('canvas');
    c.width = 2048;
    c.height = 1024;
    const ctx = c.getContext('2d');

    // Horizon line in equirectangular projection is at y = 512 (equator of sphere)
    const horizY = 512;

    // 1. Upper Sky Gradient (300 to horizY)
    const skyGrad = ctx.createLinearGradient(0, 300, 0, horizY);
    if (l === 'sunset') {
      // Exact stops from Solid View (Color(0xFF1E1B4B), 0xFF4C0519, 0xFF831843, 0xFFC2410C, 0xFFFDE68A)
      skyGrad.addColorStop(0.00, '#1E1B4B'); // Deep indigo dusk zenith
      skyGrad.addColorStop(0.28, '#4C0519'); // Midnight crimson
      skyGrad.addColorStop(0.52, '#831843'); // Rich magenta
      skyGrad.addColorStop(0.78, '#C2410C'); // Deep amber
      skyGrad.addColorStop(1.00, '#FDE68A'); // Glowing golden horizon
    } else if (l === 'night') {
      // Exact stops from Solid View (Color(0xFF020403), 0xFF050B08, 0xFF09140E, 0xFF0E1F16)
      skyGrad.addColorStop(0.00, '#020403'); // Pure obsidian zenith
      skyGrad.addColorStop(0.35, '#050B08');
      skyGrad.addColorStop(0.70, '#09140E');
      skyGrad.addColorStop(1.00, '#0E1F16'); // Horizon starlight rim
    } else {
      // Exact stops from Solid View (Color(0xFF0369A1), 0xFF0284C7, 0xFF38BDF8, 0xFFBAE6FD, 0xFFF1F5F9)
      skyGrad.addColorStop(0.00, '#0369A1'); // Deep azure zenith
      skyGrad.addColorStop(0.25, '#0284C7');
      skyGrad.addColorStop(0.55, '#38BDF8'); // Bright daytime sky
      skyGrad.addColorStop(0.82, '#BAE6FD'); // Atmosphere haze
      skyGrad.addColorStop(1.00, '#F1F5F9'); // Horizon line
    }
    ctx.fillStyle = skyGrad;
    ctx.fillRect(0, 0, 2048, horizY);

    // 2. Lower Ground Gradient (horizY to 1024) blending into terrain distance
    const groundGrad = ctx.createLinearGradient(0, horizY, 0, 1024);
    if (l === 'sunset') {
      groundGrad.addColorStop(0.00, '#FDE68A'); // Golden horizon match
      groundGrad.addColorStop(0.18, '#7C2D12'); // Amber ground haze
      groundGrad.addColorStop(0.40, '#262B1B'); // Dark grass boundary
      groundGrad.addColorStop(1.00, '#0F1710');
    } else if (l === 'night') {
      groundGrad.addColorStop(0.00, '#0E1F16');
      groundGrad.addColorStop(0.25, '#060A08');
      groundGrad.addColorStop(1.00, '#020403');
    } else {
      groundGrad.addColorStop(0.00, '#F1F5F9');
      groundGrad.addColorStop(0.20, '#64748B');
      groundGrad.addColorStop(0.45, '#233D27');
      groundGrad.addColorStop(1.00, '#0D1D15');
    }
    ctx.fillStyle = groundGrad;
    ctx.fillRect(0, horizY, 2048, 1024 - horizY);

    // 3. Stars for Night Mode (280 stars with natural brightness variation)
    if (l === 'night') {
      ctx.save();
      let seed = 42;
      function rnd() {
        seed = (seed * 9301 + 49297) % 233280;
        return seed / 233280;
      }
      for (let i = 0; i < 280; i++) {
        const sx = rnd() * 2048;
        const sy = rnd() * 470; // Above the horizon
        const sr = 0.6 + rnd() * 1.4;
        const alpha = 0.35 + rnd() * 0.60;
        ctx.fillStyle = `rgba(255, 255, 255, ${alpha.toFixed(2)})`;
        ctx.beginPath();
        ctx.arc(sx, sy, sr, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();
    }

    // 4. Distant Parallax Mountain Silhouettes along the Horizon (Exact Solid View Colors & 4-Harmonic Profile)
    function drawSeamlessMountainRidge(color, scale, phase) {
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.moveTo(0, horizY + 30);
      for (let x = 0; x <= 2048; x += 8) {
        const th = (x / 2048) * Math.PI * 2;
        // Integer harmonic multiples ensure the 360° panorama matches at x = 0 and x = 2048 seamlessly
        const h = (Math.abs(
          Math.sin(th * 2 + phase) * 44.0 +
          Math.sin(th * 5 + phase * 1.5) * 26.0 +
          Math.sin(th * 11 - phase) * 14.0 +
          Math.sin(th * 19) * 7.0
        ) + 24.0) * scale;
        ctx.lineTo(x, horizY - h);
      }
      ctx.lineTo(2048, horizY + 30);
      ctx.closePath();
      ctx.fill();
    }

    if (l === 'sunset') {
      // Solid View Dusk mountain range:
      // Back ridge: const Color(0x55581C87) -> rgba(88, 28, 135, 0.40)
      drawSeamlessMountainRidge('rgba(88, 28, 135, 0.40)', 1.25, 1.4);
      // Front ridge: const Color(0x803B0764) -> rgba(59, 7, 100, 0.65)
      drawSeamlessMountainRidge('rgba(59, 7, 100, 0.65)', 0.82, 0.0);
    } else if (l === 'night') {
      // Solid View Night mountain range:
      // Back ridge: const Color(0x7009100C) -> rgba(9, 16, 12, 0.44)
      drawSeamlessMountainRidge('rgba(9, 16, 12, 0.44)', 1.20, 1.4);
      // Front ridge: const Color(0xA0040705) -> rgba(4, 7, 5, 0.63)
      drawSeamlessMountainRidge('rgba(4, 7, 5, 0.63)', 0.80, 0.0);
    } else {
      // Solid View Day mountain range:
      // Back ridge: const Color(0x3064748B) -> rgba(100, 116, 139, 0.25)
      drawSeamlessMountainRidge('rgba(100, 116, 139, 0.25)', 1.25, 1.4);
      // Front ridge: const Color(0x50475569) -> rgba(71, 85, 105, 0.42)
      drawSeamlessMountainRidge('rgba(71, 85, 105, 0.42)', 0.82, 0.0);
    }

    // 5. Cumulus Cloud Wisps for Day (Exact Solid View: Color(0x24FFFFFF))
    if (l === 'day') {
      ctx.fillStyle = 'rgba(255, 255, 255, 0.14)';
      ctx.beginPath();
      ctx.ellipse(512, horizY - 78, 380, 22, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.ellipse(1536, horizY - 62, 450, 26, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    // 6. Celestial Body (Sun / Moon) with Exact Solid View Corona, Core, Disk & Flare Streaks
    if (l === 'sunset') {
      const sunX = 1024;
      const sunY = 468; // Just above the mountain line and horizon

      // Broad sunset halo: Color(0x95FFF7ED), Color(0x75F97316), Color(0x20EA580C), Color(0x00C2410C)
      const halo = ctx.createRadialGradient(sunX, sunY, 12, sunX, sunY, 170);
      halo.addColorStop(0.00, 'rgba(255, 247, 237, 0.58)');
      halo.addColorStop(0.30, 'rgba(249, 115, 22, 0.46)');
      halo.addColorStop(0.65, 'rgba(234, 88, 12, 0.13)');
      halo.addColorStop(1.00, 'rgba(194, 65, 12, 0.0)');
      ctx.fillStyle = halo;
      ctx.beginPath();
      ctx.arc(sunX, sunY, 170, 0, Math.PI * 2);
      ctx.fill();

      // Intense inner glow: Color(0xF5FFFBEB), Color(0x85F59E0B), Color(0x00F59E0B)
      const inner = ctx.createRadialGradient(sunX, sunY, 4, sunX, sunY, 65);
      inner.addColorStop(0.00, 'rgba(255, 251, 235, 0.96)');
      inner.addColorStop(0.50, 'rgba(245, 158, 11, 0.52)');
      inner.addColorStop(1.00, 'rgba(245, 158, 11, 0.0)');
      ctx.fillStyle = inner;
      ctx.beginPath();
      ctx.arc(sunX, sunY, 65, 0, Math.PI * 2);
      ctx.fill();

      // Golden sun disk: Color(0xFFFFFBEB)
      ctx.fillStyle = '#FFFBEB';
      ctx.beginPath();
      ctx.arc(sunX, sunY, 22, 0, Math.PI * 2);
      ctx.fill();

      // Horizontal golden flare streak: Color(0x55F97316)
      const streakGrad = ctx.createLinearGradient(sunX - 750, sunY, sunX + 750, sunY);
      streakGrad.addColorStop(0.0, 'rgba(249, 115, 22, 0.0)');
      streakGrad.addColorStop(0.5, 'rgba(249, 115, 22, 0.33)');
      streakGrad.addColorStop(1.0, 'rgba(249, 115, 22, 0.0)');
      ctx.fillStyle = streakGrad;
      ctx.fillRect(sunX - 750, sunY - 3, 1500, 6);

    } else if (l === 'day') {
      const sunX = 720;
      const sunY = 425;

      // Corona glow: Color(0x60FFFBEB), Color(0x28FDE047), Color(0x00FDE047)
      const corona = ctx.createRadialGradient(sunX, sunY, 10, sunX, sunY, 130);
      corona.addColorStop(0.00, 'rgba(255, 251, 235, 0.38)');
      corona.addColorStop(0.35, 'rgba(253, 224, 71, 0.16)');
      corona.addColorStop(1.00, 'rgba(253, 224, 71, 0.0)');
      ctx.fillStyle = corona;
      ctx.beginPath();
      ctx.arc(sunX, sunY, 130, 0, Math.PI * 2);
      ctx.fill();

      // Core glow: Color(0xF0FFFFFF), Color(0x80FEF08A), Color(0x00FEF08A)
      const core = ctx.createRadialGradient(sunX, sunY, 4, sunX, sunY, 50);
      core.addColorStop(0.00, 'rgba(255, 255, 255, 0.94)');
      core.addColorStop(0.50, 'rgba(254, 240, 138, 0.50)');
      core.addColorStop(1.00, 'rgba(254, 240, 138, 0.0)');
      ctx.fillStyle = core;
      ctx.beginPath();
      ctx.arc(sunX, sunY, 50, 0, Math.PI * 2);
      ctx.fill();

      // Solid sun disk
      ctx.fillStyle = '#FFFFFF';
      ctx.beginPath();
      ctx.arc(sunX, sunY, 18, 0, Math.PI * 2);
      ctx.fill();

      // Horizontal lens flare streak: Color(0x40FFFFFF)
      const streakGrad = ctx.createLinearGradient(sunX - 600, sunY, sunX + 600, sunY);
      streakGrad.addColorStop(0.0, 'rgba(255, 255, 255, 0.0)');
      streakGrad.addColorStop(0.5, 'rgba(255, 255, 255, 0.25)');
      streakGrad.addColorStop(1.0, 'rgba(255, 255, 255, 0.0)');
      ctx.fillStyle = streakGrad;
      ctx.fillRect(sunX - 600, sunY - 2, 1200, 4);

    } else {
      // Night Moon: Color(0x4560A5FA), Color(0x1538BDF8), Color(0xFFE2E8F0)
      const moonX = 1400;
      const moonY = 425;

      const moonGlow = ctx.createRadialGradient(moonX, moonY, 12, moonX, moonY, 60);
      moonGlow.addColorStop(0.00, 'rgba(96, 165, 250, 0.27)');
      moonGlow.addColorStop(0.45, 'rgba(56, 189, 248, 0.08)');
      moonGlow.addColorStop(1.00, 'rgba(0, 0, 0, 0.0)');
      ctx.fillStyle = moonGlow;
      ctx.beginPath();
      ctx.arc(moonX, moonY, 60, 0, Math.PI * 2);
      ctx.fill();

      // Moon disk
      ctx.fillStyle = '#E2E8F0';
      ctx.beginPath();
      ctx.arc(moonX, moonY, 15, 0, Math.PI * 2);
      ctx.fill();

      // Crescent shadow cutout: Color(0xFF060B08)
      ctx.fillStyle = '#060B08';
      ctx.beginPath();
      ctx.arc(moonX + 4.5, moonY - 2.5, 12.5, 0, Math.PI * 2);
      ctx.fill();
    }

    const tex = new THREE.CanvasTexture(c);
    tex.wrapS = THREE.RepeatWrapping;
    tex.encoding = THREE.sRGBEncoding;
    return new THREE.MeshBasicMaterial({
      map: tex,
      side: THREE.BackSide,
      depthWrite: false,
      fog: false
    });
  }

  function applyTestDriveAtmosphere(lightingName) {
    if (!scene) return;
    const l = String(lightingName || 'sunset').toLowerCase();

    if (testDriveSkyDome) {
      disposeObject(testDriveSkyDome);
      scene.remove(testDriveSkyDome);
      testDriveSkyDome = null;
    }

    const skyMat = createSkyDomeMaterial(l);
    testDriveSkyDome = new THREE.Mesh(new THREE.SphereGeometry(1200, 48, 24), skyMat);
    testDriveSkyDome.name = 'TestDriveSkyDome';
    scene.add(testDriveSkyDome);

    // Generate PBR environment reflection map from the sky dome for realistic car paint reflections
    if (renderer && THREE.PMREMGenerator) {
      try {
        if (testDriveEnvRT) testDriveEnvRT.dispose();
        const pmrem = new THREE.PMREMGenerator(renderer);
        const envScene = new THREE.Scene();
        envScene.add(new THREE.Mesh(new THREE.SphereGeometry(50, 24, 12), skyMat.clone()));
        testDriveEnvRT = pmrem.fromScene(envScene, 0.04);
        scene.environment = testDriveEnvRT.texture;
        pmrem.dispose();
      } catch (e) {}
    }

    if (l === 'sunset') {
      scene.background = new THREE.Color(0xc2410c);
      scene.fog = new THREE.FogExp2(0xd97736, 0.00055);
      if (hemiLight) {
        hemiLight.color.set(0xffd8a8);
        hemiLight.groundColor.set(0x2c1d18);
        hemiLight.intensity = 0.72;
      }
      if (dirLightKey) {
        dirLightKey.color.set(0xffb469);
        dirLightKey.intensity = 1.85;
      }
    } else if (l === 'night') {
      scene.background = new THREE.Color(0x03070b);
      scene.fog = new THREE.FogExp2(0x050a10, 0.0009);
      if (hemiLight) {
        hemiLight.color.set(0x475569);
        hemiLight.groundColor.set(0x060a08);
        hemiLight.intensity = 0.28;
      }
      if (dirLightKey) {
        dirLightKey.color.set(0x93c5fd);
        dirLightKey.intensity = 0.65;
      }
    } else {
      scene.background = new THREE.Color(0x38bdf8);
      scene.fog = new THREE.FogExp2(0xbbe0f8, 0.00048);
      if (hemiLight) {
        hemiLight.color.set(0xffffff);
        hemiLight.groundColor.set(0x334155);
        hemiLight.intensity = 0.85;
      }
      if (dirLightKey) {
        dirLightKey.color.set(0xfffbeb);
        dirLightKey.intensity = 1.75;
      }
    }
  }

  function buildTestDriveTrack(lightingName, trackStyleName) {
    if (testDriveTrackGroup) {
      disposeObject(testDriveTrackGroup);
      scene.remove(testDriveTrackGroup);
      testDriveTrackGroup = null;
      testDriveRoadAnchor = null;
    }

    const l = String(lightingName || testDriveLighting || 'sunset').toLowerCase();
    const t = String(trackStyleName || testDriveTrackStyle || 'circuit').toLowerCase();
    testDriveLighting = l;
    testDriveTrackStyle = t;

    if (scene && testDriveOrigFog === null) {
      testDriveOrigFog = scene.fog;
      testDriveOrigEnv = scene.environment;
    }
    applyTestDriveAtmosphere(l);

    testDriveTrackGroup = new THREE.Group();
    testDriveTrackGroup.name = 'TestDriveTrack';

    // Textured open terrain
    const turfMesh = new THREE.Mesh(
      new THREE.PlaneGeometry(2400, 2400),
      new THREE.MeshStandardMaterial({
        map: createTurfTexture(l),
        roughness: 0.98,
        metalness: 0.0,
        envMapIntensity: 0.06
      })
    );
    turfMesh.rotation.x = -Math.PI / 2;
    turfMesh.position.set(0, -0.04, 0);
    turfMesh.receiveShadow = true;
    testDriveTrackGroup.add(turfMesh);

    // Infinite 24m-snapping road anchor (NO GridHelper!)
    testDriveRoadAnchor = new THREE.Group();
    const spanLen = 720;
    const roadW = t === 'skidpad' ? 120 : (t === 'dragstrip' ? 22 : 24);

    // Gravel shoulders
    const shoulder = new THREE.Mesh(
      new THREE.PlaneGeometry(roadW + 14, spanLen),
      new THREE.MeshStandardMaterial({
        color: l === 'night' ? 0x16191d : 0x3b3a36,
        roughness: 0.96,
        metalness: 0.0,
        envMapIntensity: 0.08
      })
    );
    shoulder.rotation.x = -Math.PI / 2;
    shoulder.position.set(0, -0.025, 0);
    shoulder.receiveShadow = true;
    testDriveRoadAnchor.add(shoulder);

    // Textured PBR asphalt surface
    const road = new THREE.Mesh(
      new THREE.PlaneGeometry(roadW, spanLen),
      new THREE.MeshStandardMaterial({
        map: createAsphaltTextures(),
        color: l === 'night' ? 0x4b5563 : 0x9ca3af,
        roughness: 0.93,
        metalness: 0.0,
        envMapIntensity: 0.08
      })
    );
    road.rotation.x = -Math.PI / 2;
    road.position.set(0, -0.015, 0);
    road.receiveShadow = true;
    testDriveRoadAnchor.add(road);

    // Crisp white road boundary lines + dashed yellow center line
    const edgeX = roadW / 2 - 0.4;
    const whiteMat = new THREE.MeshBasicMaterial({ color: 0xf8fafc });
    [-edgeX, edgeX].forEach(function (lx) {
      const line = new THREE.Mesh(new THREE.PlaneGeometry(0.22, spanLen), whiteMat);
      line.rotation.x = -Math.PI / 2;
      line.position.set(lx, -0.008, 0);
      testDriveRoadAnchor.add(line);
    });

    const yellowMat = new THREE.MeshBasicMaterial({ color: 0xfbbf24 });
    for (let z = -spanLen / 2 + 6; z < spanLen / 2; z += 12) {
      const dash = new THREE.Mesh(new THREE.PlaneGeometry(0.18, 5.0), yellowMat);
      dash.rotation.x = -Math.PI / 2;
      dash.position.set(0, -0.008, z);
      testDriveRoadAnchor.add(dash);
    }

    // Alternating red/white FIA curbs + Armco guardrails + roadside streetlamps every 24m
    if (t === 'circuit') {
      const redMat = new THREE.MeshStandardMaterial({ color: 0xdc2626, roughness: 0.55 });
      const wCurbMat = new THREE.MeshStandardMaterial({ color: 0xf8fafc, roughness: 0.55 });
      const curbGeo = new THREE.BoxGeometry(1.1, 0.05, 2.8);
      for (let z = -spanLen / 2 + 1.4; z < spanLen / 2; z += 2.8) {
        const cMat = (Math.round((z + 1000) / 2.8) % 2 === 0) ? redMat : wCurbMat;
        [-roadW / 2 - 0.55, roadW / 2 + 0.55].forEach(function (cx) {
          const curb = new THREE.Mesh(curbGeo, cMat);
          curb.position.set(cx, -0.004, z);
          curb.receiveShadow = true;
          testDriveRoadAnchor.add(curb);
        });
      }

      const railMat = new THREE.MeshStandardMaterial({ color: 0x94a3b8, metalness: 0.75, roughness: 0.35 });
      [-roadW / 2 - 4.2, roadW / 2 + 4.2].forEach(function (rx) {
        const rail = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.35, spanLen), railMat);
        rail.position.set(rx, 0.55, 0);
        rail.castShadow = true;
        testDriveRoadAnchor.add(rail);
      });
    }

    const poleMat = new THREE.MeshStandardMaterial({ color: 0x334155, metalness: 0.8, roughness: 0.3 });
    const lampMat = new THREE.MeshBasicMaterial({ color: l === 'sunset' ? 0xfde68a : 0xfef9c3 });
    const poleGeo = new THREE.CylinderGeometry(0.08, 0.12, 6.2, 8);
    const armGeo = new THREE.CylinderGeometry(0.05, 0.05, 2.2, 8);
    const lampGeo = new THREE.BoxGeometry(0.35, 0.10, 0.45);
    const poleX = roadW / 2 + 4.6;
    for (let z = -spanLen / 2 + 12; z < spanLen / 2; z += 24) {
      [-poleX, poleX].forEach(function (px) {
        const s = px > 0 ? 1 : -1;
        const pole = new THREE.Mesh(poleGeo, poleMat);
        pole.position.set(px, 3.1, z);
        testDriveRoadAnchor.add(pole);
        const arm = new THREE.Mesh(armGeo, poleMat);
        arm.rotation.z = -s * Math.PI / 2.4;
        arm.position.set(px - s * 0.85, 6.0, z);
        testDriveRoadAnchor.add(arm);
        const lamp = new THREE.Mesh(lampGeo, lampMat);
        lamp.position.set(px - s * 1.7, 6.25, z);
        testDriveRoadAnchor.add(lamp);
      });
    }

    testDriveTrackGroup.add(testDriveRoadAnchor);
    scene.add(testDriveTrackGroup);
  }

  function setTestDriveWorld(lighting, trackStyle) {
    const l = lighting ? String(lighting).toLowerCase() : testDriveLighting;
    const t = trackStyle ? String(trackStyle).toLowerCase() : testDriveTrackStyle;
    const changed = (!testDriveTrackGroup || l !== testDriveLighting || t !== testDriveTrackStyle);
    testDriveLighting = l;
    testDriveTrackStyle = t;
    if (testDriveActive && changed) {
      buildTestDriveTrack(testDriveLighting, testDriveTrackStyle);
    }
  }

  // ── Procedural Under-Chassis AO Contact Shadow & Tire Contact Patches ─────
  let testDriveContactShadow = null;

  function createChassisAOMaterial() {
    const canvas = document.createElement('canvas');
    canvas.width = 256;
    canvas.height = 512;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, 256, 512);

    const cx = 128, cy = 256;
    ctx.save();
    ctx.scale(1.0, 2.0);
    const outerGrad = ctx.createRadialGradient(cx, cy / 2, 45, cx, cy / 2, 120);
    outerGrad.addColorStop(0, 'rgba(0, 0, 0, 0.78)');
    outerGrad.addColorStop(0.48, 'rgba(0, 0, 0, 0.40)');
    outerGrad.addColorStop(0.85, 'rgba(0, 0, 0, 0.12)');
    outerGrad.addColorStop(1.0, 'rgba(0, 0, 0, 0.0)');
    ctx.fillStyle = outerGrad;
    ctx.beginPath();
    ctx.arc(cx, cy / 2, 120, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    ctx.save();
    ctx.scale(0.82, 2.0);
    const coreGrad = ctx.createRadialGradient(cx / 0.82, cy / 2, 12, cx / 0.82, cy / 2, 85);
    coreGrad.addColorStop(0, 'rgba(0, 0, 0, 0.90)');
    coreGrad.addColorStop(0.65, 'rgba(0, 0, 0, 0.55)');
    coreGrad.addColorStop(1.0, 'rgba(0, 0, 0, 0.0)');
    ctx.fillStyle = coreGrad;
    ctx.beginPath();
    ctx.arc(cx / 0.82, cy / 2, 85, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    const tex = new THREE.CanvasTexture(canvas);
    return new THREE.MeshBasicMaterial({
      map: tex,
      transparent: true,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -4,
      polygonOffsetUnits: -4,
      opacity: 0.85
    });
  }

  function createTirePatchMaterial() {
    const canvas = document.createElement('canvas');
    canvas.width = 128;
    canvas.height = 128;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, 128, 128);

    const grad = ctx.createRadialGradient(64, 64, 8, 64, 64, 56);
    grad.addColorStop(0, 'rgba(0, 0, 0, 0.98)');
    grad.addColorStop(0.55, 'rgba(0, 0, 0, 0.80)');
    grad.addColorStop(0.85, 'rgba(0, 0, 0, 0.28)');
    grad.addColorStop(1.0, 'rgba(0, 0, 0, 0.0)');

    ctx.save();
    ctx.scale(0.72, 1.28);
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(64 / 0.72, 64 / 1.28, 44, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    const tex = new THREE.CanvasTexture(canvas);
    return new THREE.MeshBasicMaterial({
      map: tex,
      transparent: true,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -6,
      polygonOffsetUnits: -6,
      opacity: 0.92
    });
  }

  function buildTestDriveContactShadow(wheels) {
    const group = new THREE.Group();
    group.name = 'TestDriveContactShadow';

    let minX = -0.9, maxX = 0.9, minZ = -1.8, maxZ = 1.8;
    if (wheels && wheels.FL && wheels.FR && wheels.RL && wheels.RR) {
      minX = Math.min(wheels.FL.x, wheels.FR.x, wheels.RL.x, wheels.RR.x);
      maxX = Math.max(wheels.FL.x, wheels.FR.x, wheels.RL.x, wheels.RR.x);
      minZ = Math.min(wheels.FL.z, wheels.FR.z, wheels.RL.z, wheels.RR.z);
      maxZ = Math.max(wheels.FL.z, wheels.FR.z, wheels.RL.z, wheels.RR.z);
    }
    const carW = Math.max(1.85, (maxX - minX) + 0.38);
    const carL = Math.max(4.10, (maxZ - minZ) + 0.92);
    const centerX = (minX + maxX) / 2;
    const centerZ = (minZ + maxZ) / 2;

    // 1. Under-Chassis Ambient Occlusion contact shadow
    const chassisMat = createChassisAOMaterial();
    const chassisGeo = new THREE.PlaneGeometry(carW, carL);
    const chassisMesh = new THREE.Mesh(chassisGeo, chassisMat);
    chassisMesh.rotation.x = -Math.PI / 2;
    chassisMesh.position.set(centerX, 0.003, centerZ);
    chassisMesh.renderOrder = 5;
    group.add(chassisMesh);

    // 2. Four Tire Contact Patches at asphalt surface (y = 0.004)
    const tireMat = createTirePatchMaterial();
    const tireGeo = new THREE.PlaneGeometry(0.28, 0.44);
    const frontPatches = [];

    const cornerCoords = wheels ? {
      FL: [wheels.FL ? wheels.FL.x : -0.85, wheels.FL ? wheels.FL.z : 1.35],
      FR: [wheels.FR ? wheels.FR.x : 0.85, wheels.FR ? wheels.FR.z : 1.35],
      RL: [wheels.RL ? wheels.RL.x : -0.85, wheels.RL ? wheels.RL.z : -1.35],
      RR: [wheels.RR ? wheels.RR.x : 0.85, wheels.RR ? wheels.RR.z : -1.35]
    } : {
      FL: [-0.85, 1.35],
      FR: [0.85, 1.35],
      RL: [-0.85, -1.35],
      RR: [0.85, -1.35]
    };

    ['FL', 'FR', 'RL', 'RR'].forEach(function (corner) {
      const coord = cornerCoords[corner];
      const patch = new THREE.Mesh(tireGeo, tireMat);
      patch.rotation.x = -Math.PI / 2;
      patch.position.set(coord[0], 0.004, coord[1]);
      patch.renderOrder = 6;
      group.add(patch);
      if (corner === 'FL' || corner === 'FR') {
        frontPatches.push(patch);
      }
    });

    return {
      group: group,
      frontPatches: frontPatches
    };
  }

  // ── 3D Drift Skid Marks & Dynamic Tire Smoke Particles ─────────────────────
  let testDriveSkidPool = [];
  let testDriveSkidCursor = 0;
  let testDriveLastSkidPos = null;
  let testDriveSmokePool = [];
  let testDriveSmokeCursor = 0;

  function initTestDriveDriftFx() {
    disposeTestDriveDriftFx();
    const skidMat = new THREE.MeshBasicMaterial({
      color: 0x090b0d,
      transparent: true,
      opacity: 0.72,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -8
    });
    const skidGeo = new THREE.PlaneGeometry(0.28, 1.0);
    for (let i = 0; i < 160; i++) {
      const m = new THREE.Mesh(skidGeo, skidMat);
      m.rotation.x = -Math.PI / 2;
      m.visible = false;
      m.renderOrder = 7;
      scene.add(m);
      testDriveSkidPool.push(m);
    }

    const sc = document.createElement('canvas');
    sc.width = 64;
    sc.height = 64;
    const sctx = sc.getContext('2d');
    const sg = sctx.createRadialGradient(32, 32, 2, 32, 32, 30);
    sg.addColorStop(0, 'rgba(226, 232, 240, 0.55)');
    sg.addColorStop(0.5, 'rgba(203, 213, 225, 0.25)');
    sg.addColorStop(1, 'rgba(203, 213, 225, 0.0)');
    sctx.fillStyle = sg;
    sctx.fillRect(0, 0, 64, 64);
    const smokeTex = new THREE.CanvasTexture(sc);

    const smokeGeo = new THREE.PlaneGeometry(1.1, 1.1);
    for (let i = 0; i < 48; i++) {
      const sm = new THREE.MeshBasicMaterial({
        map: smokeTex,
        transparent: true,
        opacity: 0.0,
        depthWrite: false
      });
      const puff = new THREE.Mesh(smokeGeo, sm);
      puff.visible = false;
      puff.renderOrder = 8;
      scene.add(puff);
      testDriveSmokePool.push({ mesh: puff, life: 0, maxLife: 0.75, vx: 0, vy: 0, vz: 0 });
    }
  }

  function updateTestDriveDriftFx(state) {
    const cx = state.x || 0;
    const cz = state.z || 0;
    const yaw = state.yaw || 0;
    const sinY = Math.sin(yaw);
    const cosY = Math.cos(yaw);

    for (let i = 0; i < testDriveSmokePool.length; i++) {
      const p = testDriveSmokePool[i];
      if (!p.mesh.visible) continue;
      p.life += 0.016;
      if (p.life >= p.maxLife) {
        p.mesh.visible = false;
        continue;
      }
      const t = p.life / p.maxLife;
      p.mesh.position.x += p.vx * 0.016;
      p.mesh.position.y += p.vy * 0.016;
      p.mesh.position.z += p.vz * 0.016;
      const s = 0.7 + t * 2.2;
      p.mesh.scale.set(s, s, s);
      p.mesh.material.opacity = (1.0 - t) * 0.55;
      if (camera) p.mesh.quaternion.copy(camera.quaternion);
    }

    if (!state.isDrifting || (state.speedKmh || 0) < 6.0) {
      testDriveLastSkidPos = null;
      return;
    }

    const rearZ = 1.28;
    const halfTrack = 0.85;
    const rlX = cx - halfTrack * cosY + rearZ * sinY;
    const rlZ = cz + halfTrack * sinY + rearZ * cosY;
    const rrX = cx + halfTrack * cosY + rearZ * sinY;
    const rrZ = cz - halfTrack * sinY + rearZ * cosY;

    if (testDriveLastSkidPos) {
      const dx = cx - testDriveLastSkidPos.x;
      const dz = cz - testDriveLastSkidPos.z;
      const dist = Math.hypot(dx, dz);
      if (dist > 0.35 && dist < 8.0) {
        const segAngle = Math.atan2(dx, dz);
        [[rlX, rlZ, testDriveLastSkidPos.rlX, testDriveLastSkidPos.rlZ],
         [rrX, rrZ, testDriveLastSkidPos.rrX, testDriveLastSkidPos.rrZ]].forEach(function (pair) {
          const seg = testDriveSkidPool[testDriveSkidCursor];
          testDriveSkidCursor = (testDriveSkidCursor + 1) % testDriveSkidPool.length;
          seg.position.set((pair[0] + pair[2]) * 0.5, 0.002, (pair[1] + pair[3]) * 0.5);
          seg.rotation.set(-Math.PI / 2, 0, segAngle);
          seg.scale.set(1, Math.max(0.4, dist * 1.15), 1);
          seg.visible = true;
        });

        [[rlX, rlZ], [rrX, rrZ]].forEach(function (pt) {
          const p = testDriveSmokePool[testDriveSmokeCursor];
          testDriveSmokeCursor = (testDriveSmokeCursor + 1) % testDriveSmokePool.length;
          p.mesh.position.set(pt[0] + (Math.random() - 0.5) * 0.25, 0.22, pt[1] + (Math.random() - 0.5) * 0.25);
          p.mesh.scale.set(0.7, 0.7, 0.7);
          p.mesh.visible = true;
          p.life = 0;
          p.vx = (Math.random() - 0.5) * 0.8;
          p.vy = 0.85 + Math.random() * 0.65;
          p.vz = (Math.random() - 0.5) * 0.8;
        });
      }
    }
    testDriveLastSkidPos = { x: cx, z: cz, rlX: rlX, rlZ: rlZ, rrX: rrX, rrZ: rrZ };
  }

  function disposeTestDriveDriftFx() {
    testDriveSkidPool.forEach(function (m) {
      if (scene) scene.remove(m);
    });
    if (testDriveSkidPool.length > 0 && testDriveSkidPool[0].geometry) {
      testDriveSkidPool[0].geometry.dispose();
      testDriveSkidPool[0].material.dispose();
    }
    testDriveSkidPool = [];
    testDriveSmokePool.forEach(function (p) {
      if (scene) scene.remove(p.mesh);
      if (p.mesh.material) p.mesh.material.dispose();
    });
    if (testDriveSmokePool.length > 0 && testDriveSmokePool[0].mesh.geometry) {
      testDriveSmokePool[0].mesh.geometry.dispose();
    }
    testDriveSmokePool = [];
    testDriveLastSkidPos = null;
  }

  function enterTestDriveMode() {
    if (!scene || !currentModel || !renderer) return false;
    if (testDriveActive) return true;

    if (!detectedWheelData) {
      try {
        detectWheels({});
      } catch (e) {}
    }

    testDriveActive = true;
    try {
      highlightWheelMeshes(null);
      highlightMeshesCyan(null);
    } catch (e) {}
    if (markersGroup) markersGroup.visible = false;
    if (forwardArrowGroup) forwardArrowGroup.visible = false;
    if (gridGroup) gridGroup.visible = false;
    if (controls) controls.enabled = false;

    scene.updateMatrixWorld(true);

    testDriveGroup = new THREE.Group();
    testDriveGroup.name = 'TestDriveVehicleRoot';
    scene.add(testDriveGroup);

    testDriveBodyGroup = new THREE.Group();
    testDriveBodyGroup.name = 'TestDriveBodyGroup';
    testDriveGroup.add(testDriveBodyGroup);

    const vehicleChassis = modelPivotGroup || currentModel;
    testDriveModelSnapshot = snapshotTransform(vehicleChassis);
    testDriveBodyGroup.attach(vehicleChassis);

    // Guaranteed visible real-time shadows: enable castShadow & receiveShadow on all child meshes
    vehicleChassis.traverse(function (child) {
      if (child.isMesh) {
        child.castShadow = true;
        child.receiveShadow = true;
      }
    });

    // Procedural Under-Chassis AO Contact Shadow & 4 Tire Contact Patches
    const wheels = detectedWheelData && detectedWheelData.wheels;
    testDriveContactShadow = buildTestDriveContactShadow(wheels);
    if (testDriveContactShadow && testDriveContactShadow.group) {
      testDriveContactShadow.group.position.y = 0.003;
      testDriveGroup.add(testDriveContactShadow.group);
    }

    testDriveWheelPivots = {};
    if (wheels) {
      ['FL', 'FR', 'RL', 'RR'].forEach(function (corner) {
        const w = wheels[corner];
        if (!w) return;
        const hubWorld = new THREE.Vector3(w.x, w.y, w.z);
        const steerGroup = new THREE.Group();
        const spinGroup = new THREE.Group();
        steerGroup.position.copy(hubWorld);
        steerGroup.add(spinGroup);
        testDriveGroup.add(steerGroup);

        const origParents = [];
        const calSet = new Set(w.caliperHubMeshes || []);
        const spinList = (w.spinMeshes && w.spinMeshes.length)
          ? w.spinMeshes
          : (w.meshes || []);

        spinList.forEach(function (mesh) {
          if (!mesh || calSet.has(mesh)) return;
          origParents.push(snapshotTransform(mesh));
          spinGroup.attach(mesh);
        });
        calSet.forEach(function (mesh) {
          if (!mesh) return;
          origParents.push(snapshotTransform(mesh));
          steerGroup.attach(mesh);
        });

        testDriveWheelPivots[corner] = {
          steerGroup: steerGroup,
          spinGroup: spinGroup,
          hubPos: hubWorld,
          origParents: origParents
        };
      });
    }

    buildTestDriveTrack(testDriveLighting, testDriveTrackStyle);
    initTestDriveDriftFx();

    // Immediately snap camera to the initial vehicle chase pose and render
    // synchronously so the very first visible frame is already the WebGL test drive
    // with zero glimpse/flash of the previous workbench solid orbit view.
    if (camera) {
      camera.position.set(0, 1.82, 5.45);
      camera.lookAt(0, 0.72, -2.6);
      camera.fov = 54.0;
      camera.updateProjectionMatrix();
      if (testDriveSkyDome) {
        testDriveSkyDome.position.copy(camera.position);
      }
    }
    if (renderer && scene && camera) {
      renderer.render(scene, camera);
    }
    return true;
  }

  function updateTestDriveState(state) {
    if (!testDriveActive || !testDriveGroup || !state) return;

    // Keep testDriveGroup yaw-only so the 4 wheel steerGroups stay planted flat
    // on the asphalt (Y = 0), and apply suspension pitch & roll to testDriveBodyGroup!
    testDriveGroup.position.set(state.x || 0, state.y || 0, state.z || 0);
    testDriveGroup.rotation.set(0, state.yaw || 0, 0);
    if (testDriveBodyGroup) {
      testDriveBodyGroup.rotation.order = 'YXZ';
      testDriveBodyGroup.rotation.x = state.pitch || 0;
      testDriveBodyGroup.rotation.z = state.roll || 0;
    } else if (currentModel) {
      currentModel.rotation.order = 'YXZ';
      currentModel.rotation.x = state.pitch || 0;
      currentModel.rotation.z = state.roll || 0;
    }

    // Dynamic directional light & shadow tracking: lock frustum directly to car
    if (dirLightKey && state.x !== undefined) {
      dirLightKey.position.set(state.x + 12, (state.y || 0) + 14, state.z - 16);
      dirLightKey.target.position.set(state.x, state.y || 0, state.z);
      dirLightKey.target.updateMatrixWorld();
    }

    // Steer front tire contact patches with steering angle
    if (testDriveContactShadow && testDriveContactShadow.frontPatches) {
      const steer = state.steerAngle || 0;
      testDriveContactShadow.frontPatches.forEach(function (patch) {
        patch.rotation.z = -steer;
      });
    }

    // Infinite scrolling 3D track anchor snaps in 24m increments along car Z
    if (testDriveRoadAnchor && state.z !== undefined) {
      const snapZ = Math.round(state.z / 24) * 24;
      testDriveRoadAnchor.position.z = snapZ;
    }

    const steer = state.steerAngle || 0;
    const rearSteer = state.rearSteerAngle || 0;
    const rollRad = state.wheelRollRad || 0;
    const comps = state.compressions || [0, 0, 0, 0];

    ['FL', 'FR', 'RL', 'RR'].forEach(function (corner, idx) {
      const p = testDriveWheelPivots[corner];
      if (!p) return;
      const isFront = corner.charAt(0) === 'F';
      p.steerGroup.rotation.y = isFront ? steer : rearSteer;
      p.spinGroup.rotation.x = rollRad;
      p.steerGroup.position.set(
        p.hubPos.x,
        p.hubPos.y + (comps[idx] || 0),
        p.hubPos.z
      );
    });

    if (camera) {
      if (state.camX !== undefined) {
        camera.position.set(state.camX, state.camY, state.camZ);
        const target = new THREE.Vector3(state.targetX || 0, state.targetY || 0.8, state.targetZ || 0);
        const roll = state.camRoll || 0;
        const dir = target.clone().sub(camera.position).normalize();
        const defaultUp = new THREE.Vector3(0, 1, 0);
        const camUp = defaultUp.applyAxisAngle(dir, roll);
        camera.up.copy(camUp);
        camera.lookAt(target);
      }
      if (testDriveSkyDome) {
        testDriveSkyDome.position.copy(camera.position);
      }
      if (state.fov !== undefined && Math.abs(camera.fov - state.fov) > 0.05) {
        camera.fov = state.fov;
        camera.updateProjectionMatrix();
      }
    }
    updateTestDriveDriftFx(state);
  }

  function exitTestDriveMode() {
    if (!testDriveActive) return;
    testDriveActive = false;

    stopEngineAndSirenAudio();
    stopSkidAudio();
    disposeTestDriveDriftFx();

    Object.values(testDriveWheelPivots).forEach(function (p) {
      p.origParents.forEach(restoreTransform);
    });
    testDriveWheelPivots = {};

    const vehicleChassis = modelPivotGroup || currentModel;
    if (testDriveBodyGroup && vehicleChassis) {
      if (testDriveModelSnapshot) {
        restoreTransform(testDriveModelSnapshot);
      } else {
        scene.attach(vehicleChassis);
      }
    }
    testDriveModelSnapshot = null;
    testDriveBodyGroup = null;

    if (testDriveContactShadow) {
      disposeObject(testDriveContactShadow.group);
      if (testDriveGroup) {
        testDriveGroup.remove(testDriveContactShadow.group);
      }
      testDriveContactShadow = null;
    }

    if (testDriveEnvRT) {
      try { testDriveEnvRT.dispose(); } catch (e) {}
      testDriveEnvRT = null;
    }

    if (testDriveSkyDome) {
      scene.remove(testDriveSkyDome);
      disposeObject(testDriveSkyDome);
      testDriveSkyDome = null;
    }

    if (testDriveGroup) {
      scene.remove(testDriveGroup);
      testDriveGroup = null;
    }

    if (testDriveTrackGroup) {
      disposeObject(testDriveTrackGroup);
      scene.remove(testDriveTrackGroup);
      testDriveTrackGroup = null;
      testDriveRoadAnchor = null;
    }

    if (scene) {
      scene.fog = testDriveOrigFog;
      scene.environment = testDriveOrigEnv;
    }
    testDriveOrigFog = null;
    testDriveOrigEnv = null;

    if (dirLightKey) {
      dirLightKey.position.set(6, 9, 6);
      dirLightKey.target.position.set(0, 0, 0);
      dirLightKey.target.updateMatrixWorld();
    }

    if (camera) {
      camera.up.set(0, 1, 0);
      camera.fov = 45;
      camera.updateProjectionMatrix();
    }

    if (markersGroup) markersGroup.visible = true;
    if (forwardArrowGroup) forwardArrowGroup.visible = true;
    if (gridGroup) gridGroup.visible = true;
    if (controls) controls.enabled = true;
    resetCamera();
  }

  // Global API attached to window
  window.SketchfabViewer = {
    init: init,
    loadModel: loadModel,
    loadGlbFromArrayBuffer: function(buf, cb) {
      return loadModel(buf, 'model.glb', cb);
    },
    setRenderMode: applyRenderMode,
    setCameraPreset: setCameraPreset,
    setLighting: setLighting,
    resize: onWindowResize,
    setTurntable: setTurntable,
    resetCamera: resetCamera,
    setGridStyle: setGridStyle,
    setForwardArrowVisible: setForwardArrowVisible,
    setWheelMarkers: setWheelMarkers,
    clearWheelDataAndMarkers: clearWheelDataAndMarkers,
    detectWheels: detectWheels,
    highlightWheelMeshes: highlightWheelMeshes,
    highlightMeshesCyan: highlightMeshesCyan,
    rotateModel: rotateModel,
    flipModel: flipModel,
    snapToGround: snapToGround,
    purgeUnderWheelMeshes: purgeUnderWheelMeshesAndSnapToGround,
    applyScale: applyScale,
    loadDemoCar: loadDemoCar,
    playAudioPreview: playAudioPreview,
    stopAudioPreview: stopAudioPreview,
    updateSkidAudio: updateSkidAudio,
    stopSkidAudio: stopSkidAudio,
    updateEngineAndSirenAudio: updateEngineAndSirenAudio,
    stopEngineAndSirenAudio: stopEngineAndSirenAudio,
    enterTestDriveMode: enterTestDriveMode,
    updateTestDriveState: updateTestDriveState,
    exitTestDriveMode: exitTestDriveMode,
    setTestDriveWorld: setTestDriveWorld,
    setSketchfabTestDriveWorld: setTestDriveWorld,
    isTestDriveActive: function() { return testDriveActive; },
    isInitialized: function() { return isInitialized; }
  };
})();
