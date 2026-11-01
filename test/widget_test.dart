import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rig_car/auto_detector.dart';
import 'package:rig_car/main.dart';
import 'package:rig_car/model_data.dart';
import 'package:rig_car/pre_rigged_cars.dart';

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

    testWidgets('navigates from home screen to workbench via "Rig Your Car"',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RigCarApp());

      // Tap top Rig Your Car button
      await tester.tap(find.text('Rig Your Car').first);
      await tester.pumpAndSettle();

      expect(find.text('CAR RIGGER'), findsOneWidget);
      expect(find.text('Mixamo-Style Auto-Rig'), findsOneWidget);

      // Back button exists and navigates back
      expect(find.text('Fleet Library'), findsWidgets);
    });
  });

  group('UI Workbench Flow', () {
    testWidgets('renders workbench shell and 3D wireframe viewer',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));

      expect(find.text('RIG-CAR'), findsWidgets);
      expect(find.text('CAR RIGGER'), findsOneWidget);
      expect(find.text('Mixamo-Style Auto-Rig'), findsOneWidget);
      expect(find.text('Procedural 3D Rig'), findsOneWidget);
    });

    testWidgets('switches between workflow steps in workbench', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));

      // Tap Step 2: Review Detections
      await tester.tap(find.text('2  Review Rig'));
      await tester.pumpAndSettle();
      expect(find.text('Human-Assist Wheel Assignment'), findsOneWidget);

      // Tap Step 3: Tune physics
      await tester.tap(find.text('3  Tune physics'));
      await tester.pumpAndSettle();
      expect(find.text('Vehicle Physics'), findsOneWidget);
      expect(find.text('Mass'), findsOneWidget);

      // Tap Step 4: Export to Godot
      await tester.tap(find.text('4  Export to Godot'));
      await tester.pumpAndSettle();
      expect(find.text('Godot 4 Rig Package'), findsOneWidget);
      expect(find.text('rig_car.tscn'), findsOneWidget);
    });
  });
}
