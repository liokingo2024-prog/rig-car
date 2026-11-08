/**
 * Sketchfab-grade WebGL 3D Viewer for RIG-CAR
 * Powered by Three.js with full PBR textures, environment lighting,
 * and 60 FPS hardware acceleration.
 */
(function() {
  'use strict';

  let renderer, scene, camera, controls;
  let currentModel = null;
  let groundGrid = null;
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

  function init(container) {
    if (isInitialized && containerEl === container) return;
    containerEl = container;

    const width = container.clientWidth || 800;
    const height = container.clientHeight || 500;

    // 1. Scene
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x090D0B);

    // 2. Camera
    camera = new THREE.PerspectiveCamera(45, width / height, 0.05, 1000);
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

    // 4. OrbitControls
    controls = new THREE.OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.05;
    controls.screenSpacePanning = true;
    controls.maxPolarAngle = Math.PI * 0.92;
    controls.minDistance = 0.4;
    controls.maxDistance = 100.0;
    controls.target.set(0, 0.6, 0);

    // 5. Lighting Rig (Sketchfab Studio 3-Point PBR Lighting)
    hemiLight = new THREE.HemisphereLight(0xffffff, 0x18241d, 0.85);
    hemiLight.position.set(0, 20, 0);
    scene.add(hemiLight);

    dirLightKey = new THREE.DirectionalLight(0xffffff, 1.4);
    dirLightKey.position.set(6, 9, 6);
    dirLightKey.castShadow = true;
    dirLightKey.shadow.mapSize.width = 2048;
    dirLightKey.shadow.mapSize.height = 2048;
    dirLightKey.shadow.camera.near = 0.5;
    dirLightKey.shadow.camera.far = 40;
    dirLightKey.shadow.camera.left = -6;
    dirLightKey.shadow.camera.right = 6;
    dirLightKey.shadow.camera.top = 6;
    dirLightKey.shadow.camera.bottom = -6;
    dirLightKey.shadow.bias = -0.0002;
    scene.add(dirLightKey);

    dirLightFill = new THREE.DirectionalLight(0xaad8e6, 0.65);
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
  }

  function createGround(sc) {
    if (groundGrid) sc.remove(groundGrid);
    if (groundShadow) sc.remove(groundShadow);

    // Dark CAD Ground Grid
    groundGrid = new THREE.GridHelper(30, 60, 0x10b981, 0x1b2820);
    groundGrid.position.y = -0.001;
    sc.add(groundGrid);

    // Soft Radial Contact Shadow Plane
    const shadowCanvas = document.createElement('canvas');
    shadowCanvas.width = 256;
    shadowCanvas.height = 256;
    const ctx = shadowCanvas.getContext('2d');
    const grad = ctx.createRadialGradient(128, 128, 20, 128, 128, 120);
    grad.addColorStop(0, 'rgba(0, 0, 0, 0.7)');
    grad.addColorStop(0.5, 'rgba(0, 0, 0, 0.3)');
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
    groundShadow.position.y = 0.001;
    sc.add(groundShadow);
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

  function loadGlbFromArrayBuffer(arrayBuffer, callback) {
    if (!scene) return;
    const loader = new THREE.GLTFLoader();

    loader.parse(
      arrayBuffer,
      '',
      function(gltf) {
        if (currentModel) {
          scene.remove(currentModel);
          disposeObject(currentModel);
          currentModel = null;
        }
        originalMaterials.clear();

        const model = gltf.scene || gltf.scenes[0];
        currentModel = model;

        // Process materials and textures
        model.traverse(function(child) {
          if (child.isMesh) {
            child.castShadow = true;
            child.receiveShadow = true;

            if (child.material) {
              const mats = Array.isArray(child.material) ? child.material : [child.material];
              mats.forEach(mat => {
                originalMaterials.set(mat.uuid, mat.clone());
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
                if (isGlass || mat.transparent || mat.opacity < 1.0) {
                  mat.transparent = true;
                  mat.depthWrite = true;
                  mat.side = THREE.DoubleSide;
                  if (mat.opacity >= 1.0) mat.opacity = 0.55;
                } else {
                  // Double-sided for thin aero panels (spoilers, wings, diffusers)
                  mat.side = THREE.DoubleSide;
                }
              });
            }
          }
        });

        // Compute BBox and center
        const box = new THREE.Box3().setFromObject(model);
        modelBBox = box;
        const size = box.getSize(new THREE.Vector3());
        const center = box.getCenter(new THREE.Vector3());

        // Center on floor (y=0)
        model.position.x = -center.x;
        model.position.y = -box.min.y;
        model.position.z = -center.z;

        modelRadius = Math.max(size.x, Math.max(size.y, size.z)) * 0.5;
        modelCenter = new THREE.Vector3(0, size.y * 0.5, 0);

        // Adjust shadow plane to vehicle size
        if (groundShadow) {
          groundShadow.scale.set(size.x * 0.35, size.z * 0.35, 1);
          groundShadow.position.set(0, 0.001, 0);
        }

        scene.add(model);

        // Fit camera to vehicle
        resetCamera();

        // Apply current render mode
        applyRenderMode(currentRenderMode);

        if (callback) callback({ success: true, size: size, center: center });
      },
      function(error) {
        console.error('Error parsing GLB in WebGL viewer:', error);
        if (callback) callback({ success: false, error: error });
      }
    );
  }

  function resetCamera() {
    if (!camera || !controls) return;
    const dist = modelRadius * 2.8;
    camera.position.set(dist * 0.8, dist * 0.45, dist * 0.85);
    controls.target.copy(modelCenter || new THREE.Vector3(0, 0.7, 0));
    camera.near = Math.max(0.01, dist * 0.01);
    camera.far = Math.max(100, dist * 20);
    camera.updateProjectionMatrix();
    controls.update();
  }

  function setCameraPreset(preset) {
    if (!camera || !controls) return;
    const dist = modelRadius * 2.8;
    const cy = modelCenter ? modelCenter.y : 0.7;

    switch (preset.toLowerCase()) {
      case 'iso':
        camera.position.set(dist * 0.8, dist * 0.45, dist * 0.85);
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
      // Add subtle wireframe lines over the textured solid model
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
        hemiLight.intensity = 0.85;
        dirLightKey.color.set(0xffffff);
        dirLightKey.intensity = 1.4;
        dirLightFill.intensity = 0.65;
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

  function setGridStyle(style) {
    if (!groundGrid) return;
    if (style === 'off') {
      groundGrid.visible = false;
    } else {
      groundGrid.visible = true;
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
      const markerGeo = new THREE.CylinderGeometry(0.08, 0.08, 0.22, 16);
      const markerMat = new THREE.MeshBasicMaterial({ color: 0x34d399 });
      const marker = new THREE.Mesh(markerGeo, markerMat);
      marker.position.set(w.x, w.y, w.z);
      markersGroup.add(marker);
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
    loadGlbFromArrayBuffer: loadGlbFromArrayBuffer,
    setRenderMode: applyRenderMode,
    setCameraPreset: setCameraPreset,
    setLighting: setLighting,
    setTurntable: setTurntable,
    resetCamera: resetCamera,
    setGridStyle: setGridStyle,
    setWheelMarkers: setWheelMarkers,
    isInitialized: function() { return isInitialized; }
  };
})();
