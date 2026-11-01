import 'dart:convert';
import 'dart:typed_data';

import 'model_data.dart';

// ── GLB / glTF Binary Parser ────────────────────────────────────────────────
//
// Reads a .glb file (glTF 2.0 binary container), extracts the full node tree,
// mesh vertex positions, triangle edges, and bounding boxes.  The result is a
// [ParsedModel] ready for auto-detection and wireframe rendering.

class GlbParser {
  static const _glbMagic = 0x46546C67; // ASCII 'glTF'
  static const _chunkJson = 0x4E4F534A;
  static const _chunkBin = 0x004E4942;

  /// Maximum edges to keep per mesh primitive to prevent OOM on huge models.
  static const _maxEdgesPerPrimitive = 60000;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Parse a GLB binary blob.  Throws [FormatException] on invalid data.
  static ParsedModel parse(String fileName, Uint8List bytes) {
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
        json = jsonDecode(utf8.decode(bytes.sublist(offset, offset + chunkLen)))
            as Map<String, dynamic>;
      } else if (chunkType == _chunkBin) {
        bin = bytes.sublist(offset, offset + chunkLen);
      }
      offset += chunkLen;
    }

    if (json == null) throw const FormatException('No JSON chunk in GLB');
    return _build(fileName, json, bin);
  }

  // ── Internal ────────────────────────────────────────────────────────────

  static ParsedModel _build(
    String fileName,
    Map<String, dynamic> gltf,
    Uint8List? bin,
  ) {
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

      nodes.add(SceneNode(
        index: i,
        name: n['name'] as String? ?? 'Node_$i',
        localTransform: local,
        meshIndex: n['mesh'] as int?,
        childIndices: (n['children'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            const [],
        parentIndex: parentMap[i],
      ));
    }

    // ── Compute world transforms ────────────────────────────────────────
    _computeWorldTransforms(nodes);

    // ── Parse meshes ────────────────────────────────────────────────────
    final meshes = <MeshData>[];
    for (var mi = 0; mi < jsonMeshes.length; mi++) {
      final m = jsonMeshes[mi] as Map<String, dynamic>;
      final prims = m['primitives'] as List<dynamic>? ?? [];

      final allVerts = <Vec3>[];
      final allEdges = <Edge>{};

      for (final prim in prims) {
        final attrs = prim['attributes'] as Map<String, dynamic>?;
        if (attrs == null) continue;
        final posIdx = attrs['POSITION'] as int?;
        if (posIdx == null) continue;

        final vOffset = allVerts.length;
        allVerts.addAll(_readVec3Accessor(
          jsonAccessors[posIdx] as Map<String, dynamic>,
          jsonBufferViews,
          bin,
        ));

        final idxIdx = prim['indices'] as int?;
        if (idxIdx != null) {
          final indices = _readScalarAccessor(
            jsonAccessors[idxIdx] as Map<String, dynamic>,
            jsonBufferViews,
            bin,
          );
          final triCount = indices.length ~/ 3;
          final step = triCount > _maxEdgesPerPrimitive
              ? (triCount / _maxEdgesPerPrimitive).ceil()
              : 1;
          for (var t = 0; t + 2 < indices.length; t += 3 * step) {
            final i0 = indices[t] + vOffset;
            final i1 = indices[t + 1] + vOffset;
            final i2 = indices[t + 2] + vOffset;
            allEdges.add(Edge(i0, i1));
            allEdges.add(Edge(i1, i2));
            allEdges.add(Edge(i0, i2));
          }
        }
      }

      meshes.add(MeshData(
        index: mi,
        name: m['name'] as String? ?? 'Mesh_$mi',
        vertices: allVerts,
        edges: allEdges.toList(),
        bbox: BBox.fromPoints(allVerts),
      ));
    }

    // ── Build mesh instances (world-space) ──────────────────────────────
    final instances = <MeshInstance>[];
    for (final node in nodes) {
      if (node.meshIndex == null) continue;
      final mi = node.meshIndex!;
      if (mi >= meshes.length) continue;
      final mesh = meshes[mi];
      final wt = node.worldTransform;

      final worldVerts = mesh.vertices.map((v) => wt.transformPoint(v)).toList();

      instances.add(MeshInstance(
        nodeIndex: node.index,
        meshIndex: mi,
        worldVertices: worldVerts,
        edges: mesh.edges,
        worldBBox: BBox.fromPoints(worldVerts),
      ));
    }

    // ── Root nodes ──────────────────────────────────────────────────────
    final sceneIdx = gltf['scene'] as int? ?? 0;
    final scenes = gltf['scenes'] as List<dynamic>?;
    List<int> roots;
    if (scenes != null && sceneIdx < scenes.length) {
      roots = ((scenes[sceneIdx] as Map<String, dynamic>)['nodes']
                  as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [];
    } else {
      roots = [for (var i = 0; i < nodes.length; i++) if (nodes[i].parentIndex == null) i];
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
      result.add(Vec3(
        bd.getFloat32(o, Endian.little),
        bd.getFloat32(o + 4, Endian.little),
        bd.getFloat32(o + 8, Endian.little),
      ));
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
