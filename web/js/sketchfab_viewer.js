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
    scene.background = new THREE.Color(0x090D0B);

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

    // 10. Load any pending buffer
    if (pendingModelBuffer) {
      const p = pendingModelBuffer;
      pendingModelBuffer = null;
      loadModel(p.buffer, p.fileName, p.callback);
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

    if (groundShadow) sc.remove(groundShadow);

    // Soft Radial Contact Shadow Plane
    const shadowCanvas = document.createElement('canvas');
    shadowCanvas.width = 256;
    shadowCanvas.height = 256;
    const ctx = shadowCanvas.getContext('2d');
    const grad = ctx.createRadialGradient(128, 128, 20, 128, 128, 120);
    grad.addColorStop(0, 'rgba(0, 0, 0, 0.75)');
    grad.addColorStop(0.5, 'rgba(0, 0, 0, 0.35)');
    grad.addColorStop(1, 'rgba(0, 0, 0, 0)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 256, 256);

    const shadowTex = new THREE.CanvasTexture(shadowCanvas);
    const shadowGeo = new THREE.PlaneGeometry(8, 8);
    const shadowMat = new THREE.MeshBasicMaterial({
      map: shadowTex,
      transparent: true,
      depthWrite: false,
      opacity: 0.85
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

  /**
   * Unified Post-Processing Pipeline for all loaded models.
   */
  function applyLoadedModel(model, callback) {
    if (!scene) return;
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
      groundShadow.scale.set(Math.max(size.x * 0.7, 4), Math.max(size.z * 0.7, 4), 1);
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
  }

  function setCameraPreset(preset) {
    if (!camera || !controls) return;
    const dist = Math.max(modelRadius * 2.6, 2.5);
    const cy = modelCenter ? modelCenter.y : 0.7;

    switch (preset.toLowerCase()) {
      case 'iso':
        camera.position.set(dist * 0.85, dist * 0.45, dist * 0.85);
        break;
      case 'front':
        camera.position.set(0, cy, -dist);
        break;
      case 'back':
        camera.position.set(0, cy, dist);
        break;
      case 'left':
        camera.position.set(-dist, cy, 0);
        break;
      case 'right':
        camera.position.set(dist, cy, 0);
        break;
      case 'top':
        camera.position.set(0, dist * 1.5, 0.001);
        break;
      case 'bottom':
        camera.position.set(0, -dist * 1.5, 0.001);
        break;
    }
    controls.target.set(0, cy, 0);
    camera.updateProjectionMatrix();
    controls.update();
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
        scene.background.set(0x090D0B);
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

  function buildCadGrid() {
    const grp = new THREE.Group();
    // 30m x 30m CAD grid with 60 subdivisions (0.5m spacing)
    const grid = new THREE.GridHelper(30, 60, 0x10b981, 0x182c22);
    grid.position.y = 0.0004;
    if (grid.material) {
      grid.material.transparent = true;
      grid.material.opacity = 0.75;
      grid.material.depthWrite = false;
    }
    grp.add(grid);

    // Outer boundary frame
    const hw = 15;
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
    if (!wheels || !Array.isArray(wheels)) return;

    wheels.forEach(w => {
      if (!w || typeof w.x !== 'number') return;
      // Glowing emerald cylindrical hub marker
      const markerGeo = new THREE.CylinderGeometry(0.10, 0.10, 0.24, 20);
      markerGeo.rotateZ(Math.PI / 2);
      const markerMat = new THREE.MeshStandardMaterial({
        color: 0x10b981,
        emissive: 0x059669,
        emissiveIntensity: 0.7,
        roughness: 0.2,
        metalness: 0.8
      });
      const marker = new THREE.Mesh(markerGeo, markerMat);
      marker.position.set(w.x, w.y, w.z);
      markersGroup.add(marker);

      // Outer glowing ring
      const ringGeo = new THREE.TorusGeometry(0.22, 0.02, 16, 32);
      ringGeo.rotateY(Math.PI / 2);
      const ringMat = new THREE.MeshBasicMaterial({ color: 0x34d399 });
      const ring = new THREE.Mesh(ringGeo, ringMat);
      ring.position.set(w.x, w.y, w.z);
      markersGroup.add(ring);
    });
  }

  function highlightWheelMeshes(wheelNodeNames) {
    if (!currentModel) return;
    const names = Array.isArray(wheelNodeNames) && wheelNodeNames.length > 0
      ? wheelNodeNames.map(n => (n || '').toLowerCase())
      : ['wheel', 'tire', 'tyre', 'rim'];
    currentModel.traverse(function(child) {
      if (child.isMesh) {
        const cName = (child.name || '').toLowerCase();
        const isWheel = names.some(n => cName.includes(n));
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
    setWheelMarkers: setWheelMarkers,
    highlightWheelMeshes: highlightWheelMeshes,
    rotateModel: rotateModel,
    flipModel: flipModel,
    snapToGround: snapToGround,
    applyScale: applyScale,
    isInitialized: function() { return isInitialized; }
  };
})();
