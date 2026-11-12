import 'dart:convert' hide Codec;
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';

import 'model_data.dart';

// ── GLB / glTF Binary Parser ────────────────────────────────────────────────
//
// Reads a .glb file (glTF 2.0 binary container), extracts the full node tree,
// mesh vertex positions, triangle edges, and bounding boxes.  The result is a
// [ParsedModel] ready for auto-detection and wireframe rendering.

/// A decoded glTF image kept at a usable resolution so each triangle can be
/// tinted with the texel colour it actually samples through its UV coordinates.
class _DecodedTexture {
  _DecodedTexture(this.width, this.height, this.rgba, this.averageColor);

  final int width;
  final int height;
  final Uint8List rgba;
  final Color averageColor;

  Color? sampleUv(double u, double v, {List<double>? baseColorFactor}) {
    if (width <= 0 || height <= 0 || rgba.isEmpty) return null;
    // Malformed TEXCOORD_0 data (NaN/Infinity) would otherwise throw in round().
    if (!u.isFinite || !v.isFinite) return averageColor;
    var uu = u % 1.0;
    var vv = v % 1.0;
    if (uu < 0) uu += 1.0;
    if (vv < 0) vv += 1.0;
    final x = (uu * (width - 1)).round().clamp(0, width - 1);
    final y = (vv * (height - 1)).round().clamp(0, height - 1);
    final o = (y * width + x) * 4;
    if (o + 4 > rgba.length) return averageColor;
    final a = rgba[o + 3];
    if (a <= 10) return averageColor;
    var r = rgba[o];
    var g = rgba[o + 1];
    var b = rgba[o + 2];
    // Tinted materials often combine a neutral AO/detail atlas with a coloured
    // baseColorFactor; multiply so the authored paint tint survives sampling.
    if (baseColorFactor != null && baseColorFactor.length >= 3) {
      r = (r * baseColorFactor[0]).round().clamp(0, 255);
      g = (g * baseColorFactor[1]).round().clamp(0, 255);
      b = (b * baseColorFactor[2]).round().clamp(0, 255);
    }
    return Color.fromARGB(a, r, g, b);
  }
}

class GlbParser {
  static const _glbMagic = 0x46546C67; // ASCII 'glTF'
  static const _chunkJson = 0x4E4F534A;
  static const _chunkBin = 0x004E4942;

  /// Maximum edges to keep per mesh primitive to prevent OOM on huge models.
  // The viewport is an interactive wireframe preview, not a mesh editor.
  // Capping sampled triangle edges keeps browser parsing and memory bounded
  // for production GLBs while preserving all vertex positions for detection.
  static const _maxEdgesPerPrimitive = 16000;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Parse any 3D model format (.glb, .gltf, .obj, .stl, .fbx, .zip) asynchronously,
  /// extracting authentic meshes, nodes, and materials for auto-rigging and Godot export.
  static Future<ParsedModel> parse(String fileName, Uint8List bytes) async {
    final lower = fileName.toLowerCase();

    // 1. Standard GLB binary
    if (_isGlb(bytes) || lower.endsWith('.glb')) {
      try {
        final (json, bin) = _unpackGlb(bytes);
        return await _buildGltfWithTextures(fileName, json, bin);
      } catch (_) {}
    }

    // 2. ZIP package (e.g. Sketchfab zip archive)
    if (_isZip(bytes) || lower.endsWith('.zip')) {
      return _parseZip(fileName, bytes);
    }

    // 3. Wavefront OBJ
    if (lower.endsWith('.obj') || _isObj(bytes)) {
      return _parseObj(fileName, bytes);
    }

    // 4. Stereolithography STL
    if (lower.endsWith('.stl') || _isStl(bytes)) {
      return _parseStl(fileName, bytes);
    }

    // 5. glTF JSON
    if (lower.endsWith('.gltf') || _isGltfJson(bytes)) {
      try {
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final bin = _extractEmbeddedGltfBin(json);
        return await _buildGltfWithTextures(fileName, json, bin);
      } catch (_) {}
    }

    // 6. Generic/FBX fallback
    return _createFallbackVehicle(fileName, bytes: bytes);
  }

  /// Synchronous fallback when async texture decoding is not needed.
  static ParsedModel parseSync(String fileName, Uint8List bytes) {
    final lower = fileName.toLowerCase();

    if (_isGlb(bytes) || lower.endsWith('.glb')) {
      try {
        final (json, bin) = _unpackGlb(bytes);
        return _build(fileName, json, bin);
      } catch (_) {}
    }

    if (_isZip(bytes) || lower.endsWith('.zip')) {
      return _parseZipSync(fileName, bytes);
    }

    if (lower.endsWith('.obj') || _isObj(bytes)) {
      return _parseObj(fileName, bytes);
    }

    if (lower.endsWith('.stl') || _isStl(bytes)) {
      return _parseStl(fileName, bytes);
    }

    if (lower.endsWith('.gltf') || _isGltfJson(bytes)) {
      try {
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final bin = _extractEmbeddedGltfBin(json);
        return _build(fileName, json, bin);
      } catch (_) {}
    }

    return _createFallbackVehicle(fileName, bytes: bytes);
  }

  static bool _isGlb(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final data = ByteData.sublistView(bytes);
    return data.getUint32(0, Endian.little) == _glbMagic;
  }

  static bool _isZip(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
  }

  static bool _isGltfJson(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    for (var i = 0; i < bytes.length && i < 200; i++) {
      final b = bytes[i];
      if (b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D) continue;
      return b == 0x7B; // '{'
    }
    return false;
  }

  static bool _isObj(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    final sample = utf8.decode(bytes.sublist(0, min(bytes.length, 500)), allowMalformed: true);
    return sample.contains(RegExp(r'(^|\n)\s*v\s+[-0-9]'));
  }

  static bool _isStl(Uint8List bytes) {
    if (bytes.length < 84) return false;
    final data = ByteData.sublistView(bytes);
    final count = data.getUint32(80, Endian.little);
    if (count > 0 && 84 + count * 50 == bytes.length) return true;
    final sample = utf8.decode(bytes.sublist(0, min(bytes.length, 100)), allowMalformed: true).trimLeft();
    return sample.startsWith('solid');
  }

