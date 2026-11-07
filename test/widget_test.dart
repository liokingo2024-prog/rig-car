import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rig_car/auto_detector.dart';
import 'package:rig_car/main.dart';
import 'package:rig_car/model_data.dart';
import 'package:rig_car/physics_sim.dart';
import 'package:rig_car/pre_rigged_cars.dart';
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
      expect(find.text('Mixamo-Style Auto-Rig'), findsOneWidget);

      // Back button exists and navigates back
      expect(find.text('Fleet Library'), findsWidgets);
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
      expect(find.text('Mixamo-Style Auto-Rig'), findsOneWidget);
      expect(find.text('Procedural 3D Rig'), findsOneWidget);
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

    testWidgets('switches between workflow steps in workbench', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Step 2: Review Detections
      await tester.tap(find.text('Review Detections'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Human-Assist Wheel Assignment'), findsOneWidget);

      // Tap Step 3: Tune physics
      await tester.tap(find.text('Tune physics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Vehicle Physics'), findsOneWidget);
      expect(find.text('Mass'), findsOneWidget);

      // Tap Step 4: Export to Godot
      await tester.tap(find.text('Export to Godot'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Godot 4 Rig Package'), findsOneWidget);
      expect(find.text('rig_car.tscn'), findsOneWidget);
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
  });
}
