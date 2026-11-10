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

    controls.domElement.addEventListener('pointerdown', () => {
      renderer.domElement.style.cursor = 'grabbing';
    });
    controls.domElement.addEventListener('pointerup', () => {
      renderer.domElement.style.cursor = 'grab';
    });

    // 5. Lighting Rig (Sketchfab Studio 3-Point PBR Lighting)
    hemiLight = new THREE.HemisphereLight(0xffffff, 0x18241d, 1.0);
    hemiLight.position.set(0, 20, 0);
    scene.add(hemiLight);

    dirLightKey = new THREE.DirectionalLight(0xffffff, 1.6);
    dirLightKey.position.set(6, 9, 6);
    dirLightKey.castShadow = true;
    dirLightKey.shadow.mapSize.width = 2048;
    dirLightKey.shadow.mapSize.height = 2048;
    dirLightKey.shadow.camera.near = 0.5;
    dirLightKey.shadow.camera.far = 60;
    dirLightKey.shadow.camera.left = -8;
    dirLightKey.shadow.camera.right = 8;
    dirLightKey.shadow.camera.top = 8;
    dirLightKey.shadow.camera.bottom = -8;
    dirLightKey.shadow.bias = -0.0002;
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
    if (controls) controls.update();
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
      6, 8, 10,  6, 10, 12, 3, 12, 14, 1, 7, 5,
      1, 2, 7,   7, 11, 9,  7, 13, 11, 2, 15, 13,
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

  function snapToGround() {
    if (!modelPivotGroup || !currentModel) return;
    modelPivotGroup.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(modelPivotGroup);
    const minY = box.min.y;
    currentModel.position.y -= minY;
    modelPivotGroup.updateMatrixWorld(true);
    if (wireframeOverlayGroup) {
      applyRenderMode(currentRenderMode);
    }
    console.log('SketchfabViewer: Snapped model to ground Y = 0.0m (adjusted by', -minY, ')');
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
          (diameter >= 0.08 * carLength && diameter <= 0.38 * carLength) &&
          (circularity >= (namedWheel ? 0.60 : 0.75)) &&
          (center.y < groundY + 0.35 * carHeight) &&
          (Math.abs(center[lAxis] - carCenter[lAxis]) > 0.25 * carWidth)
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
          if (dist2D <= maxSpinAxisDist) {
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
      const tireWidth = coreWheelBox.max[lAxis] - coreWheelBox.min[lAxis];
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
      const inboardAllowance = Math.max(0.45 * tireWidth, 0.06 * carWidth);

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

    return detectedWheelData;
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
          child.material = new THREE.MeshStandardMaterial({
            color: 0x10b981,
            emissive: 0x059669,
            emissiveIntensity: 0.5,
            roughness: 0.2,
            metalness: 0.8
          });
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
          child.material = new THREE.MeshStandardMaterial({
            color: 0x00e5ff,
            emissive: 0x008ba3,
            emissiveIntensity: 0.7,
            roughness: 0.2,
            metalness: 0.8
          });
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
          if (m.map) m.map.dispose();
          m.dispose();
        });
      }
    });
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
    applyScale: applyScale,
    loadDemoCar: loadDemoCar,
    isInitialized: function() { return isInitialized; }
  };
})();
