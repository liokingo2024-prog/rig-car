import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Color, Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:rig_car/glb_parser.dart';
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

  test('toRiggedGlb preserves embedded textures, samplers, materials, and UVs', () {
    final pngBytes = Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, //
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, //
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, //
      0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, //
      0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, //
      0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

    final verts = <Vec3>[
      const Vec3(0, 0, 0),
      const Vec3(1, 0, 0),
      const Vec3(0, 1, 0),
    ];
    final uvs = <Offset>[
      const Offset(0.0, 0.0),
      const Offset(1.0, 0.0),
      const Offset(0.0, 1.0),
    ];
    final tris = <Triangle>[const Triangle(0, 1, 2)];

    final model = ParsedModel(
      fileName: 'textured_car.glb',
      nodes: [
        SceneNode(
          index: 0,
          name: 'Body',
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
          vertices: verts,
          edges: const [],
          triangles: tris,
          bbox: BBox.fromPoints(verts),
          uvs: uvs,
          materialIndex: 0,
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
          uvs: uvs,
          materialIndex: 0,
        ),
      ],
      rootNodeIndices: const [0],
      worldBBox: BBox.fromPoints(verts),
      gltfAssets: GltfMaterialAssets(
        materials: [
          <String, dynamic>{
            'name': 'RedPaint',
            'pbrMetallicRoughness': <String, dynamic>{
              'baseColorTexture': <String, dynamic>{'index': 0},
              'metallicFactor': 0.8,
              'roughnessFactor': 0.2,
            },
          },
        ],
        textures: [
          <String, dynamic>{'source': 0, 'sampler': 0},
        ],
        samplers: [
          <String, dynamic>{'magFilter': 9729, 'minFilter': 9987},
        ],
        images: [
          GltfImageAsset(
            bytes: pngBytes,
            mimeType: 'image/png',
            name: 'paint_albedo',
          ),
        ],
      ),
    );

    final glb = model.toRiggedGlb();
    final roundTripped = GlbParser.parseSync('exported.glb', glb);

    expect(roundTripped.gltfAssets, isNotNull);
    expect(roundTripped.gltfAssets!.materials.length, 1);
    expect(roundTripped.gltfAssets!.materials[0]['name'], 'RedPaint');
    expect(roundTripped.gltfAssets!.textures.length, 1);
    expect(roundTripped.gltfAssets!.samplers.length, 1);
    expect(roundTripped.gltfAssets!.images.length, 1);
    expect(roundTripped.gltfAssets!.images[0]!.mimeType, 'image/png');
    expect(roundTripped.gltfAssets!.images[0]!.bytes, pngBytes);
    expect(roundTripped.instances.single.uvs, isNotNull);
    expect(roundTripped.instances.single.uvs!.length, 3);
    expect(roundTripped.instances.single.materialIndex, 0);

    final glbData = ByteData.sublistView(glb);
    final jsonLength = glbData.getUint32(12, Endian.little);
    final json = jsonDecode(
      utf8.decode(glb.sublist(20, 20 + jsonLength)),
    ) as Map<String, dynamic>;
    final attrs = ((json['meshes'] as List)[0]['primitives'] as List)[0]
        ['attributes'] as Map<String, dynamic>;
    expect(attrs.containsKey('TEXCOORD_0'), isTrue);
    expect(attrs.containsKey('COLOR_0'), isFalse);
  });

  test('glass materials are lifted out of near-invisibility on import', () {
    // Exports routinely author windows at 2-6% opacity, which used to paint
    // them as holes in the body instead of tinted glass.
    final glass = _singleTriangleModel({
      'name': 'Glass',
      'alphaMode': 'BLEND',
      'pbrMetallicRoughness': {
        'baseColorFactor': [0.1, 0.15, 0.2, 0.02],
      },
    });
    final glassColor = glass.instances.single.triangles.single.color!;
    final glassAlpha = (glassColor.toARGB32() >> 24) & 0xFF;
    expect(glassAlpha, greaterThanOrEqualTo(160));
    expect(glassAlpha, lessThanOrEqualTo(215));
    expect((glassColor.toARGB32() >> 16) & 0xFF, lessThan(60));

    // A colourless pane picks up the cockpit tint rather than staying white.
    final clear = _singleTriangleModel({
      'name': 'window_glass',
      'alphaMode': 'BLEND',
      'pbrMetallicRoughness': {
        'baseColorFactor': [1.0, 1.0, 1.0, 0.05],
      },
    });
    final clearArgb = clear.instances.single.triangles.single.color!.toARGB32();
    expect((clearArgb >> 16) & 0xFF, lessThan(80));
    expect((clearArgb >> 24) & 0xFF, greaterThanOrEqualTo(160));

    // Non-glass blended surfaces (light cones, glow planes) stay subtle.
    final glow = _singleTriangleModel({
      'name': 'Glow',
      'alphaMode': 'BLEND',
      'pbrMetallicRoughness': {
        'baseColorFactor': [1.0, 0.4, 0.2, 1.0],
      },
    });
    final glowAlpha =
        (glow.instances.single.triangles.single.color!.toARGB32() >> 24) &
            0xFF;
    expect(glowAlpha, lessThanOrEqualTo(120));
  });

  test('async import reports staged progress for the loading overlay', () async {
    final stages = <String>[];
    final progress = <double>[];
    final model = await GlbParser.parse(
      'glass.glb',
      _singleTriangleGlb({
        'name': 'Paint',
        'pbrMetallicRoughness': {
          'baseColorFactor': [0.8, 0.1, 0.1, 1.0],
        },
      }),
      onProgress: (stage, value) {
        stages.add(stage);
        progress.add(value);
      },
    );

    expect(model.instances.single.triangles.length, 1);
    expect(stages, isNotEmpty);
    expect(stages.first, contains('Unpacking GLB'));
    expect(stages.last, contains('Finalizing'));
    // Progress must move forwards and stay inside 0-1 for the overlay bar.
    for (var i = 0; i < progress.length; i++) {
      expect(progress[i], inInclusiveRange(0.0, 1.0));
      // Tolerate double rounding in the stage maths (0.3 vs 0.30000000000000004)
      // while still failing on a bar that visibly jumps backwards.
      if (i > 0) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1] - 1e-6));
      }
    }
  });
}