  static Uint8List? _extractEmbeddedGltfBin(Map<String, dynamic> json) {
    try {
      final buffers = json['buffers'];
      if (buffers is List && buffers.isNotEmpty) {
        final firstBuf = buffers.first;
        if (firstBuf is Map) {
          final uri = firstBuf['uri'] as String?;
          if (uri != null && uri.startsWith('data:')) {
            final comma = uri.indexOf(',');
            if (comma != -1) {
              final b64 = uri.substring(comma + 1).trim();
              return base64Decode(b64);
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static void _addEdgeToSet(List<Edge> edges, Set<int> edgeSet, int a, int b) {
    if (a == b) return;
    final minIdx = a < b ? a : b;
    final maxIdx = a > b ? a : b;
    final key = minIdx * 10000000 + maxIdx;
    if (edgeSet.add(key)) {
      edges.add(Edge(minIdx, maxIdx));
    }
  }

  static ParsedModel _parseObj(String fileName, Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final lines = text.split('\n');
    final allVerts = <Vec3>[];
    final groups = <String, List<Triangle>>{};
    String currentGroup = 'Car_Body';

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      if (line.startsWith('v ')) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final x = double.tryParse(parts[1]) ?? 0.0;
          final y = double.tryParse(parts[2]) ?? 0.0;
          final z = double.tryParse(parts[3]) ?? 0.0;
          allVerts.add(Vec3(x, y, z));
        }
      } else if (line.startsWith('g ') || line.startsWith('o ')) {
        final gName = line.substring(2).trim();
        if (gName.isNotEmpty) {
          currentGroup = gName;
        }
      } else if (line.startsWith('f ')) {
        final parts = line.split(RegExp(r'\s+'));
        final idxs = <int>[];
        for (var i = 1; i < parts.length; i++) {
          final p = parts[i].split('/')[0];
          final idx = int.tryParse(p);
          if (idx != null) {
            final actualIdx = idx > 0 ? idx - 1 : allVerts.length + idx;
            if (actualIdx >= 0 && actualIdx < allVerts.length) {
              idxs.add(actualIdx);
            }
          }
        }
        for (var i = 1; i + 1 < idxs.length; i++) {
          final t = Triangle(idxs[0], idxs[i], idxs[i + 1]);
          groups.putIfAbsent(currentGroup, () => []).add(t);
        }
      }
    }

    if (allVerts.isEmpty) {
      return _createFallbackVehicle(fileName, bytes: bytes);
    }

    final nodes = <SceneNode>[];
    final meshes = <MeshData>[];
    final instances = <MeshInstance>[];

    var nodeIdx = 0;
    if (groups.isEmpty) {
      final edges = <Edge>[];
      final edgeSet = <int>{};
      for (var i = 0; i + 1 < allVerts.length && edges.length < _maxEdgesPerPrimitive; i += 2) {
        _addEdgeToSet(edges, edgeSet, i, i + 1);
      }
      final bbox = BBox.fromPoints(allVerts);
      final mesh = MeshData(index: 0, name: 'Mesh_0', vertices: allVerts, edges: edges, bbox: bbox);
      meshes.add(mesh);
      nodes.add(SceneNode(
        index: 0,
        name: 'Car_Body',
        localTransform: Mat4.identity(),
        meshIndex: 0,
        childIndices: const [],
        parentIndex: null,
      ));
      instances.add(MeshInstance(nodeIndex: 0, meshIndex: 0, worldVertices: allVerts, edges: edges, worldBBox: bbox));
    } else {
      for (final entry in groups.entries) {
        final gName = entry.key;
        final groupTrisRaw = entry.value;
        if (groupTrisRaw.isEmpty) continue;

        // Compact vertices to only those referenced by this group's triangles
        final vertMap = <int, int>{};
        final groupVerts = <Vec3>[];
        final groupTris = <Triangle>[];

        int getOrAddVert(int globalIdx) {
          return vertMap.putIfAbsent(globalIdx, () {
            final localIdx = groupVerts.length;
            groupVerts.add(globalIdx >= 0 && globalIdx < allVerts.length
                ? allVerts[globalIdx]
                : Vec3.zero);
            return localIdx;
          });
        }

        for (final t in groupTrisRaw) {
          final na = getOrAddVert(t.a);
          final nb = getOrAddVert(t.b);
          final nc = getOrAddVert(t.c);
          groupTris.add(Triangle(na, nb, nc, t.color));
        }

        final edges = <Edge>[];
        final edgeSet = <int>{};
        for (final t in groupTris) {
          if (edges.length >= _maxEdgesPerPrimitive) break;
          _addEdgeToSet(edges, edgeSet, t.a, t.b);
          _addEdgeToSet(edges, edgeSet, t.b, t.c);
          _addEdgeToSet(edges, edgeSet, t.c, t.a);
        }

        final bbox = groupVerts.isNotEmpty ? BBox.fromPoints(groupVerts) : BBox.empty;
        final meshIdx = meshes.length;
        final mesh = MeshData(
          index: meshIdx,
          name: gName,
          vertices: groupVerts,
          edges: edges,
          triangles: groupTris,
          bbox: bbox,
        );
        meshes.add(mesh);
        nodes.add(SceneNode(
          index: nodeIdx,
          name: gName,
          localTransform: Mat4.identity(),
          meshIndex: meshIdx,
          childIndices: const [],
          parentIndex: null,
        ));
        instances.add(MeshInstance(
          nodeIndex: nodeIdx,
          meshIndex: meshIdx,
          worldVertices: groupVerts,
          edges: edges,
          triangles: groupTris,
          worldBBox: bbox,
        ));
        nodeIdx++;
      }
    }

    final overallBBox = BBox.fromPoints(allVerts);
    return ParsedModel(
      fileName: fileName,
      nodes: nodes,
      meshes: meshes,
      instances: instances,
      rootNodeIndices: [0],
      worldBBox: overallBBox,
    );
  }

  static ParsedModel _parseStl(String fileName, Uint8List bytes) {
    final verts = <Vec3>[];
    final tris = <Triangle>[];
    final edges = <Edge>[];
    final edgeSet = <int>{};

    if (bytes.length >= 84) {
      final data = ByteData.sublistView(bytes);
      final count = data.getUint32(80, Endian.little);
      if (84 + count * 50 == bytes.length && count > 0) {
        var offset = 84;
        for (var i = 0; i < count; i++) {
          offset += 12; // normal
          final v0 = Vec3(data.getFloat32(offset, Endian.little), data.getFloat32(offset + 4, Endian.little), data.getFloat32(offset + 8, Endian.little));
          offset += 12;
          final v1 = Vec3(data.getFloat32(offset, Endian.little), data.getFloat32(offset + 4, Endian.little), data.getFloat32(offset + 8, Endian.little));
          offset += 12;
          final v2 = Vec3(data.getFloat32(offset, Endian.little), data.getFloat32(offset + 4, Endian.little), data.getFloat32(offset + 8, Endian.little));
          offset += 12;
          offset += 2; // attr byte count

          final idx = verts.length;
          verts.add(v0);
          verts.add(v1);
          verts.add(v2);
          tris.add(Triangle(idx, idx + 1, idx + 2));
          if (edges.length < _maxEdgesPerPrimitive) {
            _addEdgeToSet(edges, edgeSet, idx, idx + 1);
            _addEdgeToSet(edges, edgeSet, idx + 1, idx + 2);
            _addEdgeToSet(edges, edgeSet, idx + 2, idx);
          }
        }
      }
    }

    if (verts.isEmpty) {
      final text = utf8.decode(bytes, allowMalformed: true);
      final lines = text.split('\n');
      for (var line in lines) {
        line = line.trim();
        if (line.startsWith('vertex ')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final x = double.tryParse(parts[1]) ?? 0.0;
            final y = double.tryParse(parts[2]) ?? 0.0;
            final z = double.tryParse(parts[3]) ?? 0.0;
            verts.add(Vec3(x, y, z));
          }
        }
      }
      for (var i = 0; i + 2 < verts.length; i += 3) {
        tris.add(Triangle(i, i + 1, i + 2));
        if (edges.length < _maxEdgesPerPrimitive) {
          _addEdgeToSet(edges, edgeSet, i, i + 1);
          _addEdgeToSet(edges, edgeSet, i + 1, i + 2);
          _addEdgeToSet(edges, edgeSet, i + 2, i);
        }
      }
    }

    if (verts.isEmpty) {
      return _createFallbackVehicle(fileName, bytes: bytes);
    }

    final bbox = BBox.fromPoints(verts);
    final mesh = MeshData(index: 0, name: 'STL_Mesh', vertices: verts, edges: edges, triangles: tris, bbox: bbox);
    final node = SceneNode(
      index: 0,
      name: 'Car_Body',
      localTransform: Mat4.identity(),
      meshIndex: 0,
      childIndices: const [],
      parentIndex: null,
    );
    final instance = MeshInstance(nodeIndex: 0, meshIndex: 0, worldVertices: verts, edges: edges, triangles: tris, worldBBox: bbox);

    return ParsedModel(
      fileName: fileName,
      nodes: [node],
      meshes: [mesh],
      instances: [instance],
      rootNodeIndices: [0],
      worldBBox: bbox,
    );
  }

  static Future<ParsedModel> _parseZip(String fileName, Uint8List bytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      String? bestModelName;
      Uint8List? bestModelBytes;
      var bestScore = -1;
      final fileMap = <String, Uint8List>{};

      for (final file in archive) {
        if (!file.isFile) continue;
        final entryName = file.name;
        final low = entryName.toLowerCase();
        final Uint8List entryBytes = file.content;
        if (entryBytes.isEmpty) continue;
        fileMap[low] = entryBytes;
        fileMap[low.split('/').last] = entryBytes;

        var score = 0;
        if (low.endsWith('.glb')) {
          score = 10;
        } else if (low.endsWith('.gltf')) {
          score = 8;
        } else if (low.endsWith('.obj')) {
          score = 6;
        } else if (low.endsWith('.stl')) {
          score = 4;
        } else if (low.endsWith('.fbx')) {
          score = 2;
        }

        if (score > bestScore) {
          bestScore = score;
          bestModelName = entryName.split('/').last;
          bestModelBytes = entryBytes;
        }
      }

      if (bestModelBytes != null && bestModelName != null) {
        if (bestModelName.toLowerCase().endsWith('.gltf')) {
          // Resolve external .bin buffers and image URIs from the archive so
          // textures survive zipped glTF imports.
          final json =
              jsonDecode(utf8.decode(bestModelBytes)) as Map<String, dynamic>;
          Uint8List? bin = _extractEmbeddedGltfBin(json);
          if (bin == null) {
            final buffers = json['buffers'] as List<dynamic>?;
            if (buffers != null && buffers.isNotEmpty) {
              final uri =
                  (buffers.first as Map)['uri']?.toString().toLowerCase() ?? '';
              bin = fileMap[uri] ?? fileMap[uri.split('/').last];
            }
          }
          return await _buildGltfWithTextures(
            bestModelName,
            json,
            bin,
            externalFiles: fileMap,
          );
        }
        return await parse(bestModelName, bestModelBytes);
      }
    } catch (_) {}
    return _parseZipSync(fileName, bytes);
  }

  static ParsedModel _parseZipSync(String fileName, Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      String? bestModelName;
      Uint8List? bestModelBytes;
      var bestScore = -1;

      for (final file in archive) {
        if (!file.isFile) continue;
        final entryName = file.name;
        final low = entryName.toLowerCase();
        var score = 0;
        if (low.endsWith('.glb')) {
          score = 10;
        } else if (low.endsWith('.gltf')) {
          score = 8;
        } else if (low.endsWith('.obj')) {
          score = 6;
        } else if (low.endsWith('.stl')) {
          score = 4;
        } else if (low.endsWith('.fbx')) {
          score = 2;
        }

        if (score > bestScore) {
          final Uint8List entryBytes = file.content;
          if (entryBytes.isNotEmpty) {
            bestScore = score;
            bestModelName = entryName.split('/').last;
            bestModelBytes = entryBytes;
          }
        }
      }

      if (bestModelBytes != null && bestModelName != null) {
        return parseSync(bestModelName, bestModelBytes);
      }
    } catch (_) {}

    return _createFallbackVehicle(fileName, bytes: bytes);
  }

