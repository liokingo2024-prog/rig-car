import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rig_car/auto_detector.dart';
import 'package:rig_car/glb_parser.dart';
import 'package:rig_car/main.dart';
import 'package:rig_car/model_data.dart';
import 'package:rig_car/physics_sim.dart';
import 'package:rig_car/pre_rigged_cars.dart';
import 'package:rig_car/solid_mesh_lod.dart';
import 'package:rig_car/wireframe_viewer.dart';

void main() {
  group('3D Math & Matrix', () {
    test('Vec3 operations', () {
      const a = Vec3(1, 2, 3);
      const b = Vec3(4, 5, 6);
      expect((a + b).x, 5);
      expect((b - a).y, 3);
      expect(a.dot(b), 32);
      expect(a.cross(b).z, -3);
    });

    test('Mat4 lookAt & perspective transform', () {
      const eye = Vec3(0, 0, 5);
      const target = Vec3.zero;
      final view = Mat4.lookAt(eye, target, const Vec3(0, 1, 0));
      final proj = Mat4.perspective(1.0, 1.0, 0.1, 100.0);
      final vp = proj * view;

      const p = Vec3(0, 0, 0);
      final clip = vp.transformClip(p);
      expect(clip[3] > 0, isTrue); // In front of camera
    });

    test('normalizes imported vehicle units and origin', () {
      final mesh = MeshData(
        index: 0,
        name: 'CarMesh',
        vertices: const [Vec3(-100, 20, -200), Vec3(100, 120, 200)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-100, 20, -200), Vec3(100, 120, 200)),
      );
      final model = ParsedModel(
        fileName: 'millimeter_car.glb',
        nodes: [
          SceneNode(
            index: 0,
            name: 'Car_Body',
            localTransform: Mat4.identity(),
            meshIndex: 0,
            childIndices: const [],
            parentIndex: null,
            worldTransform: Mat4.identity(),
          ),
        ],
        meshes: [mesh],
        instances: [
          MeshInstance(
            nodeIndex: 0,
            meshIndex: 0,
            worldVertices: mesh.vertices,
            edges: mesh.edges,
            worldBBox: mesh.bbox,
          ),
        ],
        rootNodeIndices: const [0],
        worldBBox: mesh.bbox,
      );

      final normalized = model.normalizedForRigging();
      expect(
        max(
          normalized.worldBBox.size.x.abs(),
          normalized.worldBBox.size.z.abs(),
        ),
        closeTo(4.2, 1e-9),
      );
      expect(normalized.worldBBox.center.x, closeTo(0, 1e-9));
      expect(normalized.worldBBox.center.z, closeTo(0, 1e-9));
      expect(normalized.worldBBox.lo.y, closeTo(0, 1e-9));
    });
  });

  group('AutoDetector Heuristics', () {
    test('Detects wheels by naming convention', () {
      final nodes = [
        SceneNode(
          index: 0,
          name: 'Root',
          localTransform: Mat4.identity(),
          meshIndex: null,
          childIndices: [1, 2, 3, 4, 5],
          parentIndex: null,
        ),
        SceneNode(
          index: 1,
          name: 'Car_Body',
          localTransform: Mat4.identity(),
          meshIndex: 0,
          childIndices: [],
          parentIndex: 0,
        ),
        SceneNode(
          index: 2,
          name: 'Wheel_FL',
          localTransform: Mat4.fromTRS(
            const Vec3(-0.8, 0.3, -1.2),
            Quat.identity,
            Vec3.one,
          ),
          meshIndex: 1,
          childIndices: [],
          parentIndex: 0,
        ),
        SceneNode(
          index: 3,
          name: 'Wheel_FR',
          localTransform: Mat4.fromTRS(
            const Vec3(0.8, 0.3, -1.2),
            Quat.identity,
            Vec3.one,
          ),
          meshIndex: 1,
          childIndices: [],
          parentIndex: 0,
        ),
        SceneNode(
          index: 4,
          name: 'Wheel_RL',
          localTransform: Mat4.fromTRS(
            const Vec3(-0.8, 0.3, 1.2),
            Quat.identity,
            Vec3.one,
          ),
          meshIndex: 1,
          childIndices: [],
          parentIndex: 0,
        ),
        SceneNode(
          index: 5,
          name: 'Wheel_RR',
          localTransform: Mat4.fromTRS(
            const Vec3(0.8, 0.3, 1.2),
            Quat.identity,
            Vec3.one,
          ),
          meshIndex: 1,
          childIndices: [],
          parentIndex: 0,
        ),
      ];

      for (final n in nodes) {
        n.worldTransform = n.localTransform;
      }

      final bodyMesh = MeshData(
        index: 0,
        name: 'BodyMesh',
        vertices: const [Vec3(-1, 0, -2), Vec3(1, 1.5, 2)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-1, 0, -2), Vec3(1, 1.5, 2)),
      );

      final wheelMesh = MeshData(
        index: 1,
        name: 'WheelMesh',
        vertices: const [Vec3(-0.2, -0.3, -0.2), Vec3(0.2, 0.3, 0.2)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.2, -0.3, -0.2), Vec3(0.2, 0.3, 0.2)),
      );

      final model = ParsedModel(
        fileName: 'test_car.glb',
        nodes: nodes,
        meshes: [bodyMesh, wheelMesh],
        instances: [
          MeshInstance(
            nodeIndex: 1,
            meshIndex: 0,
            worldVertices: bodyMesh.vertices,
            edges: bodyMesh.edges,
            worldBBox: bodyMesh.bbox,
          ),
        ],
        rootNodeIndices: [0],
        worldBBox: const BBox(Vec3(-1, 0, -2), Vec3(1, 1.5, 2)),
      );

      final result = AutoDetector.detect(model);
      expect(result.wheels.length, 4);
      expect(result.wheels.any((w) => w.nodeName == 'Wheel_FL'), isTrue);
      expect(result.wheels.any((w) => w.nodeName == 'Wheel_RR'), isTrue);
      expect(result.body?.nodeName, 'Car_Body');
    });

    test('Merges tire and rim parts into four wheel assemblies', () {
      final wheelPositions = const [
        Vec3(-0.8, 0.3, -1.2),
        Vec3(0.8, 0.3, -1.2),
        Vec3(-0.8, 0.3, 1.2),
        Vec3(0.8, 0.3, 1.2),
      ];
      final nodes = <SceneNode>[
        SceneNode(
          index: 0,
          name: 'Root',
          localTransform: Mat4.identity(),
          meshIndex: null,
          childIndices: [1, for (var i = 0; i < 8; i++) i + 2],
          parentIndex: null,
        ),
        SceneNode(
          index: 1,
          name: 'Car_Body',
          localTransform: Mat4.identity(),
          meshIndex: 0,
          childIndices: [],
          parentIndex: 0,
        ),
      ];
      final instances = <MeshInstance>[];
      final bodyMesh = MeshData(
        index: 0,
        name: 'BodyMesh',
        vertices: const [Vec3(-1, 0, -2), Vec3(1, 1.5, 2)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-1, 0, -2), Vec3(1, 1.5, 2)),
      );
      final wheelMesh = MeshData(
        index: 1,
        name: 'WheelPartMesh',
        vertices: const [Vec3(-0.15, -0.35, -0.35), Vec3(0.15, 0.35, 0.35)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.15, -0.35, -0.35), Vec3(0.15, 0.35, 0.35)),
      );
      instances.add(
        MeshInstance(
          nodeIndex: 1,
          meshIndex: 0,
          worldVertices: bodyMesh.vertices,
          edges: bodyMesh.edges,
          worldBBox: bodyMesh.bbox,
        ),
      );

      var nodeIndex = 2;
      for (var wheel = 0; wheel < wheelPositions.length; wheel++) {
        for (final part in ['Tire', 'Rim']) {
          final position = wheelPositions[wheel];
          final node = SceneNode(
            index: nodeIndex,
            name: 'Wheel_${wheel}_$part',
            localTransform: Mat4.fromTRS(position, Quat.identity, Vec3.one),
            meshIndex: 1,
            childIndices: [],
            parentIndex: 0,
          );
          nodes.add(node);
          instances.add(
            MeshInstance(
              nodeIndex: nodeIndex,
              meshIndex: 1,
              worldVertices: wheelMesh.vertices
                  .map(node.localTransform.transformPoint)
                  .toList(),
              edges: wheelMesh.edges,
              worldBBox: BBox.fromPoints(
                wheelMesh.vertices
                    .map(node.localTransform.transformPoint)
                    .toList(),
              ),
            ),
          );
          nodeIndex++;
        }
      }

      final result = AutoDetector.detect(
        ParsedModel(
          fileName: 'multi_part_car.glb',
          nodes: nodes,
          meshes: [bodyMesh, wheelMesh],
          instances: instances,
          rootNodeIndices: [0],
          worldBBox: const BBox(Vec3(-1, 0, -2), Vec3(1, 1.5, 2)),
        ),
      );

      expect(result.wheels.length, 4);
      expect(result.wheels.every((wheel) => wheel.partCount == 2), isTrue);
      expect(result.body?.nodeName, 'Car_Body');
    });

    test('RigConfig exports real wheel coordinates', () {
      const config = RigConfig(
        modelName: 'race_car.glb',
        presetName: 'Sports coupe',
        drive: 'RWD',
        mass: 1100,
        engineForce: 500,
        grip: 1.2,
        suspension: 6.5,
        centerOfMass: -0.2,
        frontSteering: true,
        rearSteering: false,
        frontTraction: false,
        rearTraction: true,
        wheelPositions: [
          Vec3(-0.82, 0.31, -1.38),
          Vec3(0.82, 0.31, -1.38),
          Vec3(-0.84, 0.31, 1.42),
          Vec3(0.84, 0.31, 1.42),
        ],
      );

      final tscn = config.toTscn();
      expect(tscn.contains('Wheel_FL'), isTrue);
      expect(tscn.contains('-0.820'), isTrue);
      expect(tscn.contains('-1.380'), isTrue);

      final json = config.toJson();
      expect(json['model'], 'race_car.glb');
    });

    test('PreRiggedCar exports valid Godot config', () {
      final car = preRiggedCars.first;
      final config = car.toRigConfig();
      expect(config.modelName, 'Apex GT Coupe.glb');
      expect(config.wheelPositions?.length, 4);
      expect(config.toTscn().contains('VehicleBody3D'), isTrue);
    });
  });

  group('Fleet Library Home Screen', () {
    testWidgets('renders fleet library home screen with cards', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RigCarApp());

      expect(find.text('RIG-CAR'), findsWidgets);
      expect(find.text('PRE-RIGGED VEHICLE FLEET'), findsOneWidget);
      expect(find.text('Apex GT Coupe'), findsOneWidget);
      expect(find.text('Vanguard 4x4 Trail'), findsOneWidget);
      expect(find.text('Rig Your Car'), findsWidgets);
    });

    testWidgets('navigates from home screen to workbench via "Rig Your Car"', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RigCarApp());
      await tester.pump(const Duration(milliseconds: 100));

      // Tap top Rig Your Car button
      await tester.tap(find.text('Rig Your Car').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('CAR RIGGER'), findsOneWidget);
      expect(find.text('Mixamo-Style Auto-Rig'), findsNothing);

      // Back button exists on nav and navigates back
      expect(find.byTooltip('Back to Fleet Library'), findsOneWidget);
    });
  });

  group('UI Workbench Flow', () {
    testWidgets('renders workbench shell and 3D wireframe viewer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('RIG-CAR'), findsWidgets);
      expect(find.text('CAR RIGGER'), findsOneWidget);
      // Car name label and right sidepanel content are removed as requested
      expect(find.text('Procedural 3D Rig'), findsNothing);
      expect(find.text('Mixamo-Style Auto-Rig'), findsNothing);
      expect(find.byTooltip('Auto-rig vehicle'), findsOneWidget);
      expect(find.text('ISO'), findsOneWidget);
      expect(find.byTooltip('Viewport lighting: Studio'), findsOneWidget);
      expect(find.byTooltip('Fullscreen Viewport'), findsOneWidget);

      // Open camera angle dropdown and switch to Rear view
      await tester.tap(find.text('ISO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rear View (+Z)').last);
      await tester.pumpAndSettle();
      expect(find.text('BACK'), findsOneWidget);
    });

    testWidgets('renders 5-step master-detail pipeline in workbench with dynamic detail inspector', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Left sidebar renders exactly 5 pipeline step cards
      expect(find.text('RIGGING PIPELINE'), findsOneWidget);
      expect(find.text('Upload Vehicle'), findsWidgets);
      expect(find.text('Scan & Organize'), findsWidgets);
      expect(find.text('Add Physics'), findsWidgets);
      expect(find.text('Add Sound'), findsWidgets);
      expect(find.text('Export Rig'), findsWidgets);

      // Subtitles
      expect(find.text('Import 3D model (.glb, .gltf)'), findsWidgets);
      expect(find.text('Loose parts, 4-wheel match & hubs'), findsWidgets);
      expect(find.text('Mass, suspension & tire grip'), findsWidgets);
      expect(find.text('Engine RPM, skid & siren audio'), findsWidgets);
      expect(find.text('Package Godot 4 vehicle scene'), findsWidgets);

      // Right inspector fixed header and Step 1 view
      expect(find.text('✨ Auto'), findsOneWidget);
      expect(find.text('🛠 Custom'), findsOneWidget);
      expect(find.text('PROGRESS & BOUNDS VERIFICATION'), findsOneWidget);
      expect(find.text('Model Parsed'), findsOneWidget);
      expect(find.text('Bounding Box'), findsOneWidget);
      expect(find.text('Ground Plane Snap'), findsOneWidget);
      expect(find.text('Forward Axis'), findsOneWidget);

      // Tap Step 2: Scan & Organize
      await tester.tap(find.text('Scan & Organize').first);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('4-STAGE AUTO-RIG PIPELINE'), findsOneWidget);
      expect(find.text('1. Separate Loose Parts'), findsOneWidget);
      expect(find.text('2. Similarity Match (2s & 4s)'), findsOneWidget);
      expect(find.text('3. Lower-Corner & Height Filter'), findsOneWidget);
      expect(find.text('4. Hub Center & Radius Math'), findsOneWidget);
      expect(find.text('Approve Auto Rig'), findsOneWidget);

      // Switch to Custom
      await tester.tap(find.text('🛠 Custom'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('A. DETECTED 2/4 GROUP CHECKLIST'), findsOneWidget);
      expect(find.text('B. HEIGHT & CORNER FILTER OVERRIDE'), findsOneWidget);
      expect(find.text('C. 4-CORNER MANUAL SLOT PICKER'), findsOneWidget);
      expect(find.text('D. ONE-CLICK SYMMETRY & PIVOT REPAIR'), findsOneWidget);
      expect(find.text('Mirror Left → Right Hubs'), findsOneWidget);

      // Tap Step 3: Add Physics
      await tester.tap(find.text('Add Physics').first);
      await tester.pump(const Duration(milliseconds: 100));

      // Switch back to Auto
      await tester.tap(find.text('✨ Auto'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('HANDLING PRESETS'), findsOneWidget);
      expect(find.text('Sport / Interceptor'), findsOneWidget);
      expect(find.text('Arcade Drift'), findsOneWidget);
      expect(find.text('Off-Road SUV'), findsOneWidget);
      expect(find.text('Heavy Utility'), findsOneWidget);
      expect(find.text('CALCULATED SUMMARY'), findsOneWidget);

      // Tap Step 4: Add Sound
      await tester.tap(find.text('Add Sound').first);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('ACOUSTIC PROFILES'), findsOneWidget);
      expect(find.text('V10 Supercar'), findsOneWidget);
      expect(find.text('V8 Muscle'), findsOneWidget);
      expect(find.text('ACCESSORY AUDIO LAYERS'), findsOneWidget);

      // Tap Step 5: Export Rig
      await tester.tap(find.text('Export Rig').first);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PRE-FLIGHT READINESS CHECKLIST'), findsOneWidget);
      expect(find.text('Scale & Axis Valid'), findsOneWidget);
      expect(find.text('GODOT 4 ARCHITECTURE'), findsOneWidget);
      expect(find.text('Export Godot 4 Rig (.glb / .tscn)'), findsOneWidget);
    });

    testWidgets('interacts with all 5 inspector steps, toggles auto and manual modes, and verifies controls', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Step 1: Switch to Custom
      await tester.tap(find.text('🛠 Custom'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('ORIENTATION QUICK-FIX'), findsOneWidget);
      expect(find.text('Rotate +90° Yaw'), findsOneWidget);
      expect(find.text('Flip Front/Back'), findsOneWidget);
      expect(find.text('Snap to Ground (Y = 0.0m)'), findsOneWidget);
      expect(find.text('Apply Scale'), findsOneWidget);
      expect(find.text('Exclude roof/antenna parts from chassis bounds'), findsOneWidget);

      // Tap orientation buttons
      await tester.tap(find.text('Rotate +90° Yaw'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Flip Front/Back'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Snap to Ground (Y = 0.0m)'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Apply Scale'));
      await tester.pump(const Duration(milliseconds: 50));

      // Step 2: Scan & Organize
      await tester.tap(find.text('Scan & Organize').first);
      await tester.pump(const Duration(milliseconds: 100));

      // In Custom view
      expect(find.text('Mirror Left → Right Hubs'), findsOneWidget);
      expect(find.text('Recenter Pivots to Cylinder'), findsOneWidget);
      await tester.ensureVisible(find.text('Mirror Left → Right Hubs'));
      await tester.tap(find.text('Mirror Left → Right Hubs'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.ensureVisible(find.text('Recenter Pivots to Cylinder'));
      await tester.tap(find.text('Recenter Pivots to Cylinder'));
      await tester.pump(const Duration(milliseconds: 50));

      // Step 3: Add Physics
      await tester.tap(find.text('Add Physics').first);
      await tester.pump(const Duration(milliseconds: 100));

      // Manual view shows slider parameters
      expect(find.text('MANUAL PHYSICS PARAMETERS'), findsOneWidget);
      expect(find.text('Vehicle Mass (kg)'), findsOneWidget);
      expect(find.text('Center of Mass Height Offset'), findsOneWidget);
      expect(find.text('Spring Stiffness'), findsOneWidget);

      // Step 4: Add Sound
      await tester.tap(find.text('Add Sound').first);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('AUDIO SLOT CONFIGURATION'), findsOneWidget);
      expect(find.text('Idle Loop'), findsOneWidget);
      expect(find.text('High RPM Loop'), findsOneWidget);
      expect(find.text('Tire Skid'), findsOneWidget);
      expect(find.text('Siren/Extra'), findsOneWidget);

      // Step 5: Export Rig
      await tester.tap(find.text('Export Rig').first);
      await tester.pump(const Duration(milliseconds: 100));

      // Toggle Godot architecture
      await tester.ensureVisible(find.text('Custom Raycast Vehicle Setup'));
      await tester.tap(find.text('Custom Raycast Vehicle Setup'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Scripted multi-ray suspension solver for custom drift & arcade handling.'), findsOneWidget);

      // Launch Test Drive button works
      await tester.ensureVisible(find.text('Launch Test Drive'));
      await tester.tap(find.text('Launch Test Drive'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('WORKBENCH'), findsOneWidget);
    });

    testWidgets('collapses and expands left sidepanel with toggle button', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Sidebar is initially expanded with collapse button
      expect(find.byTooltip('Collapse left sidebar'), findsOneWidget);
      expect(find.byTooltip('Collapse sidebar'), findsOneWidget);
      expect(find.text('RIGGING PIPELINE'), findsOneWidget);

      // Tap collapse button in topbar
      await tester.tap(find.byTooltip('Collapse left sidebar'));
      await tester.pumpAndSettle();

      // Now topbar shows Expand left sidebar button
      expect(find.byTooltip('Expand left sidebar'), findsOneWidget);

      // Tap expand button to restore sidebar
      await tester.tap(find.byTooltip('Expand left sidebar'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Collapse left sidebar'), findsOneWidget);
      expect(find.text('RIGGING PIPELINE'), findsOneWidget);
    });
  });

  group('VehiclePhysicsSimulation Godot 4 Physics', () {
    test('Initializes with default resting state', () {
      final sim = VehiclePhysicsSimulation(
        mass: 1200,
        engineForce: 450,
        grip: 1.0,
        suspension: 6.0,
        centerOfMass: -0.18,
        drive: 'AWD',
        frontSteering: true,
        rearSteering: false,
        frontTraction: true,
        rearTraction: true,
        wheelPositions: const [
          Vec3(-0.95, 0.35, -1.25),
          Vec3(0.95, 0.35, -1.25),
          Vec3(-0.95, 0.35, 1.25),
          Vec3(0.95, 0.35, 1.25),
        ],
      );

      expect(sim.speedKmh, 0.0);
      expect(sim.currentGear, 1);
      expect(sim.engineRpm, 950.0);
      expect(sim.position.z, 24.0);
      expect(sim.cones.isNotEmpty, isTrue);
    });

    test('Throttle accelerates vehicle and shifts gears', () {
      final sim = VehiclePhysicsSimulation(
        mass: 1200,
        engineForce: 600,
        grip: 1.0,
        suspension: 6.0,
        centerOfMass: -0.18,
        drive: 'AWD',
        frontSteering: true,
        rearSteering: false,
        frontTraction: true,
        rearTraction: true,
        wheelPositions: const [
          Vec3(-0.95, 0.35, -1.25),
          Vec3(0.95, 0.35, -1.25),
          Vec3(-0.95, 0.35, 1.25),
          Vec3(0.95, 0.35, 1.25),
        ],
      );

      for (var i = 0; i < 100; i++) {
        sim.step(0.02, throttleInput: 1.0, steerInput: 0.0, handbrake: false);
      }

      expect(sim.speedKmh > 20.0, isTrue);
      expect(sim.position.z < 24.0, isTrue);
      expect(sim.engineRpm > 1200.0, isTrue);
    });

    test('Steering input induces yaw angular velocity', () {
      final sim = VehiclePhysicsSimulation(
        mass: 1200,
        engineForce: 500,
        grip: 1.0,
        suspension: 6.0,
        centerOfMass: -0.18,
        drive: 'AWD',
        frontSteering: true,
        rearSteering: false,
        frontTraction: true,
        rearTraction: true,
        wheelPositions: const [
          Vec3(-0.95, 0.35, -1.25),
          Vec3(0.95, 0.35, -1.25),
          Vec3(-0.95, 0.35, 1.25),
          Vec3(0.95, 0.35, 1.25),
        ],
      );

      for (var i = 0; i < 80; i++) {
        sim.step(0.02, throttleInput: 1.0, steerInput: 0.8, handbrake: false);
      }

      expect(sim.steerAngle != 0.0, isTrue);
      expect(sim.yaw != 0.0, isTrue);
    });

    test('Handbrake triggers drift and generates tire skid marks', () {
      final sim = VehiclePhysicsSimulation(
        mass: 1200,
        engineForce: 800,
        grip: 0.9,
        suspension: 6.0,
        centerOfMass: -0.18,
        drive: 'RWD',
        frontSteering: true,
        rearSteering: false,
        frontTraction: false,
        rearTraction: true,
        wheelPositions: const [
          Vec3(-0.95, 0.35, -1.25),
          Vec3(0.95, 0.35, -1.25),
          Vec3(-0.95, 0.35, 1.25),
          Vec3(0.95, 0.35, 1.25),
        ],
      );

      for (var i = 0; i < 70; i++) {
        sim.step(0.02, throttleInput: 1.0, steerInput: 0.0, handbrake: false);
      }
      expect(sim.speedKmh > 18.0, isTrue);

      for (var i = 0; i < 30; i++) {
        sim.step(0.02, throttleInput: 0.5, steerInput: 1.0, handbrake: true);
      }

      expect(sim.isDrifting, isTrue);
      expect(sim.leftSkidMarks.isNotEmpty, isTrue);
      expect(sim.rightSkidMarks.isNotEmpty, isTrue);
    });
  });

  group('Interactive Test Drive Simulation Mode', () {
    testWidgets('renders TestDriveViewport with Godot racing HUD', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: RigWorkbenchPage(startInTestDrive: true)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('GODOT 4 VEHICLE SIMULATOR'), findsOneWidget);
      expect(find.text('KM/H'), findsOneWidget);
      expect(find.text('G-METER'), findsOneWidget);
      expect(find.text('TIRE SLIP & SUSPENSION'), findsOneWidget);
      expect(find.text('EXIT TEST DRIVE'), findsOneWidget);

      await tester.tap(find.text('EXIT TEST DRIVE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('CAR RIGGER'), findsOneWidget);
      expect(find.text('TEST DRIVE'), findsWidgets);
    });

    testWidgets('toggles Test Drive mode from workbench topbar button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: RigWorkbenchPage(startInTestDrive: false)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('CAR RIGGER'), findsOneWidget);

      await tester.tap(find.text('TEST DRIVE').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('GODOT 4 VEHICLE SIMULATOR'), findsOneWidget);
    });

    testWidgets(
      'toggles natural and inverted controls in 3D wireframe viewer',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(home: RigWorkbenchPage(startInTestDrive: false)),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Find invert controls toggle button by tooltip
        final invertButton = find.byTooltip(
          'Controls: Natural (Click for Inverted)',
        );
        expect(invertButton, findsOneWidget);

        await tester.tap(invertButton);
        await tester.pump();

        expect(
          find.byTooltip('Controls: Inverted (Click for Natural)'),
          findsOneWidget,
        );
      },
    );

    testWidgets('cycles and switches land grid styles in 3D wireframe viewer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: RigWorkbenchPage(startInTestDrive: false)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Initially CAD Grid is selected
      expect(find.text('CAD Grid'), findsOneWidget);

      // Cycle to Radial Podium
      final cycleButton = find.byTooltip('Cycle Land Grid (Radial Podium)');
      expect(cycleButton, findsOneWidget);

      await tester.tap(cycleButton);
      await tester.pump();

      expect(find.text('Radial'), findsOneWidget);
    });

    testWidgets(
      'renders TestDriveViewport with Day Bright lighting and asphalt track selector',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(home: RigWorkbenchPage(startInTestDrive: true)),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Day'), findsOneWidget);
        expect(find.text('Circuit'), findsOneWidget);
        expect(
          find.byTooltip('Environment Lighting: Day Bright'),
          findsOneWidget,
        );
        expect(
          find.byTooltip('Track Surface: Circuit Asphalt'),
          findsOneWidget,
        );
      },
    );

    testWidgets('toggles fullscreen mode in TestDriveViewport with button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: RigWorkbenchPage(startInTestDrive: true)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final fsBtn = find.text('FULLSCREEN (F)');
      expect(fsBtn, findsOneWidget);
      await tester.ensureVisible(fsBtn);

      await tester.tap(fsBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final exitFsBtn = find.text('EXIT FULL (F)');
      expect(exitFsBtn, findsOneWidget);
      await tester.ensureVisible(exitFsBtn);

      await tester.tap(exitFsBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('FULLSCREEN (F)'), findsOneWidget);
    });

    testWidgets(
      'switches viewport render mode between Wireframe, Solid, and Hybrid',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: WireframeViewer(
                model: null,
                detection: null,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('SOLID'), findsOneWidget);

        // Open render mode dropdown and tap Wireframe
        final solidBtn = find.text('SOLID');
        await tester.tap(solidBtn);
        await tester.pumpAndSettle();

        // Tap Wireframe option
        await tester.tap(find.text('Wireframe').last);
        await tester.pumpAndSettle();

        expect(find.text('WIREFRAME'), findsOneWidget);

        // Open render mode dropdown and tap Hybrid
        final wireframeBtn = find.text('WIREFRAME');
        await tester.tap(wireframeBtn);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Hybrid').last);
        await tester.pumpAndSettle();

        expect(find.text('HYBRID'), findsOneWidget);
      },
    );

    testWidgets(
      'renders compact non-overflowing 3D viewport topbar with long uploaded model name on narrow screen',
      (tester) async {
        tester.view.physicalSize = const Size(580, 500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final model = ParsedModel(
          fileName:
              'Lamborghini_Aventador_LP700-4_Roadster_Special_Track_Edition.glb',
          nodes: const [],
          meshes: const [],
          instances: const [],
          rootNodeIndices: const [],
          worldBBox: const BBox(Vec3(-1, 0, -2), Vec3(1, 1, 2)),
        );

        final detection = DetectionResult(
          wheels: [
            DetectedWheel(
              nodeIndex: 0,
              nodeName: 'Wheel_FL',
              axle: 'front',
              side: 'left',
              worldPosition: const Vec3(-0.8, 0.3, -1.3),
              confidence: 0.95,
            ),
            DetectedWheel(
              nodeIndex: 1,
              nodeName: 'Wheel_FR',
              axle: 'front',
              side: 'right',
              worldPosition: const Vec3(0.8, 0.3, -1.3),
              confidence: 0.95,
            ),
            DetectedWheel(
              nodeIndex: 2,
              nodeName: 'Wheel_RL',
              axle: 'rear',
              side: 'left',
              worldPosition: const Vec3(-0.8, 0.3, 1.3),
              confidence: 0.95,
            ),
            DetectedWheel(
              nodeIndex: 3,
              nodeName: 'Wheel_RR',
              axle: 'rear',
              side: 'right',
              worldPosition: const Vec3(0.8, 0.3, 1.3),
              confidence: 0.95,
            ),
          ],
          body: const DetectedBody(
            nodeIndex: 4,
            nodeName: 'Body',
            worldBBox: BBox(Vec3(-1, 0, -2), Vec3(1, 1, 2)),
            confidence: 0.95,
          ),
          suggestedDrive: 'AWD',
          suggestedPreset: 'Supercar',
          warnings: const [],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WireframeViewer(
                model: model,
                detection: detection,
                onTestDrive: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('SOLID'), findsOneWidget);
        expect(find.text('ISO'), findsOneWidget);
        expect(find.byTooltip('Fullscreen Viewport'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders high-density uploaded car model smoothly with adaptive budget and pan orbit gesture',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Generate high-density mesh with 12,000 triangles and 12,000 edges
        final highPolyVerts = <Vec3>[];
        final highPolyEdges = <Edge>[];
        final highPolyTriangles = <Triangle>[];

        for (var i = 0; i < 4000; i++) {
          final x = ((i % 20) - 10) * 0.1;
          final y = (((i ~/ 20) % 20) * 0.05) + 0.2;
          final z = ((i ~/ 400) - 5) * 0.4;
          highPolyVerts.add(Vec3(x, y, z));
        }

        for (var i = 0; i < highPolyVerts.length - 2; i++) {
          highPolyEdges.add(Edge(i, i + 1));
          highPolyEdges.add(Edge(i + 1, i + 2));
          highPolyTriangles.add(Triangle(i, i + 1, i + 2));
          highPolyTriangles.add(Triangle(i + 2, i + 1, i));
        }

        final mesh = MeshData(
          index: 0,
          name: 'Chassis_HighPoly',
          vertices: highPolyVerts,
          edges: highPolyEdges,
          triangles: highPolyTriangles,
          bbox: const BBox(Vec3(-1.0, 0.0, -2.0), Vec3(1.0, 1.2, 2.0)),
        );

        final instance = MeshInstance(
          nodeIndex: 0,
          meshIndex: 0,
          worldVertices: highPolyVerts,
          edges: highPolyEdges,
          triangles: highPolyTriangles,
          worldBBox: const BBox(Vec3(-1.0, 0.0, -2.0), Vec3(1.0, 1.2, 2.0)),
        );

        final model = ParsedModel(
          fileName: 'hypercar_dense_mesh.glb',
          nodes: [
            SceneNode(
              index: 0,
              name: 'Car_Body',
              localTransform: Mat4.identity(),
              meshIndex: 0,
              childIndices: const [],
              parentIndex: null,
            )..worldTransform = Mat4.identity(),
          ],
          meshes: [mesh],
          instances: [instance],
          rootNodeIndices: const [0],
          worldBBox: const BBox(Vec3(-1.0, 0.0, -2.0), Vec3(1.0, 1.2, 2.0)),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WireframeViewer(
                model: model,
                detection: null,
                onTestDrive: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        // Perform multi-step drag orbit to simulate user dragging the car
        final gesture = await tester.startGesture(const Offset(400, 300));
        await gesture.moveBy(const Offset(100, 50));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(const Offset(80, -30));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 50));

        // Switch to Wireframe mode via dropdown and drag again
        await tester.tap(find.text('SOLID'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Wireframe').last);
        await tester.pumpAndSettle();

        final wireGesture = await tester.startGesture(const Offset(400, 300));
        await wireGesture.moveBy(const Offset(-60, 40));
        await tester.pump(const Duration(milliseconds: 16));
        await wireGesture.up();
        await tester.pump(const Duration(milliseconds: 50));

        // Switch to Hybrid mode via dropdown and drag again
        await tester.tap(find.text('WIREFRAME'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hybrid').last);
        await tester.pumpAndSettle();

        final hybridGesture = await tester.startGesture(const Offset(400, 300));
        await hybridGesture.moveBy(const Offset(40, -40));
        await tester.pump(const Duration(milliseconds: 16));
        await hybridGesture.up();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
      },
    );

    test('SolidScene eliminates LOD popping during orbit interaction', () {
      final model = ParsedModel(
        fileName: 'test_car.glb',
        nodes: [
          SceneNode(
            index: 0,
            name: 'Root',
            localTransform: Mat4.identity(),
            meshIndex: 0,
            childIndices: const [],
            parentIndex: null,
          ),
        ],
        meshes: [
          MeshData(
            index: 0,
            name: 'Body',
            vertices: [
              const Vec3(0, 0, 0),
              const Vec3(1, 0, 0),
              const Vec3(0, 1, 0),
            ],
            edges: [Edge(0, 1), Edge(1, 2), Edge(2, 0)],
            triangles: [
              const Triangle(0, 1, 2, Color(0xFFDC2626)),
            ],
            bbox: const BBox(Vec3.zero, Vec3(1, 1, 0)),
          ),
        ],
        instances: [
          MeshInstance(
            nodeIndex: 0,
            meshIndex: 0,
            worldVertices: [
              const Vec3(0, 0, 0),
              const Vec3(1, 0, 0),
              const Vec3(0, 1, 0),
            ],
            edges: [Edge(0, 1), Edge(1, 2), Edge(2, 0)],
            triangles: [
              const Triangle(0, 1, 2, Color(0xFFDC2626)),
            ],
            worldBBox: const BBox(Vec3.zero, Vec3(1, 1, 0)),
          ),
        ],
        rootNodeIndices: [0],
        worldBBox: const BBox(Vec3.zero, Vec3(1, 1, 0)),
      );

      final scene = SolidScene.of(model);
      // Verify that interactive and full share the same mesh instance
      expect(identical(scene.interactive, scene.full), isTrue);
      expect(scene.interactive.triangleCount, scene.full.triangleCount);
    });

    test('Model preserves authentic authored triangle colors without paint override', () {
      final model = ParsedModel(
        fileName: 'test_car.glb',
        nodes: [
          SceneNode(
            index: 0,
            name: 'Root',
            localTransform: Mat4.identity(),
            meshIndex: 0,
            childIndices: const [],
            parentIndex: null,
          ),
        ],
        meshes: [
          MeshData(
            index: 0,
            name: 'Body',
            vertices: [
              const Vec3(0, 0, 0),
              const Vec3(1, 0, 0),
              const Vec3(0, 1, 0),
            ],
            edges: [Edge(0, 1), Edge(1, 2), Edge(2, 0)],
            triangles: [
              const Triangle(0, 1, 2, Color(0xFFDC2626)),
            ],
            bbox: const BBox(Vec3.zero, Vec3(1, 1, 0)),
          ),
        ],
        instances: [
          MeshInstance(
            nodeIndex: 0,
            meshIndex: 0,
            worldVertices: [
              const Vec3(0, 0, 0),
              const Vec3(1, 0, 0),
              const Vec3(0, 1, 0),
            ],
            edges: [Edge(0, 1), Edge(1, 2), Edge(2, 0)],
            triangles: [
              const Triangle(0, 1, 2, Color(0xFFDC2626)),
            ],
            worldBBox: const BBox(Vec3.zero, Vec3(1, 1, 0)),
          ),
        ],
        rootNodeIndices: [0],
        worldBBox: const BBox(Vec3.zero, Vec3(1, 1, 0)),
      );

      final scene = SolidScene.of(model);
      expect(
        scene.full.triColor[0] & 0xFFFFFFFF,
        const Color(0xFFDC2626).toARGB32(),
      );
    });

    test('GlbParser parses Wavefront OBJ files with nodes and geometry', () async {
      const objData = '''
# Wavefront OBJ car
v -1.0 0.0 -2.0
v 1.0 0.0 -2.0
v 1.0 1.2 2.0
v -1.0 1.2 2.0
g Car_Body
f 1 2 3
f 1 3 4
''';
      final bytes = Uint8List.fromList(utf8.encode(objData));
      final model = await GlbParser.parse('sport_coupe.obj', bytes);
      expect(model.fileName, 'sport_coupe.obj');
      expect(model.nodes.isNotEmpty, isTrue);
      expect(model.meshes.isNotEmpty, isTrue);
      expect(model.instances.first.worldVertices.length, 4);
    });

    test('GlbParser parses ASCII STL files into ParsedModel', () async {
      const stlData = '''solid sports_car
facet normal 0 0 1
  outer loop
    vertex 0 0 0
    vertex 1 0 0
    vertex 0 1 0
  endloop
endfacet
endsolid sports_car''';
      final bytes = Uint8List.fromList(utf8.encode(stlData));
      final model = await GlbParser.parse('car_body.stl', bytes);
      expect(model.fileName, 'car_body.stl');
      expect(model.instances.isNotEmpty, isTrue);
      expect(model.instances.first.worldVertices.length, 3);
    });

    test('GlbParser provides structured vehicle fallback for FBX or binary packages', () async {
      final dummyFbxBytes = Uint8List.fromList([
        0x4B, 0x61, 0x79, 0x64, 0x61, 0x72, 0x61, 0x20, // 'Kaydara '
        0x46, 0x42, 0x58, 0x20, 0x42, 0x69, 0x6E, 0x61,
        0x72, 0x79, 0x20, 0x20, 0x00, 0x1A, 0x00,
      ]);
      final model = await GlbParser.parse('racecar.fbx', dummyFbxBytes);
      expect(model.fileName, 'racecar.fbx');
      expect(model.nodes.length, 5); // Body + 4 wheels
      final nodeNames = model.nodes.map((n) => n.name).toList();
      expect(nodeNames.contains('Wheel_FL'), isTrue);
      expect(nodeNames.contains('Wheel_FR'), isTrue);
      expect(nodeNames.contains('Car_Body'), isTrue);
    });
  });
}