/// Minimal one-triangle binary glTF carrying the supplied material.
ParsedModel _singleTriangleModel(Map<String, dynamic> material) =>
    GlbParser.parseSync('glass.glb', _singleTriangleGlb(material));

Uint8List _singleTriangleGlb(Map<String, dynamic> material) {
  final verts = Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]);
  final indices = Int32List.fromList([0, 1, 2]);
  final bin = BytesBuilder()
    ..add(verts.buffer.asUint8List())
    ..add(indices.buffer.asUint8List());
  final json = {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'nodes': [
      {'mesh': 0, 'name': 'Body'},
    ],
    'materials': [material],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0},
            'indices': 1,
            'material': 0,
          },
        ],
      },
    ],
    'accessors': [
      {'bufferView': 0, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
      {'bufferView': 1, 'componentType': 5125, 'count': 3, 'type': 'SCALAR'},
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': 36, 'byteLength': 12},
    ],
    'buffers': [
      {'byteLength': 48},
    ],
  };
  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPad = (4 - jsonBytes.length % 4) % 4;
  final binBytes = bin.takeBytes();
  final total = 12 + 8 + jsonBytes.length + jsonPad + 8 + binBytes.length;
  final header = ByteData(12)
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, total, Endian.little);
  final jsonChunk = ByteData(8)
    ..setUint32(0, jsonBytes.length + jsonPad, Endian.little)
    ..setUint32(4, 0x4E4F534A, Endian.little);
  final binChunk = ByteData(8)
    ..setUint32(0, binBytes.length, Endian.little)
    ..setUint32(4, 0x004E4942, Endian.little);
  final glb = BytesBuilder()
    ..add(header.buffer.asUint8List())
    ..add(jsonChunk.buffer.asUint8List())
    ..add(jsonBytes)
    ..add(List<int>.filled(jsonPad, 0x20))
    ..add(binChunk.buffer.asUint8List())
    ..add(binBytes);
  return glb.takeBytes();
}