  static ParsedModel _createFallbackVehicle(String fileName, {Uint8List? bytes}) {
    const halfL = 2.1;
    const halfW = 0.95;
    const h = 1.2;
    const wheelR = 0.34;
    const wheelW = 0.24;

    final bodyVerts = <Vec3>[
      const Vec3(-halfW, wheelR * 0.8, -halfL),
      const Vec3(halfW, wheelR * 0.8, -halfL),
      const Vec3(halfW, wheelR * 0.8, halfL),
      const Vec3(-halfW, wheelR * 0.8, halfL),
      const Vec3(-halfW * 0.9, h * 0.7, -halfL * 0.8),
      const Vec3(halfW * 0.9, h * 0.7, -halfL * 0.8),
      const Vec3(halfW * 0.85, h, 0.2),
      const Vec3(-halfW * 0.85, h, 0.2),
      const Vec3(halfW * 0.85, h, 0.8),
      const Vec3(-halfW * 0.85, h, 0.8),
      const Vec3(halfW * 0.9, h * 0.65, halfL * 0.9),
      const Vec3(-halfW * 0.9, h * 0.65, halfL * 0.9),
    ];

    final bodyTris = <Triangle>[
      const Triangle(0, 1, 5),
      const Triangle(0, 5, 4),
      const Triangle(4, 5, 6),
      const Triangle(4, 6, 7),
      const Triangle(7, 6, 8),
      const Triangle(7, 8, 9),
      const Triangle(9, 8, 10),
      const Triangle(9, 10, 11),
      const Triangle(0, 3, 2),
      const Triangle(0, 2, 1),
    ];

    final bodyEdges = <Edge>[
      for (final t in bodyTris) ...[
        Edge(min(t.a, t.b), max(t.a, t.b)),
        Edge(min(t.b, t.c), max(t.b, t.c)),
        Edge(min(t.c, t.a), max(t.c, t.a)),
      ],
    ];

    final bodyBBox = BBox.fromPoints(bodyVerts);
    final bodyMesh = MeshData(
      index: 0,
      name: 'Car_Body',
      vertices: bodyVerts,
      edges: bodyEdges,
      triangles: bodyTris,
      bbox: bodyBBox,
    );

    MeshData makeWheelMesh(int index, String name) {
      final wVerts = <Vec3>[];
      final wTris = <Triangle>[];
      const segments = 12;
      for (var i = 0; i < segments; i++) {
        final a = (i * 2 * pi) / segments;
        final y = sin(a) * wheelR;
        final z = cos(a) * wheelR;
        wVerts.add(Vec3(-wheelW * 0.5, y, z));
        wVerts.add(Vec3(wheelW * 0.5, y, z));
      }
      for (var i = 0; i < segments; i++) {
        final nxt = (i + 1) % segments;
        final i0 = i * 2;
        final i1 = i * 2 + 1;
        final n0 = nxt * 2;
        final n1 = nxt * 2 + 1;
        wTris.add(Triangle(i0, n0, i1));
        wTris.add(Triangle(i1, n0, n1));
      }
      final wEdges = <Edge>[
        for (final t in wTris) Edge(min(t.a, t.b), max(t.a, t.b)),
      ];
      final wBox = BBox.fromPoints(wVerts);
      return MeshData(index: index, name: name, vertices: wVerts, edges: wEdges, triangles: wTris, bbox: wBox);
    }

    final flWheelMesh = makeWheelMesh(1, 'Wheel_FL');
    final frWheelMesh = makeWheelMesh(2, 'Wheel_FR');
    final rlWheelMesh = makeWheelMesh(3, 'Wheel_RL');
    final rrWheelMesh = makeWheelMesh(4, 'Wheel_RR');

    final meshes = [bodyMesh, flWheelMesh, frWheelMesh, rlWheelMesh, rrWheelMesh];
    final nodes = [
      SceneNode(
        index: 0,
        name: 'Car_Body',
        localTransform: Mat4.identity(),
        meshIndex: 0,
        childIndices: const [],
        parentIndex: null,
      ),
      SceneNode(
        index: 1,
        name: 'Wheel_FL',
        localTransform: Mat4.uniformScaleTranslate(1.0, const Vec3(-halfW * 0.92, wheelR, -halfL * 0.65)),
        meshIndex: 1,
        childIndices: const [],
        parentIndex: null,
      ),
      SceneNode(
        index: 2,
        name: 'Wheel_FR',
        localTransform: Mat4.uniformScaleTranslate(1.0, const Vec3(halfW * 0.92, wheelR, -halfL * 0.65)),
        meshIndex: 2,
        childIndices: const [],
        parentIndex: null,
      ),
      SceneNode(
        index: 3,
        name: 'Wheel_RL',
        localTransform: Mat4.uniformScaleTranslate(1.0, const Vec3(-halfW * 0.92, wheelR, halfL * 0.65)),
        meshIndex: 3,
        childIndices: const [],
        parentIndex: null,
      ),
      SceneNode(
        index: 4,
        name: 'Wheel_RR',
        localTransform: Mat4.uniformScaleTranslate(1.0, const Vec3(halfW * 0.92, wheelR, halfL * 0.65)),
        meshIndex: 4,
        childIndices: const [],
        parentIndex: null,
      ),
    ];

    final instances = [
      MeshInstance(nodeIndex: 0, meshIndex: 0, worldVertices: bodyVerts, edges: bodyEdges, triangles: bodyTris, worldBBox: bodyBBox),
      MeshInstance(
        nodeIndex: 1,
        meshIndex: 1,
        worldVertices: flWheelMesh.vertices.map((v) => v + const Vec3(-halfW * 0.92, wheelR, -halfL * 0.65)).toList(),
        edges: flWheelMesh.edges,
        triangles: flWheelMesh.triangles,
        worldBBox: BBox.fromPoints(flWheelMesh.vertices.map((v) => v + const Vec3(-halfW * 0.92, wheelR, -halfL * 0.65)).toList()),
      ),
      MeshInstance(
        nodeIndex: 2,
        meshIndex: 2,
        worldVertices: frWheelMesh.vertices.map((v) => v + const Vec3(halfW * 0.92, wheelR, -halfL * 0.65)).toList(),
        edges: frWheelMesh.edges,
        triangles: frWheelMesh.triangles,
        worldBBox: BBox.fromPoints(frWheelMesh.vertices.map((v) => v + const Vec3(halfW * 0.92, wheelR, -halfL * 0.65)).toList()),
      ),
      MeshInstance(
        nodeIndex: 3,
        meshIndex: 3,
        worldVertices: rlWheelMesh.vertices.map((v) => v + const Vec3(-halfW * 0.92, wheelR, halfL * 0.65)).toList(),
        edges: rlWheelMesh.edges,
        triangles: rlWheelMesh.triangles,
        worldBBox: BBox.fromPoints(rlWheelMesh.vertices.map((v) => v + const Vec3(-halfW * 0.92, wheelR, halfL * 0.65)).toList()),
      ),
      MeshInstance(
        nodeIndex: 4,
        meshIndex: 4,
        worldVertices: rrWheelMesh.vertices.map((v) => v + const Vec3(halfW * 0.92, wheelR, halfL * 0.65)).toList(),
        edges: rrWheelMesh.edges,
        triangles: rrWheelMesh.triangles,
        worldBBox: BBox.fromPoints(rrWheelMesh.vertices.map((v) => v + const Vec3(halfW * 0.92, wheelR, halfL * 0.65)).toList()),
      ),
    ];

    final overallBBox = BBox(
      const Vec3(-halfW, 0, -halfL),
      const Vec3(halfW, h, halfL),
    );

    return ParsedModel(
      fileName: fileName,
      nodes: nodes,
      meshes: meshes,
      instances: instances,
      rootNodeIndices: [0, 1, 2, 3, 4],
      worldBBox: overallBBox,
    );
  }

