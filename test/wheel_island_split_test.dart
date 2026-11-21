import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:rig_car/model_data.dart';

void main() {
  test('merged mesh splits detected wheels into dedicated scene nodes', () {
    const hubs = <String, Vec3>{
      'FL': Vec3(-0.9, 0.35, -1.35),
      'FR': Vec3(0.9, 0.35, -1.35),
      'RL': Vec3(-0.9, 0.35, 1.35),
      'RR': Vec3(0.9, 0.35, 1.35),
    };

    final verts = <Vec3>[];
    final tris = <Triangle>[];

    // Body triangle well away from every hub.
    verts.addAll(const [Vec3(0, 1.4, 0), Vec3(0.2, 1.4, 0), Vec3(0, 1.4, 0.2)]);
    tris.add(Triangle(0, 1, 2, const Color(0xFFFF0000)));

    hubs.forEach((corner, hub) {
      for (var i = 0; i < 12; i++) {
        final angle = i * 2 * pi / 12;
        final base = verts.length;
        verts.addAll([
          Vec3(hub.x, hub.y + 0.15 * cos(angle), hub.z + 0.15 * sin(angle)),
          Vec3(hub.x, hub.y + 0.15 * cos(angle + 0.4),
              hub.z + 0.15 * sin(angle + 0.4)),
          Vec3(hub.x, hub.y + 0.15 * cos(angle + 0.8),
              hub.z + 0.15 * sin(angle + 0.8)),
        ]);
        tris.add(Triangle(base, base + 1, base + 2));
      }
    });

    final model = ParsedModel(
      fileName: 'merged.glb',
      nodes: [
        SceneNode(
          index: 0,
          name: 'Car_Body',
          localTransform: Mat4.identity(),
          meshIndex: 0,
          childIndices: const [],
          parentIndex: null,
        ),
      ],
      meshes: [
        MeshData(
          index: 0,
          name: 'Car_Body',
          vertices: verts,
          edges: const [],
          triangles: tris,
          bbox: BBox.fromPoints(verts),
        ),
      ],
      instances: [
        MeshInstance(
          nodeIndex: 0,
          meshIndex: 0,
          worldVertices: verts,
          edges: const [],
          triangles: tris,
          worldBBox: BBox.fromPoints(verts),
        ),
      ],
      rootNodeIndices: const [0],
      worldBBox: BBox.fromPoints(verts),
    );

    final wheels = <String, DetectedWheel>{
      for (final entry in hubs.entries)
        entry.key: DetectedWheel(
          nodeIndex: 0,
          nodeName: 'Car_Body',
          worldPosition: entry.value,
          confidence: 1.0,
          axle: entry.key.startsWith('F') ? 'front' : 'rear',
          side: entry.key.endsWith('L') ? 'left' : 'right',
        ),
    };

    final result = model.splitWheelIslands(wheels);

    expect(result.wheelNodeIndices.length, 4);
    const expectedNames = {
      'FL': 'Left Front Wheel',
      'FR': 'Right Front Wheel',
      'RL': 'Left Rear Wheel',
      'RR': 'Right Rear Wheel',
    };
    for (final entry in expectedNames.entries) {
      final nodeIndex = result.wheelNodeIndices[entry.key];
      expect(nodeIndex, isNotNull);
      expect(result.model.nodes[nodeIndex!].name, entry.value);
    }
    // The merged remainder is the vehicle body.
    expect(result.model.nodes[0].name, 'Body');

    final wheelInstances = result.model.instances
        .where((i) => result.wheelNodeIndices.containsValue(i.nodeIndex))
        .toList();
    expect(wheelInstances.length, 4);
    for (final inst in wheelInstances) {
      expect(inst.triangles.length, 12);
    }

    final body = result.model.instances
        .where((i) => i.nodeIndex == 0)
        .toList()
        .single;
    expect(body.triangles.length, 1);
    expect(result.model.nodes[0].childIndices.length, 4);

    // The rigged OBJ is the final exported vehicle: Body plus four named wheels.
    final obj = result.model.toRiggedObj();
    expect(obj, contains('o Body'));
    expect(obj, contains('o Left_Front_Wheel'));
    expect(obj, contains('o Right_Front_Wheel'));
    expect(obj, contains('o Left_Rear_Wheel'));
    expect(obj, contains('o Right_Rear_Wheel'));
    expect(obj.indexOf('o Body'), lessThan(obj.indexOf('o Left_Front_Wheel')));

    // The rigged GLB must carry the colours sampled at import instead of one
    // flat grey, so paint, glass and tyres survive the export.
    final glb = result.model.toRiggedGlb();
    final glbData = ByteData.sublistView(glb);
    final jsonLength = glbData.getUint32(12, Endian.little);
    final json = jsonDecode(
      utf8.decode(glb.sublist(20, 20 + jsonLength)),
    ) as Map<String, dynamic>;

    final attributes =
        ((json['meshes'] as List)[0]['primitives'] as List)[0]['attributes']
            as Map<String, dynamic>;
    expect(attributes.containsKey('COLOR_0'), isTrue);

    final colorAccessor =
        (json['accessors'] as List)[attributes['COLOR_0'] as int]
            as Map<String, dynamic>;
    expect(colorAccessor['type'], 'VEC4');
    expect(colorAccessor['componentType'], 5121);
    expect(colorAccessor['normalized'], isTrue);

    final colorView =
        (json['bufferViews'] as List)[colorAccessor['bufferView'] as int]
            as Map<String, dynamic>;
    final binStart = 20 + jsonLength + 8;
    final colors = glb.sublist(
      binStart + (colorView['byteOffset'] as int),
      binStart +
          (colorView['byteOffset'] as int) +
          (colorAccessor['count'] as int) * 4,
    );
    // Vertex 0 is shared by no other triangle, so it keeps the sampled colour
    // exactly instead of the neutral grey used when a mesh carries no colours.
    expect(colors.sublist(0, 4), [255, 0, 0, 255]);
  });

  test('separate wheel nodes are left untouched', () {
    final verts = <Vec3>[
      const Vec3(0, 1, 0),
      const Vec3(0.1, 1, 0),
      const Vec3(0, 1, 0.1),
    ];
    final model = ParsedModel(
      fileName: 'split.glb',
      nodes: [
        SceneNode(
          index: 0,
          name: 'Wheel_FL',
          localTransform: Mat4.identity(),
          meshIndex: 0,
          childIndices: const [],
          parentIndex: null,
        ),
      ],
      meshes: [
        MeshData(
          index: 0,
          name: 'Wheel_FL',
          vertices: verts,
          edges: const [],
          triangles: [Triangle(0, 1, 2)],
          bbox: BBox.fromPoints(verts),
        ),
      ],
      instances: [
        MeshInstance(
          nodeIndex: 0,
          meshIndex: 0,
          worldVertices: verts,
          edges: const [],
          triangles: [Triangle(0, 1, 2)],
          worldBBox: BBox.fromPoints(verts),
        ),
      ],
      rootNodeIndices: const [0],
      worldBBox: BBox.fromPoints(verts),
    );

    final result = model.splitWheelIslands(const {});
    expect(result.wheelNodeIndices, isEmpty);
    expect(identical(result.model, model), isTrue);
  });

  test('multi-node car with dedicated wheel nodes leaves body mesh untouched', () {
    const hubs = <String, Vec3>{
      'FL': Vec3(-0.9, 0.35, -1.35),
      'FR': Vec3(0.9, 0.35, -1.35),
      'RL': Vec3(-0.9, 0.35, 1.35),
      'RR': Vec3(0.9, 0.35, 1.35),
    };

    // Body mesh with some triangles near wheel hubs (e.g. inner fender liner)
    final bodyVerts = <Vec3>[
      const Vec3(0, 1.4, 0),
      const Vec3(0.2, 1.4, 0),
      const Vec3(0, 1.4, 0.2),
      // Fender liner near FL hub
      const Vec3(-0.9, 0.40, -1.35),
      const Vec3(-0.88, 0.42, -1.35),
      const Vec3(-0.9, 0.45, -1.33),
    ];
    final bodyTris = [
      Triangle(0, 1, 2),
      Triangle(3, 4, 5),
    ];

    // Dedicated wheel meshes in separate nodes (nodes 1..4)
    final nodes = <SceneNode>[
      SceneNode(
        index: 0,
        name: 'Car_Body',
        localTransform: Mat4.identity(),
        meshIndex: 0,
        childIndices: const [1, 2, 3, 4],
        parentIndex: null,
      ),
    ];
    final instances = <MeshInstance>[
      MeshInstance(
        nodeIndex: 0,
        meshIndex: 0,
        worldVertices: bodyVerts,
        edges: const [],
        triangles: bodyTris,
        worldBBox: BBox.fromPoints(bodyVerts),
      ),
    ];

    var nIdx = 1;
    final wheels = <String, DetectedWheel>{};
    hubs.forEach((corner, hub) {
      final wVerts = [
        hub,
        Vec3(hub.x + 0.1, hub.y + 0.1, hub.z),
        Vec3(hub.x, hub.y + 0.1, hub.z + 0.1),
      ];
      nodes.add(
        SceneNode(
          index: nIdx,
          name: 'Dedicated_Wheel_$corner',
          localTransform: Mat4.identity(),
          meshIndex: nIdx,
          childIndices: const [],
          parentIndex: 0,
        ),
      );
      instances.add(
        MeshInstance(
          nodeIndex: nIdx,
          meshIndex: nIdx,
          worldVertices: wVerts,
          edges: const [],
          triangles: [Triangle(0, 1, 2)],
          worldBBox: BBox.fromPoints(wVerts),
        ),
      );
      wheels[corner] = DetectedWheel(
        nodeIndex: nIdx,
        nodeName: 'Dedicated_Wheel_$corner',
        worldPosition: hub,
        confidence: 1.0,
        axle: corner.startsWith('F') ? 'front' : 'rear',
        side: corner.endsWith('L') ? 'left' : 'right',
        spinNodeIndices: [nIdx],
        partNodeIndices: [nIdx],
      );
      nIdx++;
    });

    final model = ParsedModel(
      fileName: 'multinode.glb',
      nodes: nodes,
      meshes: const [],
      instances: instances,
      rootNodeIndices: const [0],
      worldBBox: BBox.fromPoints(bodyVerts),
    );

    // splitWheelIslands should detect that all 4 wheels live in dedicated nodes (1..4)
    // and NOT slice the fender liner (Triangle 3,4,5) out of body node 0!
    final result = model.splitWheelIslands(wheels);
    expect(result.wheelNodeIndices, isEmpty);
    expect(identical(result.model, model), isTrue);
  });
}
