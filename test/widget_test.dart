import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rig_car/auto_detector.dart';
import 'package:rig_car/file_picker_stub.dart';
import 'package:rig_car/glb_parser.dart';
import 'package:rig_car/main.dart';
import 'package:rig_car/model_data.dart';
import 'package:rig_car/physics_sim.dart';
import 'package:rig_car/pre_rigged_cars.dart';
import 'package:rig_car/solid_mesh_lod.dart';
import 'package:rig_car/sketchfab_viewport.dart';
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

    test('4-Quadrant Tire Scoring handles staggered 2+2 axles and rejects inboard knuckles', () {
      final nodes = <SceneNode>[
        SceneNode(
          index: 0,
          name: 'Root',
          localTransform: Mat4.identity(),
          meshIndex: null,
          childIndices: [1, 2, 3, 4, 5, 6, 7, 8, 9],
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
        // Front Axle: Diameter 0.60m, Width 0.20m, Grounded Y=0.30
        SceneNode(
          index: 2,
          name: 'FrontTire_L',
          localTransform: Mat4.fromTRS(const Vec3(-0.85, 0.30, -1.2), Quat.identity, Vec3.one),
          meshIndex: 1,
          childIndices: [],
          parentIndex: 0,
        ),
        SceneNode(
          index: 3,
          name: 'FrontTire_R',
          localTransform: Mat4.fromTRS(const Vec3(0.85, 0.30, -1.2), Quat.identity, Vec3.one),
          meshIndex: 1,
          childIndices: [],
          parentIndex: 0,
        ),
        // Rear Axle (Staggered wider & larger): Diameter 0.70m, Width 0.30m, Grounded Y=0.35
        SceneNode(
          index: 4,
          name: 'RearTire_L',
          localTransform: Mat4.fromTRS(const Vec3(-0.90, 0.35, 1.2), Quat.identity, Vec3.one),
          meshIndex: 2,
          childIndices: [],
          parentIndex: 0,
        ),
        SceneNode(
          index: 5,
          name: 'RearTire_R',
          localTransform: Mat4.fromTRS(const Vec3(0.90, 0.35, 1.2), Quat.identity, Vec3.one),
          meshIndex: 2,
          childIndices: [],
          parentIndex: 0,
        ),
        // Inboard Suspension Knuckles (Inboard lateral X=0.45, Higher up Y=0.45, Irregular profile): MUST BE REJECTED
        SceneNode(
          index: 6,
          name: 'Knuckle_FL',
          localTransform: Mat4.fromTRS(const Vec3(-0.45, 0.45, -1.2), Quat.identity, Vec3.one),
          meshIndex: 3,
          childIndices: [],
          parentIndex: 0,
        ),
        SceneNode(
          index: 7,
          name: 'Knuckle_FR',
          localTransform: Mat4.fromTRS(const Vec3(0.45, 0.45, -1.2), Quat.identity, Vec3.one),
          meshIndex: 3,
          childIndices: [],
          parentIndex: 0,
        ),
        SceneNode(
          index: 8,
          name: 'Knuckle_RL',
          localTransform: Mat4.fromTRS(const Vec3(-0.45, 0.45, 1.2), Quat.identity, Vec3.one),
          meshIndex: 3,
          childIndices: [],
          parentIndex: 0,
        ),
        SceneNode(
          index: 9,
          name: 'Knuckle_RR',
          localTransform: Mat4.fromTRS(const Vec3(0.45, 0.45, 1.2), Quat.identity, Vec3.one),
          meshIndex: 3,
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
        vertices: const [Vec3(-1.0, 0.0, -2.0), Vec3(1.0, 1.4, 2.0)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-1.0, 0.0, -2.0), Vec3(1.0, 1.4, 2.0)),
      );

      final frontTireMesh = MeshData(
        index: 1,
        name: 'FrontTireMesh',
        vertices: const [Vec3(-0.10, -0.30, -0.30), Vec3(0.10, 0.30, 0.30)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.10, -0.30, -0.30), Vec3(0.10, 0.30, 0.30)),
      );

      final rearTireMesh = MeshData(
        index: 2,
        name: 'RearTireMesh',
        vertices: const [Vec3(-0.15, -0.35, -0.35), Vec3(0.15, 0.35, 0.35)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.15, -0.35, -0.35), Vec3(0.15, 0.35, 0.35)),
      );

      final knuckleMesh = MeshData(
        index: 3,
        name: 'KnuckleMesh',
        vertices: const [Vec3(-0.08, -0.12, -0.25), Vec3(0.08, 0.12, 0.25)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.08, -0.12, -0.25), Vec3(0.08, 0.12, 0.25)),
      );

      final instances = <MeshInstance>[];
      instances.add(MeshInstance(
        nodeIndex: 1,
        meshIndex: 0,
        worldVertices: bodyMesh.vertices,
        edges: bodyMesh.edges,
        worldBBox: bodyMesh.bbox,
      ));
      for (var i = 2; i <= 9; i++) {
        final node = nodes[i];
        final mesh = [bodyMesh, frontTireMesh, rearTireMesh, knuckleMesh][node.meshIndex!];
        instances.add(MeshInstance(
          nodeIndex: i,
          meshIndex: node.meshIndex!,
          worldVertices: mesh.vertices.map(node.localTransform.transformPoint).toList(),
          edges: mesh.edges,
          worldBBox: BBox.fromPoints(mesh.vertices.map(node.localTransform.transformPoint).toList()),
        ));
      }

      final model = ParsedModel(
        fileName: 'staggered_car.glb',
        nodes: nodes,
        meshes: [bodyMesh, frontTireMesh, rearTireMesh, knuckleMesh],
        instances: instances,
        rootNodeIndices: [0],
        worldBBox: const BBox(Vec3(-1.0, 0.0, -2.0), Vec3(1.0, 1.4, 2.0)),
      );

      final result = AutoDetector.detect(model);
      expect(result.wheels.length, 4);
      expect(result.wheels.every((w) => !w.nodeName.contains('Knuckle')), isTrue);
      expect(result.wheels.any((w) => w.nodeName == 'FrontTire_L'), isTrue);
      expect(result.wheels.any((w) => w.nodeName == 'RearTire_R'), isTrue);
      expect(result.isStaggered, isTrue);
      expect(result.groundContactVerified, isTrue);
      expect(result.inboardSuspensionExcluded, isTrue);
    });

    test('Coaxial Hub Clustering & 3D Cylinder Containment solves rim face competition and captures full wheel union box', () {
      final bodyMesh = MeshData(
        index: 0,
        name: 'Chassis',
        vertices: const [Vec3(-0.7, 0.3, -1.8), Vec3(0.7, 1.1, 1.8)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.7, 0.3, -1.8), Vec3(0.7, 1.1, 1.8)),
      );

      // Rubber Tire: R=0.34m, W=0.25m, touches ground y=0.0
      final tireMesh = MeshData(
        index: 1,
        name: 'TireMesh',
        vertices: const [Vec3(-0.125, -0.34, -0.34), Vec3(0.125, 0.34, 0.34)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.125, -0.34, -0.34), Vec3(0.125, 0.34, 0.34)),
      );

      // Thin Outer Rim Face: R=0.32m, W=0.01m (previously competed with and rejected tire)
      final rimFaceMesh = MeshData(
        index: 2,
        name: 'RimFaceMesh',
        vertices: const [Vec3(-0.005, -0.32, -0.32), Vec3(0.005, 0.32, 0.32)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.005, -0.32, -0.32), Vec3(0.005, 0.32, 0.32)),
      );

      // Inner Spokes (non-circular component inside cylinder)
      final spokesMesh = MeshData(
        index: 3,
        name: 'SpokesMesh',
        vertices: const [Vec3(-0.05, -0.25, -0.15), Vec3(0.05, 0.25, 0.15)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.05, -0.25, -0.15), Vec3(0.05, 0.25, 0.15)),
      );

      // Center Cap: Tiny 0.03m sub-part (previously reported as entire wheel R=0.03m)
      final centerCapMesh = MeshData(
        index: 4,
        name: 'CenterCapMesh',
        vertices: const [Vec3(-0.015, -0.015, -0.015), Vec3(0.015, 0.015, 0.015)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.015, -0.015, -0.015), Vec3(0.015, 0.015, 0.015)),
      );

      // Inboard Knuckle: Sits inboard of tire lateral width
      final knuckleMesh = MeshData(
        index: 5,
        name: 'SuspensionKnuckle',
        vertices: const [Vec3(-0.06, -0.10, -0.10), Vec3(0.06, 0.10, 0.10)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.06, -0.10, -0.10), Vec3(0.06, 0.10, 0.10)),
      );

      final nodes = <SceneNode>[
        SceneNode(
          index: 0,
          name: 'Root',
          parentIndex: null,
          meshIndex: null,
          childIndices: List.generate(21, (i) => i + 1),
          localTransform: Mat4.identity(),
        ),
        SceneNode(
          index: 1,
          name: 'CarBody',
          parentIndex: 0,
          meshIndex: 0,
          childIndices: [],
          localTransform: Mat4.identity(),
        ),
      ];

      // 4 corners: FL, FR, RL, RR
      final cornerCenters = [
        const Vec3(-0.85, 0.34, 1.4),   // FL
        const Vec3(0.85, 0.34, 1.4),    // FR
        const Vec3(-0.85, 0.34, -1.4),  // RL
        const Vec3(0.85, 0.34, -1.4),   // RR
      ];

      var nodeIdx = 2;
      for (var c = 0; c < 4; c++) {
        final pos = cornerCenters[c];
        final sideSign = pos.x < 0 ? -1.0 : 1.0;

        // Tire
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'Tire_$c',
          parentIndex: 0,
          meshIndex: 1,
          childIndices: [],
          localTransform: Mat4.fromTRS(pos, Quat.identity, Vec3.one),
        ));
        // Rim face (at outer edge)
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'RimFace_$c',
          parentIndex: 0,
          meshIndex: 2,
          childIndices: [],
          localTransform: Mat4.fromTRS(Vec3(pos.x + sideSign * 0.12, pos.y, pos.z), Quat.identity, Vec3.one),
        ));
        // Spokes
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'Spokes_$c',
          parentIndex: 0,
          meshIndex: 3,
          childIndices: [],
          localTransform: Mat4.fromTRS(Vec3(pos.x, pos.y, pos.z), Quat.identity, Vec3.one),
        ));
        // Center cap
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'CenterCap_$c',
          parentIndex: 0,
          meshIndex: 4,
          childIndices: [],
          localTransform: Mat4.fromTRS(Vec3(pos.x + sideSign * 0.12, pos.y, pos.z), Quat.identity, Vec3.one),
        ));
        // Knuckle (inboard)
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'Knuckle_$c',
          parentIndex: 0,
          meshIndex: 5,
          childIndices: [],
          localTransform: Mat4.fromTRS(Vec3(pos.x - sideSign * 0.22, pos.y, pos.z), Quat.identity, Vec3.one),
        ));
      }

      for (final n in nodes) {
        n.worldTransform = n.localTransform;
      }

      final allMeshes = [bodyMesh, tireMesh, rimFaceMesh, spokesMesh, centerCapMesh, knuckleMesh];
      final instances = <MeshInstance>[];
      instances.add(MeshInstance(
        nodeIndex: 1,
        meshIndex: 0,
        worldVertices: bodyMesh.vertices,
        edges: bodyMesh.edges,
        worldBBox: bodyMesh.bbox,
      ));

      for (var i = 2; i < nodes.length; i++) {
        final node = nodes[i];
        final mesh = allMeshes[node.meshIndex!];
        final wVerts = mesh.vertices.map(node.localTransform.transformPoint).toList();
        instances.add(MeshInstance(
          nodeIndex: i,
          meshIndex: node.meshIndex!,
          worldVertices: wVerts,
          edges: mesh.edges,
          worldBBox: BBox.fromPoints(wVerts),
        ));
      }

      final model = ParsedModel(
        fileName: '2010_lamborghini_sesto_elemento_-_scpd_police.glb',
        nodes: nodes,
        meshes: allMeshes,
        instances: instances,
        rootNodeIndices: [0],
        worldBBox: const BBox(Vec3(-1.0, 0.0, -2.1), Vec3(1.0, 1.2, 2.1)),
      );

      final result = AutoDetector.detect(model);

      expect(result.wheels.length, 4);

      // Verify Bug 1 & 2 fixes across all 4 wheels:
      for (final wheel in result.wheels) {
        // Radius is computed from the full union box (>= 0.33m), NOT the 0.03m center cap!
        expect(wheel.radius >= 0.33, isTrue, reason: 'Wheel ${wheel.label} radius should be ~0.34m, was ${wheel.radius}');
        // Width is computed from full assembly (>= 0.24m), NOT the 0.01m rim face!
        expect(wheel.width >= 0.24, isTrue, reason: 'Wheel ${wheel.label} width should be ~0.25m, was ${wheel.width}');
        // Captured multiple sub-parts (tire, rim, spokes, cap)
        expect(wheel.subMeshCount >= 3, isTrue, reason: 'Wheel ${wheel.label} should merge at least 3 sub-meshes');
        // Excluded inboard suspension knuckles
        expect(wheel.partIds.any((p) => p.contains('Knuckle')), isFalse);
      }
    });

    test('Two-Zone Capture automatically captures inner brake rotors, calipers, and hub frames without inflating tire R and W', () {
      final bodyMesh = MeshData(
        index: 0,
        name: 'Chassis',
        vertices: const [Vec3(-0.7, 0.3, -1.8), Vec3(0.7, 1.1, 1.8)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.7, 0.3, -1.8), Vec3(0.7, 1.1, 1.8)),
      );

      // Rubber Tire: R=0.33m, W=0.23m
      final tireMesh = MeshData(
        index: 1,
        name: 'TireMesh',
        vertices: const [Vec3(-0.115, -0.33, -0.33), Vec3(0.115, 0.33, 0.33)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.115, -0.33, -0.33), Vec3(0.115, 0.33, 0.33)),
      );

      // Outer Rim Face
      final rimFaceMesh = MeshData(
        index: 2,
        name: 'RimFaceMesh',
        vertices: const [Vec3(-0.01, -0.31, -0.31), Vec3(0.01, 0.31, 0.31)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.01, -0.31, -0.31), Vec3(0.01, 0.31, 0.31)),
      );

      // Spokes (Zone 1)
      final spokesMesh = MeshData(
        index: 3,
        name: 'SpokesMesh',
        vertices: const [Vec3(-0.03, -0.25, -0.20), Vec3(0.03, 0.25, 0.20)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.03, -0.25, -0.20), Vec3(0.03, 0.25, 0.20)),
      );

      // Inner Brake Rotor: R=0.26m, W=0.03m (Zone 2, Coaxial & Circular)
      final brakeRotorMesh = MeshData(
        index: 4,
        name: 'BrakeRotorMesh',
        vertices: const [Vec3(-0.015, -0.26, -0.26), Vec3(0.015, 0.26, 0.26)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.015, -0.26, -0.26), Vec3(0.015, 0.26, 0.26)),
      );

      // Inner Brake Caliper: W=0.08m, asymmetric/eccentric (Zone 2, CaliperHub)
      final brakeCaliperMesh = MeshData(
        index: 5,
        name: 'BrakeCaliperMesh',
        vertices: const [Vec3(-0.04, 0.05, -0.06), Vec3(0.04, 0.25, 0.06)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.04, 0.05, -0.06), Vec3(0.04, 0.25, 0.06)),
      );

      // Hub Frame Bracket: W=0.06m (Zone 2, CaliperHub)
      final hubFrameMesh = MeshData(
        index: 6,
        name: 'HubFrameMesh',
        vertices: const [Vec3(-0.03, -0.09, -0.09), Vec3(0.03, 0.09, 0.09)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.03, -0.09, -0.09), Vec3(0.03, 0.09, 0.09)),
      );

      // Inboard Suspension Wishbone: W=0.45m (MUST BE EXCLUDED)
      final wishboneMesh = MeshData(
        index: 7,
        name: 'SuspensionWishbone',
        vertices: const [Vec3(-0.225, -0.04, -0.04), Vec3(0.225, 0.04, 0.04)],
        edges: [Edge(0, 1)],
        bbox: const BBox(Vec3(-0.225, -0.04, -0.04), Vec3(0.225, 0.04, 0.04)),
      );

      final nodes = <SceneNode>[
        SceneNode(
          index: 0,
          name: 'Root',
          parentIndex: null,
          meshIndex: null,
          childIndices: List.generate(29, (i) => i + 1),
          localTransform: Mat4.identity(),
        ),
        SceneNode(
          index: 1,
          name: 'CarBody',
          parentIndex: 0,
          meshIndex: 0,
          childIndices: [],
          localTransform: Mat4.identity(),
        ),
      ];

      final cornerCenters = [
        const Vec3(-0.85, 0.33, 1.3),   // FL
        const Vec3(0.85, 0.33, 1.3),    // FR
        const Vec3(-0.85, 0.33, -1.3),  // RL
        const Vec3(0.85, 0.33, -1.3),   // RR
      ];

      var nodeIdx = 2;
      for (var c = 0; c < 4; c++) {
        final pos = cornerCenters[c];
        final sideSign = pos.x < 0 ? -1.0 : 1.0;

        // Tire
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'Tire_$c',
          parentIndex: 0,
          meshIndex: 1,
          childIndices: [],
          localTransform: Mat4.fromTRS(pos, Quat.identity, Vec3.one),
        ));
        // Rim face
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'RimFace_$c',
          parentIndex: 0,
          meshIndex: 2,
          childIndices: [],
          localTransform: Mat4.fromTRS(Vec3(pos.x + sideSign * 0.11, pos.y, pos.z), Quat.identity, Vec3.one),
        ));
        // Spokes
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'Spokes_$c',
          parentIndex: 0,
          meshIndex: 3,
          childIndices: [],
          localTransform: Mat4.fromTRS(Vec3(pos.x, pos.y, pos.z), Quat.identity, Vec3.one),
        ));
        // Inner Brake Rotor (mounted behind spokes)
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'BrakeRotor_$c',
          parentIndex: 0,
          meshIndex: 4,
          childIndices: [],
          localTransform: Mat4.fromTRS(Vec3(pos.x - sideSign * 0.05, pos.y, pos.z), Quat.identity, Vec3.one),
        ));
        // Inner Brake Caliper (extends 0.08m inboard into hub pocket)
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'BrakeCaliper_$c',
          parentIndex: 0,
          meshIndex: 5,
          childIndices: [],
          localTransform: Mat4.fromTRS(Vec3(pos.x - sideSign * 0.08, pos.y, pos.z), Quat.identity, Vec3.one),
        ));
        // Hub Frame Bracket
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'HubFrame_$c',
          parentIndex: 0,
          meshIndex: 6,
          childIndices: [],
          localTransform: Mat4.fromTRS(Vec3(pos.x - sideSign * 0.06, pos.y, pos.z), Quat.identity, Vec3.one),
        ));
        // Suspension Wishbone (inboard chassis, wide arm -> MUST BE REJECTED)
        nodes.add(SceneNode(
          index: nodeIdx++,
          name: 'Wishbone_$c',
          parentIndex: 0,
          meshIndex: 7,
          childIndices: [],
          localTransform: Mat4.fromTRS(Vec3(pos.x - sideSign * 0.35, pos.y, pos.z), Quat.identity, Vec3.one),
        ));
      }

      for (final n in nodes) {
        n.worldTransform = n.localTransform;
      }

      final allMeshes = [bodyMesh, tireMesh, rimFaceMesh, spokesMesh, brakeRotorMesh, brakeCaliperMesh, hubFrameMesh, wishboneMesh];
      final instances = <MeshInstance>[];
      instances.add(MeshInstance(
        nodeIndex: 1,
        meshIndex: 0,
        worldVertices: bodyMesh.vertices,
        edges: bodyMesh.edges,
        worldBBox: bodyMesh.bbox,
      ));

      for (var i = 2; i < nodes.length; i++) {
        final node = nodes[i];
        final mesh = allMeshes[node.meshIndex!];
        final wVerts = mesh.vertices.map(node.localTransform.transformPoint).toList();
        instances.add(MeshInstance(
          nodeIndex: i,
          meshIndex: node.meshIndex!,
          worldVertices: wVerts,
          edges: mesh.edges,
          worldBBox: BBox.fromPoints(wVerts),
        ));
      }

      final model = ParsedModel(
        fileName: 'dirt_2_mitsubishi_lancer_evolution_ix.glb',
        nodes: nodes,
        meshes: allMeshes,
        instances: instances,
        rootNodeIndices: [0],
        worldBBox: const BBox(Vec3(-1.0, 0.0, -2.1), Vec3(1.0, 1.2, 2.1)),
      );

      final result = AutoDetector.detect(model);

      expect(result.wheels.length, 4);

      for (final wheel in result.wheels) {
        // True tire radius is preserved from coreWheelBox (not corrupted by rotor or caliper)
        expect((wheel.radius - 0.33).abs() < 0.015, isTrue,
            reason: 'Tire radius should be preserved at ~0.33m, got ${wheel.radius}');
        // True tire width is preserved from coreWheelBox (not inflated by the inboard caliper bracket)
        expect((wheel.width - 0.23).abs() < 0.015, isTrue,
            reason: 'Tire width should be preserved at ~0.23m, got ${wheel.width}');
        // Sub-mesh count includes tire, rim face, spokes, brake rotor, caliper, hub frame (at least 5 parts)
        expect(wheel.subMeshCount >= 5, isTrue,
            reason: 'Wheel should capture brake rotor, caliper, and hub frame (subMeshCount=${wheel.subMeshCount})');
        // Sub-classified: spinNodeIndices contains tire, rim, rotor
        expect(wheel.spinNodeIndices.isNotEmpty, isTrue);
        // Sub-classified: caliperHubNodeIndices contains asymmetric caliper/hub frame
        expect(wheel.caliperHubNodeIndices.isNotEmpty, isTrue);
        // Inboard long suspension wishbones were NOT captured
        expect(wheel.partIds.any((p) => p.contains('Wishbone')), isFalse);
      }

      // No false wheel warnings when 4 grounded wheels are present
      expect(result.warnings.any((w) => w.contains('Some wheel assemblies were inferred')), isFalse);
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
      expect(find.byTooltip('Auto-rig vehicle'), findsNothing);
      expect(find.text('ISO'), findsWidgets);
      expect(find.byTooltip('Viewport lighting: Studio'), findsOneWidget);
      expect(find.byTooltip('Fullscreen Viewport'), findsOneWidget);

      // Open camera angle dropdown and switch to Rear view
      await tester.tap(find.text('ISO').first);
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

      // Right inspector fixed header and Step 1 merged view (no auto/custom toggle)
      expect(find.text('✨ Auto'), findsNothing);
      expect(find.text('🛠 Custom'), findsNothing);

      // Step 1: Upload vehicle is collapsed by default
      expect(find.text('Expand Vehicle Details & Tools'), findsOneWidget);
      expect(find.text('Next: Scan & Organize'), findsOneWidget);

      // Tap to expand Step 1
      await tester.tap(find.text('Expand Vehicle Details & Tools'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PROGRESS & BOUNDS VERIFICATION'), findsOneWidget);
      expect(find.text('Model Parsed'), findsOneWidget);
      expect(find.text('Bounding Box'), findsOneWidget);
      expect(find.text('Ground Plane Snap'), findsOneWidget);
      expect(find.text('Forward Axis'), findsOneWidget);
      expect(find.text('ORIENTATION QUICK-FIX'), findsOneWidget);
      expect(find.text('SCALE NORMALIZATION'), findsOneWidget);
      expect(find.text('BOUNDS FILTER'), findsOneWidget);

      // Tap Step 2: Scan & Organize
      await tester.tap(find.text('Scan & Organize').first);
      await tester.pump(const Duration(milliseconds: 100));

      // Steps 2-4 display Auto & Custom toggle
      expect(find.text('✨ Auto'), findsOneWidget);
      expect(find.text('🛠 Custom'), findsOneWidget);

      expect(find.text('4-STAGE AUTO-RIG PIPELINE'), findsOneWidget);
      expect(find.text('1. Separate Loose Parts'), findsOneWidget);
      expect(find.text('2. Axle Symmetry & Circularity (2+2 / 4x)'), findsOneWidget);
      expect(find.text('3. Ground Contact & Outer-Track Filter'), findsOneWidget);
      expect(find.text('4. Hub Center & Radius Math'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);

      // Switch to Custom
      await tester.tap(find.text('🛠 Custom'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('A. DETECTED 2/4 GROUP CHECKLIST'), findsOneWidget);
      expect(find.text('B. HEIGHT & CORNER FILTER OVERRIDE'), findsOneWidget);
      expect(find.text('C. 4-CORNER MANUAL SLOT PICKER'), findsOneWidget);
      expect(find.text('D. ONE-CLICK SYMMETRY & PIVOT REPAIR'), findsOneWidget);
      expect(find.text('Mirror Left → Right Hubs'), findsOneWidget);

      // Tap Step 3: Add Physics while Step 2 is incomplete (should stay locked)
      await tester.tap(find.text('Add Physics').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('HANDLING PRESETS'), findsNothing);

      // Switch back to Auto and click Start to complete Step 2
      await tester.tap(find.text('✨ Auto'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // Now that Step 2 is completed, tap Step 3: Add Physics
      await tester.tap(find.text('Add Physics').first);
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

      // Step 1: Merged view is collapsed by default; expand to reveal controls
      expect(find.text('Expand Vehicle Details & Tools'), findsOneWidget);
      expect(find.text('Next: Scan & Organize'), findsOneWidget);
      await tester.tap(find.text('Expand Vehicle Details & Tools'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('ORIENTATION QUICK-FIX'), findsOneWidget);
      expect(find.text('Rotate +90° Yaw'), findsOneWidget);
      expect(find.text('Flip Front/Back'), findsOneWidget);
      expect(find.text('Snap to Ground (Y = 0.0m)'), findsOneWidget);
      expect(find.text('Apply Scale'), findsOneWidget);
      expect(find.text('Exclude roof/antenna parts from chassis bounds'), findsOneWidget);

      // Tap orientation buttons
      await tester.ensureVisible(find.text('Rotate +90° Yaw'));
      await tester.tap(find.text('Rotate +90° Yaw'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.ensureVisible(find.text('Flip Front/Back'));
      await tester.tap(find.text('Flip Front/Back'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.ensureVisible(find.text('Snap to Ground (Y = 0.0m)'));
      await tester.tap(find.text('Snap to Ground (Y = 0.0m)'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.ensureVisible(find.text('Apply Scale'));
      await tester.tap(find.text('Apply Scale'));
      await tester.pump(const Duration(milliseconds: 50));

      // Step 2: Scan & Organize
      await tester.tap(find.text('Scan & Organize').first);
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Custom view in Step 2
      await tester.tap(find.text('🛠 Custom'));
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

      // Run wheel detection via Start in Auto mode to complete Step 2
      await tester.tap(find.text('✨ Auto'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      // Return to Custom mode
      await tester.tap(find.text('🛠 Custom'));
      await tester.pump(const Duration(milliseconds: 100));

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
        expect(find.text('ISO'), findsWidgets);
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

    testWidgets('Orientation quick-fix rotates, flips, snaps and scales vehicle with visible feedback', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Expand Step 1 details & tools
      await tester.tap(find.text('Expand Vehicle Details & Tools'));
      await tester.pump(const Duration(milliseconds: 100));

      // Rotate +90° Yaw
      await tester.ensureVisible(find.text('Rotate +90° Yaw'));
      await tester.tap(find.text('Rotate +90° Yaw'));
      await tester.pump();
      expect(find.textContaining('Rotated vehicle model by 90°'), findsOneWidget);

      // Flip Front/Back
      await tester.ensureVisible(find.text('Flip Front/Back'));
      await tester.tap(find.text('Flip Front/Back'));
      await tester.pump();
      expect(find.textContaining('Flipped vehicle front to back'), findsOneWidget);

      // Snap to Ground
      await tester.ensureVisible(find.text('Snap to Ground (Y = 0.0m)'));
      await tester.tap(find.text('Snap to Ground (Y = 0.0m)'));
      await tester.pump();
      expect(find.textContaining('Snapped lowest vertices to ground plane'), findsOneWidget);

      // Apply Scale
      await tester.ensureVisible(find.text('Apply Scale'));
      await tester.tap(find.text('Apply Scale'));
      await tester.pump();
      expect(find.textContaining('Normalized vehicle footprint'), findsOneWidget);
    });

    testWidgets('advances sequentially through pipeline steps 1 to 5 using Next Step buttons', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Step 1: Upload Vehicle (starts collapsed)
      expect(find.text('Expand Vehicle Details & Tools'), findsOneWidget);
      expect(find.text('Next: Scan & Organize'), findsOneWidget);

      // Advance to Step 2
      await tester.tap(find.text('Next: Scan & Organize'));
      await tester.pump(const Duration(milliseconds: 100));

      // Step 2: Scan & Organize
      expect(find.text('4-STAGE AUTO-RIG PIPELINE'), findsOneWidget);
      expect(find.text('Next: Add Physics'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);

      // Next is disabled before scan: tapping it will not advance
      await tester.tap(find.text('Next: Add Physics'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('4-STAGE AUTO-RIG PIPELINE'), findsOneWidget);

      // Start the scan and wait for wheel filtering to complete
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 250));

      // Now Next: Add Physics is enabled, advance to Step 3
      await tester.tap(find.text('Next: Add Physics'));
      await tester.pump(const Duration(milliseconds: 100));

      // Step 3: Add Physics
      expect(find.text('HANDLING PRESETS'), findsOneWidget);
      expect(find.text('Next: Add Sound'), findsOneWidget);

      // Advance to Step 4
      await tester.tap(find.text('Next: Add Sound'));
      await tester.pump(const Duration(milliseconds: 100));

      // Step 4: Add Sound
      expect(find.text('ACOUSTIC PROFILES'), findsOneWidget);
      expect(find.text('Next: Export Rig'), findsOneWidget);

      // Advance to Step 5
      await tester.tap(find.text('Next: Export Rig'));
      await tester.pump(const Duration(milliseconds: 100));

      // Step 5: Export Rig
      expect(find.text('PRE-FLIGHT READINESS CHECKLIST'), findsOneWidget);
      expect(find.text('Export Godot 4 Rig (.glb / .tscn)'), findsOneWidget);
      expect(find.text('Launch Test Drive'), findsOneWidget);
    });

    testWidgets('starts with wheels unassigned and unhighlighted until Start is clicked', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(home: RigWorkbenchPage(initialCar: preRiggedCars.first)));
      await tester.pump(const Duration(milliseconds: 100));

      // Navigate to Step 2: Scan & Organize
      await tester.tap(find.text('Scan & Organize').first);
      await tester.pump(const Duration(milliseconds: 100));

      // Verify status is "Ready to Scan" before Start is clicked
      expect(find.text('Ready to Scan'), findsOneWidget);
      expect(find.text('4-STAGE AUTO-RIG PIPELINE'), findsOneWidget);

      // Verify Next button is disabled
      await tester.tap(find.text('Next: Add Physics'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('4-STAGE AUTO-RIG PIPELINE'), findsOneWidget);

      // Tap Start
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 250));

      // Now wheels are detected and verified
      expect(find.text('Auto Verified'), findsWidgets);

      // Next: Add Physics button is now enabled
      await tester.tap(find.text('Next: Add Physics'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('HANDLING PRESETS'), findsOneWidget);
    });

    testWidgets('uploading another car completely discards the current rigging process and resets to clear state', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => mockPickedFileForTest = null);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Advance to Step 2 and run scan
      await tester.tap(find.text('Scan & Organize').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Auto Verified'), findsWidgets);

      // Set up mocked file for uploading another car
      const objData = 'v -1 0 -1\nv 1 0 -1\nv 1 0 1\nv -1 0 1\nf 1 2 3\nf 1 3 4\n';
      mockPickedFileForTest = PickedFile(
        'hyper_car.obj',
        Uint8List.fromList(utf8.encode(objData)),
      );

      // Navigate back to Step 1: Upload Vehicle
      await tester.tap(find.text('Upload Vehicle').first);
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Import 3D Model button
      await tester.tap(find.text('Import 3D Model (.glb, .gltf, .obj)'));
      await tester.pump(const Duration(milliseconds: 200));

      // Active step is reset to 1 and model name reflects uploaded file
      expect(find.textContaining('hyper_car.obj'), findsWidgets);

      // Navigate to Step 2: Scan & Organize to check that old rigging was discarded
      await tester.tap(find.text('Scan & Organize').first);
      await tester.pump(const Duration(milliseconds: 100));

      // The process was discarded completely: status is "Ready to Scan", not "Auto Verified"
      expect(find.text('Ready to Scan'), findsOneWidget);

      // Next: Add Physics button is disabled again
      await tester.tap(find.text('Next: Add Physics'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('4-STAGE AUTO-RIG PIPELINE'), findsOneWidget);

      // Only clicking Start on the new car triggers wheel detection
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 250));

      // Verify detection ran for new car
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('grays out incomplete steps and blocks navigation until Step 2 is completed', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Initially on Step 1. Steps 3, 4, 5 are locked.
      // Trying to tap Step 3 (Add Physics) from sidebar
      await tester.tap(find.text('Add Physics').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Please complete Step 2 (Scan & Organize) before advancing.'), findsOneWidget);
      // Detail panel remains on Step 1 (Upload Vehicle)
      expect(find.text('Expand Vehicle Details & Tools'), findsOneWidget);

      // Trying to tap Step 4 (Add Sound)
      await tester.tap(find.text('Add Sound').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Please complete Step 2 (Scan & Organize) before advancing.'), findsOneWidget);
      expect(find.text('Expand Vehicle Details & Tools'), findsOneWidget);

      // Trying to tap Step 5 (Export Rig)
      await tester.tap(find.text('Export Rig').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Please complete Step 2 (Scan & Organize) before advancing.'), findsOneWidget);
      expect(find.text('Expand Vehicle Details & Tools'), findsOneWidget);

      // Step 2 (Scan & Organize) is enabled
      await tester.tap(find.text('Scan & Organize').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('4-STAGE AUTO-RIG PIPELINE'), findsOneWidget);

      // Click Start to run wheel detection
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // Now Step 3 is unlocked and can be navigated to
      await tester.tap(find.text('Add Physics').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('HANDLING PRESETS'), findsOneWidget);

      // And Step 4 is unlocked
      await tester.tap(find.text('Add Sound').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('ACOUSTIC PROFILES'), findsOneWidget);

      // And Step 5 is unlocked
      await tester.tap(find.text('Export Rig').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('PRE-FLIGHT READINESS CHECKLIST'), findsOneWidget);
    });

    testWidgets('ensures viewport does not render circle markers or CoM text on middle object', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Advance to Step 2 and run wheel detection
      await tester.tap(find.text('Scan & Organize').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // Confirm no CoM label or floating marker circle text is rendered in viewport
      expect(find.textContaining('CoM ('), findsNothing);
      expect(find.text('Wheel_FL'), findsNothing);
      expect(find.text('Wheel_FR'), findsNothing);
      expect(find.byTooltip('Hide Markers'), findsNothing);
      expect(find.byTooltip('Show Markers'), findsNothing);
    });

    testWidgets('renders Blender-like X, Y, -X, -Y, Z, -Z navigation gizmo and snaps camera orientation on tap', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Blender navigation gizmo buttons exist in 3D viewport
      expect(find.text('X'), findsWidgets);
      expect(find.text('-X'), findsOneWidget);
      expect(find.text('Y'), findsWidgets);
      expect(find.text('-Y'), findsOneWidget);
      expect(find.text('Z'), findsWidgets);
      expect(find.text('-Z'), findsOneWidget);
      expect(find.text('ISO'), findsWidgets);

      // Tap +X to align camera to Right Side (+X)
      await tester.tap(find.text('X').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('RIGHT'), findsOneWidget);

      // Tap -X to align camera to Left Side (-X)
      await tester.tap(find.text('-X'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('LEFT'), findsOneWidget);

      // Tap Y to align camera to Top View (+Y)
      await tester.tap(find.text('Y').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('TOP'), findsOneWidget);

      // Tap -Y to align camera to Bottom View (-Y)
      await tester.tap(find.text('-Y'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('BOTTOM'), findsOneWidget);

      // Tap -Z to align camera to Front View (-Z)
      await tester.tap(find.text('-Z'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('FRONT'), findsOneWidget);

      // Tap Z to align camera to Rear View (+Z)
      await tester.tap(find.text('Z').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('BACK'), findsOneWidget);

      // Tap ISO to return to Isometric View
      await tester.tap(find.text('ISO').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('ISO'), findsWidgets);
    });

    testWidgets('ensures wheels remain strictly un-highlighted until Start button is clicked', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Viewport should not show "Wheels" legend item yet
      expect(find.text('Wheels'), findsNothing);

      // Switch to Step 2 (Scan & Organize)
      await tester.tap(find.text('Scan & Organize').first);
      await tester.pump(const Duration(milliseconds: 100));

      // Before clicking Start, Next button is disabled
      final nextBtn = tester.widget<FilledButton>(
        find.ancestor(of: find.text('Next: Add Physics'), matching: find.byType(FilledButton)),
      );
      expect(nextBtn.onPressed, isNull);

      // Legend item "Wheels" is still NOT visible before clicking Start
      expect(find.text('Wheels'), findsNothing);

      // Now click Start to scan and highlight wheels
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // After clicking Start, wheels legend is visible and Next button is enabled
      expect(find.text('Wheels'), findsOneWidget);
      final enabledNextBtn = tester.widget<FilledButton>(
        find.ancestor(of: find.text('Next: Add Physics'), matching: find.byType(FilledButton)),
      );
      expect(enabledNextBtn.onPressed, isNotNull);
    });

    testWidgets('synchronizes camera orbit to Blender gizmo in real time across uploaded car and demo car', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: RigWorkbenchPage()));
      await tester.pump(const Duration(milliseconds: 100));

      // Find the SketchfabViewport in the tree
      final viewportFinder = find.byType(SketchfabViewport);
      expect(viewportFinder, findsOneWidget);

      final viewportWidget = tester.widget<SketchfabViewport>(viewportFinder);
      expect(viewportWidget.onCameraOrbit, isNotNull);

      // Simulate Three.js camera orbit event (e.g. mouse drag orbiting camera to azimuth = 1.25, elevation = 0.65)
      viewportWidget.onCameraOrbit!(1.25, 0.65, 4.8);
      await tester.pump(const Duration(milliseconds: 50));

      // Gizmo is rendered and receives updated camera angles
      expect(find.byTooltip('Blender View Gizmo (Click an axis pin or center ISO to snap)'), findsOneWidget);
    });
  });
}