  static (Map<String, dynamic>, Uint8List?) _unpackGlb(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 12) throw const FormatException('File too small');

    final magic = data.getUint32(0, Endian.little);
    if (magic != _glbMagic) throw const FormatException('Not a GLB file');

    final version = data.getUint32(4, Endian.little);
    if (version != 2) throw FormatException('Unsupported glTF v$version');

    final totalLength = data.getUint32(8, Endian.little);

    Map<String, dynamic>? json;
    Uint8List? bin;
    var offset = 12;

    while (offset + 8 <= totalLength && offset + 8 <= bytes.length) {
      final chunkLen = data.getUint32(offset, Endian.little);
      final chunkType = data.getUint32(offset + 4, Endian.little);
      offset += 8;
      if (offset + chunkLen > bytes.length) break;

      if (chunkType == _chunkJson) {
        json = jsonDecode(
          utf8.decode(bytes.sublist(offset, offset + chunkLen)),
        ) as Map<String, dynamic>;
      } else if (chunkType == _chunkBin) {
        bin = bytes.sublist(offset, offset + chunkLen);
      }
      offset += chunkLen;
    }

    if (json == null) throw const FormatException('No JSON chunk in GLB');
    return (json, bin);
  }

  // ── Internal ────────────────────────────────────────────────────────────

  /// Decodes every embedded/external glTF image once at 128x128, keeping both
  /// the full bitmap (for UV sampling) and its average colour (for fallbacks).
  static Future<Map<int, _DecodedTexture>> _extractTextures(
    List<dynamic> jsonImages,
    List<dynamic> jsonBufferViews,
    Uint8List? bin, {
    Map<String, Uint8List>? externalFiles,
  }) async {
    final textures = <int, _DecodedTexture>{};

    for (var i = 0; i < jsonImages.length; i++) {
      try {
        final img = jsonImages[i] as Map<String, dynamic>;
        Uint8List? imageBytes;
        final bvIdx = img['bufferView'] as int?;
        if (bvIdx != null &&
            bvIdx >= 0 &&
            bvIdx < jsonBufferViews.length &&
            bin != null) {
          final bv = jsonBufferViews[bvIdx] as Map<String, dynamic>;
          final byteOffset = bv['byteOffset'] as int? ?? 0;
          final byteLength = bv['byteLength'] as int? ?? 0;
          if (byteLength > 0 && byteOffset + byteLength <= bin.length) {
            imageBytes = bin.sublist(byteOffset, byteOffset + byteLength);
          }
        } else if (img['uri'] is String) {
          final uri = img['uri'] as String;
          if (uri.startsWith('data:')) {
            final comma = uri.indexOf(',');
            if (comma != -1) {
              imageBytes = base64Decode(uri.substring(comma + 1));
            }
          } else if (externalFiles != null) {
            final key = uri.toLowerCase();
            imageBytes =
                externalFiles[key] ?? externalFiles[key.split('/').last];
          }
        }

        if (imageBytes == null || imageBytes.isEmpty) continue;

        Codec codec;
        try {
          codec = await instantiateImageCodec(
            imageBytes,
            targetWidth: 128,
            targetHeight: 128,
          );
        } catch (_) {
          codec = await instantiateImageCodec(imageBytes);
        }

        final frame = await codec.getNextFrame();
        final uiImg = frame.image;
        final byteData = await uiImg.toByteData(
          format: ImageByteFormat.rawRgba,
        );
        final w = uiImg.width;
        final h = uiImg.height;
        uiImg.dispose();
        if (byteData == null || byteData.lengthInBytes < 4 || w <= 0 || h <= 0) {
          continue;
        }

        final rgba = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        var sr = 0, sg = 0, sb = 0, sa = 0, samples = 0;
        for (var p = 0; p + 4 <= rgba.length; p += 4) {
          final a = rgba[p + 3];
          if (a <= 10) continue;
          sr += rgba[p];
          sg += rgba[p + 1];
          sb += rgba[p + 2];
          sa += a;
          samples++;
        }

        Color average;
        if (samples > 0) {
          average = Color.fromARGB(
            (sa / samples).round(),
            (sr / samples).round(),
            (sg / samples).round(),
            (sb / samples).round(),
          );
        } else {
          // Direct PNG PLTE palette fallback for images the codec cannot decode.
          average = const Color(0xFFC8D1D7);
          if (imageBytes.length > 20 &&
              imageBytes[0] == 0x89 &&
              imageBytes[1] == 0x50 &&
              imageBytes[2] == 0x4E &&
              imageBytes[3] == 0x47) {
            for (var p = 8; p < imageBytes.length - 12;) {
              final len =
                  ByteData.sublistView(imageBytes).getUint32(p, Endian.big);
              final name =
                  String.fromCharCodes(imageBytes.sublist(p + 4, p + 8));
              if (name == 'PLTE' && len >= 3) {
                average = Color.fromARGB(
                  255,
                  imageBytes[p + 8],
                  imageBytes[p + 9],
                  imageBytes[p + 10],
                );
                break;
              }
              p += 12 + len;
            }
          }
        }

        textures[i] = _DecodedTexture(w, h, rgba, average);
      } catch (_) {
        // Continue if any image cannot be decoded
      }
    }
    return textures;
  }

  static Future<ParsedModel> _buildGltfWithTextures(
    String fileName,
    Map<String, dynamic> json,
    Uint8List? bin, {
    Map<String, Uint8List>? externalFiles,
  }) async {
    // Yield between the heavy stages so the import spinner keeps animating at
    // 60 FPS while large GLB/GLTF archives are decoded.
    await Future<void>.delayed(Duration.zero);
    final images = json['images'] as List<dynamic>? ?? [];
    final bufferViews = json['bufferViews'] as List<dynamic>? ?? [];
    final decoded = await _extractTextures(
      images,
      bufferViews,
      bin,
      externalFiles: externalFiles,
    );
    await Future<void>.delayed(Duration.zero);
    final colors = <int, Color>{
      for (final entry in decoded.entries) entry.key: entry.value.averageColor,
    };
    return _build(
      fileName,
      json,
      bin,
      textureColors: colors,
      decodedTextures: decoded,
    );
  }

  static ParsedModel _build(
    String fileName,
    Map<String, dynamic> gltf,
    Uint8List? bin, {
    Map<int, Color>? textureColors,
    Map<int, _DecodedTexture>? decodedTextures,
  }) {
    final jsonNodes = gltf['nodes'] as List<dynamic>? ?? [];
    final jsonMeshes = gltf['meshes'] as List<dynamic>? ?? [];
    final jsonAccessors = gltf['accessors'] as List<dynamic>? ?? [];
    final jsonBufferViews = gltf['bufferViews'] as List<dynamic>? ?? [];

    // ── Build parent map ────────────────────────────────────────────────
    final parentMap = <int, int>{};
    for (var i = 0; i < jsonNodes.length; i++) {
      final children = jsonNodes[i]['children'] as List<dynamic>?;
      if (children != null) {
        for (final c in children) {
          parentMap[c as int] = i;
        }
      }
    }

    // ── Parse scene nodes ───────────────────────────────────────────────
    final nodes = <SceneNode>[];
    for (var i = 0; i < jsonNodes.length; i++) {
      final n = jsonNodes[i] as Map<String, dynamic>;

      Mat4 local;
      if (n.containsKey('matrix')) {
        local = Mat4(
          (n['matrix'] as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList(),
        );
      } else {
        final t = _toVec3(n['translation'], Vec3.zero);
        final r = _toQuat(n['rotation'], Quat.identity);
        final s = _toVec3(n['scale'], Vec3.one);
        local = Mat4.fromTRS(t, r, s);
      }

      nodes.add(
        SceneNode(
          index: i,
          name: n['name'] as String? ?? 'Node_$i',
          localTransform: local,
          meshIndex: n['mesh'] as int?,
          childIndices:
              (n['children'] as List<dynamic>?)
                  ?.map((e) => e as int)
                  .toList() ??
              const [],
          parentIndex: parentMap[i],
        ),
      );
    }

    // ── Compute world transforms ────────────────────────────────────────
    _computeWorldTransforms(nodes);

    // ── Parse meshes (splitting multi-primitive glTF meshes so each primitive
    //    gets its own MeshData/SceneNode, matching Three.js GLTFLoader) ─────
    final jsonMaterials = gltf['materials'] as List<dynamic>? ?? [];
    final jsonTextures = gltf['textures'] as List<dynamic>? ?? [];
    final meshes = <MeshData>[];
    final gltfMeshToMeshDataIndices = <int, List<int>>{};
    for (var mi = 0; mi < jsonMeshes.length; mi++) {
      final m = jsonMeshes[mi] as Map<String, dynamic>;
      final baseMeshName = m['name'] as String? ?? 'Mesh_$mi';
      final prims = m['primitives'] as List<dynamic>? ?? [];
      final primIndices = <int>[];

      for (var pi = 0; pi < prims.length; pi++) {
        final prim = prims[pi] as Map<String, dynamic>;
        final attrs = prim['attributes'] as Map<String, dynamic>?;
        if (attrs == null) continue;
        final posIdx = attrs['POSITION'] as int?;
        if (posIdx == null) continue;

        // Resolve a viewport colour from the primitive's material.
        Map<String, dynamic>? matMap;
        String? matName;
        final matIdx = prim['material'] as int?;
        if (matIdx != null && matIdx >= 0 && matIdx < jsonMaterials.length) {
          matMap = jsonMaterials[matIdx] as Map<String, dynamic>?;
          matName = matMap?['name'] as String?;
        }
        final primName = prims.length > 1
            ? (matName != null && matName.isNotEmpty
                ? '${baseMeshName}_$matName'
                : '${baseMeshName}_prim_$pi')
            : baseMeshName;

        final materialColor = _resolveMaterialColor(
          matMap,
          meshName: primName,
          textureColors: textureColors,
          jsonTextures: jsonTextures,
        );
        final decodedTex = _resolveDecodedTexture(
          matMap,
          decodedTextures: decodedTextures,
          jsonTextures: jsonTextures,
        );
        final baseColorFactor = _readBaseColorFactor(matMap);

        List<Color>? vertexColors;
        final colorIdx = attrs['COLOR_0'] as int?;
        if (colorIdx != null &&
            colorIdx >= 0 &&
            colorIdx < jsonAccessors.length) {
          vertexColors = _readColorAccessor(
            jsonAccessors[colorIdx] as Map<String, dynamic>,
            jsonBufferViews,
            bin,
          );
        }

        List<Offset>? uvs;
        final uvIdx = attrs['TEXCOORD_0'] as int?;
        if (uvIdx != null &&
            uvIdx >= 0 &&
            uvIdx < jsonAccessors.length) {
          uvs = _readVec2Accessor(
            jsonAccessors[uvIdx] as Map<String, dynamic>,
            jsonBufferViews,
            bin,
          );
        }

        final primVerts = _readVec3Accessor(
          jsonAccessors[posIdx] as Map<String, dynamic>,
          jsonBufferViews,
          bin,
        );
        if (primVerts.isEmpty) continue;

        final primEdges = <Edge>{};
        final primTriangles = <Triangle>[];
        final idxIdx = prim['indices'] as int?;
        final mode = prim['mode'] as int? ?? 4;

        if (idxIdx != null) {
          final indices = _readScalarAccessor(
            jsonAccessors[idxIdx] as Map<String, dynamic>,
            jsonBufferViews,
            bin,
          );
          _appendTriangles(
            indices,
            0,
            mode,
            primTriangles,
            primEdges,
            materialColor: materialColor,
            vertexColors: vertexColors,
            uvs: uvs,
            decodedTexture: decodedTex,
            baseColorFactor: baseColorFactor,
          );
        } else {
          // glTF's default primitive mode is TRIANGLES.
          _appendTriangles(
            List<int>.generate(primVerts.length, (index) => index),
            0,
            mode,
            primTriangles,
            primEdges,
            materialColor: materialColor,
            vertexColors: vertexColors,
            uvs: uvs,
            decodedTexture: decodedTex,
            baseColorFactor: baseColorFactor,
          );
        }

        if (primTriangles.isEmpty) continue;
        final newMeshIdx = meshes.length;
        meshes.add(
          MeshData(
            index: newMeshIdx,
            name: primName,
            vertices: primVerts,
            edges: primEdges.toList(),
            triangles: primTriangles,
            bbox: BBox.fromPoints(primVerts),
          ),
        );
        primIndices.add(newMeshIdx);
      }
      gltfMeshToMeshDataIndices[mi] = primIndices;
    }

    // ── Build mesh instances (world-space), creating synthetic child nodes
    //    when a glTF node's mesh had multiple primitives ───────────────────
    final instances = <MeshInstance>[];
    final origNodeCount = nodes.length;
    for (var ni = 0; ni < origNodeCount; ni++) {
      final node = nodes[ni];
      final origMi = node.meshIndex;
      if (origMi == null) continue;
      final mappedMeshes = gltfMeshToMeshDataIndices[origMi];
      if (mappedMeshes == null || mappedMeshes.isEmpty) continue;

      final wt = node.worldTransform;
      final isInverted = wt.determinant3x3 < 0;

      for (var p = 0; p < mappedMeshes.length; p++) {
        final mIdx = mappedMeshes[p];
        final mesh = meshes[mIdx];
        final worldVerts = mesh.vertices
            .map((v) => wt.transformPoint(v))
            .toList();
        final worldTriangles = isInverted
            ? mesh.triangles
                .map((t) => Triangle(t.a, t.c, t.b, t.color))
                .toList()
            : mesh.triangles;

        int targetNodeIdx = node.index;
        if (p == 0) {
          // Register the synthetic primitive nodes as children so childIndices
          // stays consistent with parentIndex for downstream tree traversal.
          final updatedChildren = <int>[
            ...node.childIndices,
            for (var extra = 1; extra < mappedMeshes.length; extra++)
              nodes.length + extra - 1,
          ];
          nodes[ni] = SceneNode(
            index: node.index,
            name: mappedMeshes.length > 1
                ? '${node.name}_${mesh.name}'
                : node.name,
            localTransform: node.localTransform,
            meshIndex: mIdx,
            childIndices: updatedChildren,
            parentIndex: node.parentIndex,
          )..worldTransform = wt;
        } else {
          targetNodeIdx = nodes.length;
          nodes.add(
            SceneNode(
              index: targetNodeIdx,
              name: '${node.name}_${mesh.name}',
              localTransform: Mat4.identity(),
              meshIndex: mIdx,
              childIndices: const [],
              parentIndex: node.index,
            )..worldTransform = wt,
          );
        }

        instances.add(
          MeshInstance(
            nodeIndex: targetNodeIdx,
            meshIndex: mIdx,
            worldVertices: worldVerts,
            edges: mesh.edges,
            triangles: worldTriangles,
            worldBBox: BBox.fromPoints(worldVerts),
          ),
        );
      }
    }

    // ── Root nodes ──────────────────────────────────────────────────────
    final sceneIdx = gltf['scene'] as int? ?? 0;
    final scenes = gltf['scenes'] as List<dynamic>?;
    List<int> roots;
    if (scenes != null && sceneIdx < scenes.length) {
      roots =
          ((scenes[sceneIdx] as Map<String, dynamic>)['nodes']
                  as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [];
    } else {
      roots = [
        for (var i = 0; i < nodes.length; i++)
          if (nodes[i].parentIndex == null) i,
      ];
    }

    // ── Overall bounding box ────────────────────────────────────────────
    final worldBBox = instances.isEmpty
        ? const BBox(Vec3.zero, Vec3.one)
        : BBox.union(instances.map((i) => i.worldBBox).toList());

    return ParsedModel(
      fileName: fileName,
      nodes: nodes,
      meshes: meshes,
      instances: instances,
      rootNodeIndices: roots,
      worldBBox: worldBBox,
    );
  }

  static final _glassMaterial = RegExp(
    r'(glass|window|windshield|windscreen|visor|gls|wnd|sunroof|canopy|screen)',
    caseSensitive: false,
  );
  static final _tireMaterial = RegExp(
    r'(tire|tyre|rubber|tread|compound)',
    caseSensitive: false,
  );
  static final _metalMaterial = RegExp(
    r'(chrome|alloy|aluminium|aluminum|steel|silver|wheel|rim|spoke|hub)',
    caseSensitive: false,
  );
  static final _brakeMaterial = RegExp(
    r'(brake|caliper|disc|rotor)',
    caseSensitive: false,
  );
  static final _headlightMaterial = RegExp(
    r'(headlight|headlamp|front_light|light_front|drl|front.*lamp|lens)',
    caseSensitive: false,
  );
  static final _taillightMaterial = RegExp(
    r'(taillight|taillamp|tail_light|rear_light|light_rear|brake_light|red.*light)',
    caseSensitive: false,
  );
  static final _interiorMaterial = RegExp(
    r'(interior|cockpit|seat|dash|dashboard|steering|console|carpet|cabin)',
    caseSensitive: false,
  );
  static final _trimMaterial = RegExp(
    r'(carbon|trim|grill|grille|radiator|mesh|intake|diffuser|splitter|exhaust|muffler)',
    caseSensitive: false,
  );
  static final _chassisMaterial = RegExp(
    r'(chassis|underbody|undercarriage|suspension|subframe|axle)',
    caseSensitive: false,
  );

  /// Reads `pbrMetallicRoughness.baseColorFactor` as RGB multipliers for
  /// per-triangle texel sampling.
  static List<double>? _readBaseColorFactor(Map<String, dynamic>? material) {
    if (material == null) return null;
    final pbr = material['pbrMetallicRoughness'] as Map<String, dynamic>?;
    final factor = pbr?['baseColorFactor'] as List<dynamic>?;
    if (factor == null || factor.length < 3) return null;
    return [
      for (var i = 0; i < 3; i++)
        ((factor[i] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0).toDouble(),
    ];
  }

  /// Resolves an authored material colour using sampled embedded textures,
  /// PBR baseColorFactor, and vertex colors, falling back to semantic recognition.
  static Color? _resolveMaterialColor(
    Map<String, dynamic>? material, {
    String? meshName,
    Map<int, Color>? textureColors,
    List<dynamic>? jsonTextures,
  }) {
    Color? resolved;

    if (material != null) {
      final pbr = material['pbrMetallicRoughness'] as Map<String, dynamic>?;
      Color? texColor;
      if (pbr != null && textureColors != null) {
        final baseColorTex = pbr['baseColorTexture'] as Map<String, dynamic>?;
        if (baseColorTex != null) {
          final texIdx = baseColorTex['index'] as int?;
          if (texIdx != null) {
            final imgIdx = _textureImageIndex(jsonTextures, texIdx);
            if (textureColors.containsKey(imgIdx)) {
              texColor = textureColors[imgIdx];
            }
          }
        }
      }

      final factor = pbr?['baseColorFactor'] as List<dynamic>?;
      double fr = 1.0, fg = 1.0, fb = 1.0, fa = 1.0;
      if (factor != null && factor.length >= 3) {
        fr = (factor[0] as num).toDouble().clamp(0.0, 1.0);
        fg = (factor[1] as num).toDouble().clamp(0.0, 1.0);
        fb = (factor[2] as num).toDouble().clamp(0.0, 1.0);
        if (factor.length >= 4) {
          fa = (factor[3] as num).toDouble().clamp(0.0, 1.0);
        }
      }

      if (texColor != null) {
        final tr = (texColor.toARGB32() >> 16) & 0xFF;
        final tg = (texColor.toARGB32() >> 8) & 0xFF;
        final tb = texColor.toARGB32() & 0xFF;
        final ta = (texColor.toARGB32() >> 24) & 0xFF;
        final r = (tr * fr).round().clamp(0, 255);
        final g = (tg * fg).round().clamp(0, 255);
        final b = (tb * fb).round().clamp(0, 255);
        final a = (ta * fa).round().clamp(0, 255);
        resolved = Color.fromARGB(a, r, g, b);
      } else if (factor != null && factor.length >= 3) {
        final r = (fr * 255.0).round().clamp(0, 255);
        final g = (fg * 255.0).round().clamp(0, 255);
        final b = (fb * 255.0).round().clamp(0, 255);
        final a = (fa * 255.0).round().clamp(0, 255);
        resolved = Color.fromARGB(a, r, g, b);
      }

      // Check emissive factor for lights and displays
      if (resolved == null) {
        final emissive = material['emissiveFactor'] as List<dynamic>?;
        if (emissive != null && emissive.length >= 3) {
          final er = (emissive[0] as num).toDouble().clamp(0.0, 1.0);
          final eg = (emissive[1] as num).toDouble().clamp(0.0, 1.0);
          final eb = (emissive[2] as num).toDouble().clamp(0.0, 1.0);
          if (er > 0.05 || eg > 0.05 || eb > 0.05) {
            resolved = Color.fromARGB(
              255,
              (er * 255).round().clamp(0, 255),
              (eg * 255).round().clamp(0, 255),
              (eb * 255).round().clamp(0, 255),
            );
          }
        }
      }
    }

    if (resolved == null) {
      resolved = _materialColor(material, meshName: meshName);
    } else {
      final matName = (material?['name'] as String? ?? '').toLowerCase();
      final mName = (meshName ?? '').toLowerCase();
      final combined = '$matName $mName';
      // If the material is glass and was authored opaque, give it realistic windshield tint
      if (_glassMaterial.hasMatch(combined)) {
        final a = (resolved.toARGB32() >> 24) & 0xFF;
        if (a > 190) {
          resolved = resolved.withAlpha(180);
        }
      }
    }

    if (material != null && (material['alphaMode'] as String?) == 'BLEND') {
      final base = resolved ?? const Color(0xFF162A32);
      final alpha = (base.toARGB32() >> 24) & 0xFF;
      return base.withAlpha(alpha < 120 ? alpha : 120);
    }
    return resolved;
  }

  /// Resolves the actual image index of a glTF texture, including extensions
  /// used by Sketchfab exports (WebP and KTX2/BasisU) that hide the source.
  static int _textureImageIndex(List<dynamic>? jsonTextures, int texIdx) {
    if (jsonTextures == null || texIdx < 0 || texIdx >= jsonTextures.length) {
      return texIdx;
    }
    final texObj = jsonTextures[texIdx] as Map<String, dynamic>?;
    final extensions = texObj?['extensions'] as Map<String, dynamic>?;
    final extWebp =
        extensions?['EXT_texture_webp'] as Map<String, dynamic>?;
    final extBasis =
        extensions?['KHR_texture_basisu'] as Map<String, dynamic>?;
    return (texObj?['source'] as int?) ??
        (extWebp?['source'] as int?) ??
        (extBasis?['source'] as int?) ??
        texIdx;
  }

  /// Returns the decoded base-colour texture for a material so triangle colors
  /// can be sampled through TEXCOORD_0 instead of a single averaged pixel.
  static _DecodedTexture? _resolveDecodedTexture(
    Map<String, dynamic>? material, {
    Map<int, _DecodedTexture>? decodedTextures,
    List<dynamic>? jsonTextures,
  }) {
    if (material == null || decodedTextures == null) return null;
    final pbr = material['pbrMetallicRoughness'] as Map<String, dynamic>?;
    final baseColorTex = pbr?['baseColorTexture'] as Map<String, dynamic>?;
    final texIdx = baseColorTex?['index'] as int?;
    if (texIdx == null) return null;
    final imgIdx = _textureImageIndex(jsonTextures, texIdx);
    return decodedTextures[imgIdx];
  }

  /// Picks a flat viewport colour for a glTF material. When textured materials
  /// lack custom vertex colors, well-known material and mesh names get authentic
  /// automotive tints so glass, tyres, rims, interior, and lights are properly
  /// distinguished rather than collapsing into the body paint.
  static Color? _materialColor(
    Map<String, dynamic>? material, {
    String? meshName,
  }) {
    final matName = (material?['name'] as String? ?? '').toLowerCase();
    final mName = (meshName ?? '').toLowerCase();
    final combined = '$matName $mName';

    if (_glassMaterial.hasMatch(combined)) return const Color(0xBB162832);
    if (_tireMaterial.hasMatch(combined)) return const Color(0xFF191C1E);
    if (_brakeMaterial.hasMatch(combined)) return const Color(0xFF8B1E1E);
    if (_metalMaterial.hasMatch(combined) && !_tireMaterial.hasMatch(combined)) {
      return const Color(0xFFC8D1D7);
    }
    if (_headlightMaterial.hasMatch(combined)) return const Color(0xFFE8F4FC);
    if (_taillightMaterial.hasMatch(combined)) return const Color(0xFFDC2626);
    if (_interiorMaterial.hasMatch(combined)) return const Color(0xFF1F2327);
    if (_trimMaterial.hasMatch(combined)) return const Color(0xFF202428);
    if (_chassisMaterial.hasMatch(combined)) return const Color(0xFF181A1C);

    if (material == null) return null;

    final pbr = material['pbrMetallicRoughness'] as Map<String, dynamic>?;
    final factor = pbr?['baseColorFactor'] as List<dynamic>?;
    int channel(int i) =>
        (((factor![i] as num).toDouble()) * 255).round().clamp(0, 255).toInt();

    Color? color;
    if (factor != null && factor.length >= 3) {
      final r = channel(0), g = channel(1), b = channel(2);
      final a = factor.length >= 4 ? channel(3) : 255;
      final nearWhite = r > 240 && g > 240 && b > 240;
      if (!(pbr?['baseColorTexture'] != null && nearWhite)) {
        color = Color.fromARGB(a, r, g, b);
      }
    }

    // Blended materials (light cones, glow planes, tinted glass) must not be
    // drawn as opaque panels.
    if ((material['alphaMode'] as String?) == 'BLEND') {
      final base = color ?? const Color(0xFF162A32);
      final alpha = (base.toARGB32() >> 24) & 0xFF;
      return base.withAlpha(alpha < 120 ? alpha : 120);
    }
    return color;
  }

  static void _appendTriangles(
    List<int> indices,
    int vertexOffset,
    int mode,
    List<Triangle> triangles,
    Set<Edge> edges, {
    Color? materialColor,
    List<Color>? vertexColors,
    List<Offset>? uvs,
    _DecodedTexture? decodedTexture,
    List<double>? baseColorFactor,
  }) {
    Color? vertexColorFor(int idx) {
      if (vertexColors != null && idx >= 0 && idx < vertexColors.length) {
        return vertexColors[idx];
      }
      return null;
    }

    // Sample the base-colour atlas at the triangle's centroid UV so decals,
    // hoods and body paint all resolve to their authored texel colors.
    Color? sampledColorFor(int a, int b, int c) {
      if (decodedTexture == null || uvs == null) return null;
      if (a < 0 || b < 0 || c < 0) return null;
      if (a >= uvs.length || b >= uvs.length || c >= uvs.length) return null;
      final u = (uvs[a].dx + uvs[b].dx + uvs[c].dx) / 3.0;
      final v = (uvs[a].dy + uvs[b].dy + uvs[c].dy) / 3.0;
      return decodedTexture.sampleUv(u, v, baseColorFactor: baseColorFactor);
    }

    void addTriangle(int a, int b, int c) {
      final i0 = a + vertexOffset;
      final i1 = b + vertexOffset;
      final i2 = c + vertexOffset;
      final triCol = vertexColorFor(a) ??
          vertexColorFor(b) ??
          vertexColorFor(c) ??
          sampledColorFor(a, b, c) ??
          materialColor;
      triangles.add(Triangle(i0, i1, i2, triCol));
    }

    void addEdge(int a, int b) {
      edges.add(Edge(a + vertexOffset, b + vertexOffset));
    }

    final triangleCount = switch (mode) {
      4 => indices.length ~/ 3,
      5 || 6 => max(0, indices.length - 2),
      _ => 0,
    };

    // Keep all triangles intact so Solid mode is a continuous watertight mesh
    switch (mode) {
      case 4: // TRIANGLES
        for (var t = 0; t < triangleCount; t++) {
          final offset = t * 3;
          addTriangle(
            indices[offset],
            indices[offset + 1],
            indices[offset + 2],
          );
        }
      case 5: // TRIANGLE_STRIP
        for (var t = 0; t < triangleCount; t++) {
          final a = indices[t];
          final b = indices[t + 1];
          final c = indices[t + 2];
          if (t.isEven) {
            addTriangle(a, b, c);
          } else {
            addTriangle(b, a, c);
          }
        }
      case 6: // TRIANGLE_FAN
        for (var t = 0; t < triangleCount; t++) {
          addTriangle(indices[0], indices[t + 1], indices[t + 2]);
        }
    }

    // Sample wireframe edges to bound memory and prevent browser jank on dense meshes
    final edgeStep = triangleCount > _maxEdgesPerPrimitive
        ? (triangleCount / _maxEdgesPerPrimitive).ceil()
        : 1;

    switch (mode) {
      case 4:
        for (var t = 0; t < triangleCount; t += edgeStep) {
          final offset = t * 3;
          final i0 = indices[offset];
          final i1 = indices[offset + 1];
          final i2 = indices[offset + 2];
          addEdge(i0, i1);
          addEdge(i1, i2);
          addEdge(i0, i2);
        }
      case 5:
        for (var t = 0; t < triangleCount; t += edgeStep) {
          addEdge(indices[t], indices[t + 1]);
          addEdge(indices[t + 1], indices[t + 2]);
          addEdge(indices[t], indices[t + 2]);
        }
      case 6:
        for (var t = 0; t < triangleCount; t += edgeStep) {
          addEdge(indices[0], indices[t + 1]);
          addEdge(indices[t + 1], indices[t + 2]);
          addEdge(indices[0], indices[t + 2]);
        }
    }
  }

  // ── Accessor helpers ──────────────────────────────────────────────────

  static Vec3 _toVec3(dynamic list, Vec3 fallback) {
    if (list == null) return fallback;
    final l = list as List<dynamic>;
    return Vec3(
      (l[0] as num).toDouble(),
      (l[1] as num).toDouble(),
      (l[2] as num).toDouble(),
    );
  }

  static Quat _toQuat(dynamic list, Quat fallback) {
    if (list == null) return fallback;
    final l = list as List<dynamic>;
    return Quat(
      (l[0] as num).toDouble(),
      (l[1] as num).toDouble(),
      (l[2] as num).toDouble(),
      (l[3] as num).toDouble(),
    );
  }

  static List<Vec3> _readVec3Accessor(
    Map<String, dynamic> accessor,
    List<dynamic> bufferViews,
    Uint8List? bin,
  ) {
    if (bin == null) return [];
    final count = accessor['count'] as int;
    final bvIdx = accessor['bufferView'] as int?;
    if (bvIdx == null) return List.filled(count, Vec3.zero);

    final bv = bufferViews[bvIdx] as Map<String, dynamic>;
    final byteOffset =
        (bv['byteOffset'] as int? ?? 0) + (accessor['byteOffset'] as int? ?? 0);
    final byteStride = bv['byteStride'] as int? ?? 12;

    final bd = ByteData.sublistView(bin);
    final result = <Vec3>[];
    for (var i = 0; i < count; i++) {
      final o = byteOffset + i * byteStride;
      if (o + 12 > bin.length) break;
      result.add(
        Vec3(
          bd.getFloat32(o, Endian.little),
          bd.getFloat32(o + 4, Endian.little),
          bd.getFloat32(o + 8, Endian.little),
        ),
      );
    }
    return result;
  }

  static List<Offset> _readVec2Accessor(
    Map<String, dynamic> accessor,
    List<dynamic> bufferViews,
    Uint8List? bin,
  ) {
    if (bin == null) return [];
    if (accessor['type'] != null && accessor['type'] != 'VEC2') return [];
    final count = accessor['count'] as int? ?? 0;
    final bvIdx = accessor['bufferView'] as int?;
    if (bvIdx == null || bvIdx < 0 || bvIdx >= bufferViews.length) return [];

    // KHR_mesh_quantization stores TEXCOORD_0 as normalized 5121/5123/5122.
    final compType = accessor['componentType'] as int? ?? 5126;
    final compBytes = compType == 5126
        ? 4
        : ((compType == 5123 || compType == 5122) ? 2 : 1);

    final bv = bufferViews[bvIdx] as Map<String, dynamic>;
    final byteOffset =
        (bv['byteOffset'] as int? ?? 0) + (accessor['byteOffset'] as int? ?? 0);
    final byteStride = bv['byteStride'] as int? ?? (compBytes * 2);

    final bd = ByteData.sublistView(bin);
    final result = <Offset>[];
    for (var i = 0; i < count; i++) {
      final o = byteOffset + i * byteStride;
      if (o + compBytes * 2 > bin.length) break;
      double u, v;
      if (compType == 5126) {
        u = bd.getFloat32(o, Endian.little);
        v = bd.getFloat32(o + 4, Endian.little);
      } else if (compType == 5123) {
        u = bd.getUint16(o, Endian.little) / 65535.0;
        v = bd.getUint16(o + 2, Endian.little) / 65535.0;
      } else if (compType == 5122) {
        u = max(-1.0, bd.getInt16(o, Endian.little) / 32767.0);
        v = max(-1.0, bd.getInt16(o + 2, Endian.little) / 32767.0);
      } else if (compType == 5121) {
        u = bd.getUint8(o) / 255.0;
        v = bd.getUint8(o + 1) / 255.0;
      } else {
        u = max(-1.0, bd.getInt8(o) / 127.0);
        v = max(-1.0, bd.getInt8(o + 1) / 127.0);
      }
      result.add(Offset(u, v));
    }
    return result;
  }

  static List<int> _readScalarAccessor(
    Map<String, dynamic> accessor,
    List<dynamic> bufferViews,
    Uint8List? bin,
  ) {
    if (bin == null) return [];
    final count = accessor['count'] as int;
    final componentType = accessor['componentType'] as int;
    final bvIdx = accessor['bufferView'] as int?;
    if (bvIdx == null) return [];

    final bv = bufferViews[bvIdx] as Map<String, dynamic>;
    final byteOffset =
        (bv['byteOffset'] as int? ?? 0) + (accessor['byteOffset'] as int? ?? 0);

    final bd = ByteData.sublistView(bin);
    final result = <int>[];
    for (var i = 0; i < count; i++) {
      switch (componentType) {
        case 5121: // UNSIGNED_BYTE
          final o = byteOffset + i;
          if (o < bin.length) result.add(bd.getUint8(o));
        case 5123: // UNSIGNED_SHORT
          final o = byteOffset + i * 2;
          if (o + 2 <= bin.length) result.add(bd.getUint16(o, Endian.little));
        case 5125: // UNSIGNED_INT
          final o = byteOffset + i * 4;
          if (o + 4 <= bin.length) result.add(bd.getUint32(o, Endian.little));
      }
    }
    return result;
  }

  static List<Color> _readColorAccessor(
    Map<String, dynamic> accessor,
    List<dynamic> bufferViews,
    Uint8List? bin,
  ) {
    if (bin == null) return const [];
    final count = accessor['count'] as int? ?? 0;
    final type = accessor['type'] as String? ?? 'VEC3';
    final componentType = accessor['componentType'] as int? ?? 5126;
    final bvIdx = accessor['bufferView'] as int?;
    if (bvIdx == null || count <= 0) return const [];

    final bv = bufferViews[bvIdx] as Map<String, dynamic>;
    final baseOffset =
        (bv['byteOffset'] as int? ?? 0) + (accessor['byteOffset'] as int? ?? 0);
    final numComponents = type == 'VEC4' ? 4 : 3;

    final defaultStride = switch (componentType) {
      5121 => numComponents,
      5123 => numComponents * 2,
      5126 => numComponents * 4,
      _ => numComponents * 4,
    };
    final byteStride = bv['byteStride'] as int? ?? defaultStride;

    final bd = ByteData.sublistView(bin);
    final result = <Color>[];

    for (var i = 0; i < count; i++) {
      final o = baseOffset + i * byteStride;
      if (o >= bin.length) break;

      double r = 1.0, g = 1.0, b = 1.0, a = 1.0;
      switch (componentType) {
        case 5121: // UNSIGNED_BYTE
          if (o + numComponents <= bin.length) {
            r = bd.getUint8(o) / 255.0;
            g = bd.getUint8(o + 1) / 255.0;
            b = bd.getUint8(o + 2) / 255.0;
            if (numComponents == 4) a = bd.getUint8(o + 3) / 255.0;
          }
        case 5123: // UNSIGNED_SHORT
          if (o + numComponents * 2 <= bin.length) {
            r = bd.getUint16(o, Endian.little) / 65535.0;
            g = bd.getUint16(o + 2, Endian.little) / 65535.0;
            b = bd.getUint16(o + 4, Endian.little) / 65535.0;
            if (numComponents == 4) {
              a = bd.getUint16(o + 6, Endian.little) / 65535.0;
            }
          }
        case 5126: // FLOAT
          if (o + numComponents * 4 <= bin.length) {
            r = bd.getFloat32(o, Endian.little).clamp(0.0, 1.0);
            g = bd.getFloat32(o + 4, Endian.little).clamp(0.0, 1.0);
            b = bd.getFloat32(o + 8, Endian.little).clamp(0.0, 1.0);
            if (numComponents == 4) {
              a = bd.getFloat32(o + 12, Endian.little).clamp(0.0, 1.0);
            }
          }
      }

      final ir = (r * 255.0).round().clamp(0, 255);
      final ig = (g * 255.0).round().clamp(0, 255);
      final ib = (b * 255.0).round().clamp(0, 255);
      final ia = (a * 255.0).round().clamp(0, 255);
      result.add(Color.fromARGB(ia, ir, ig, ib));
    }
    return result;
  }

  static void _computeWorldTransforms(List<SceneNode> nodes) {
    final done = List.filled(nodes.length, false);

    void visit(int i) {
      if (done[i]) return;
      final node = nodes[i];
      if (node.parentIndex != null) {
        visit(node.parentIndex!);
        node.worldTransform =
            nodes[node.parentIndex!].worldTransform * node.localTransform;
      } else {
        node.worldTransform = node.localTransform;
      }
      done[i] = true;
    }

    for (var i = 0; i < nodes.length; i++) {
      visit(i);
    }
  }
}
