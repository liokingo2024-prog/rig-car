import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

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
  // The viewport is an interactive wireframe preview, not a mesh editor.
  // Capping sampled triangle edges keeps browser parsing and memory bounded
  // for production GLBs while preserving all vertex positions for detection.
  static const _maxEdgesPerPrimitive = 16000;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Parse a GLB binary blob asynchronously, extracting embedded textures
  /// and vertex colors so models render with their authentic authored materials.
  static Future<ParsedModel> parse(String fileName, Uint8List bytes) async {
    final (json, bin) = _unpackGlb(bytes);
    final jsonImages = json['images'] as List<dynamic>? ?? [];
    final jsonBufferViews = json['bufferViews'] as List<dynamic>? ?? [];
    final textureColors = await _extractTextureColors(
      jsonImages,
      jsonBufferViews,
      bin,
    );
    return _build(fileName, json, bin, textureColors: textureColors);
  }

  /// Synchronous fallback when async texture decoding is not needed.
  static ParsedModel parseSync(String fileName, Uint8List bytes) {
    final (json, bin) = _unpackGlb(bytes);
    return _build(fileName, json, bin);
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

  static Future<Map<int, Color>> _extractTextureColors(
    List<dynamic> jsonImages,
    List<dynamic> jsonBufferViews,
    Uint8List? bin,
  ) async {
    final colors = <int, Color>{};
    if (bin == null) return colors;

    for (var i = 0; i < jsonImages.length; i++) {
      try {
        final img = jsonImages[i] as Map<String, dynamic>;
        final bvIdx = img['bufferView'] as int?;
        if (bvIdx == null || bvIdx < 0 || bvIdx >= jsonBufferViews.length) {
          continue;
        }
        final bv = jsonBufferViews[bvIdx] as Map<String, dynamic>;
        final byteOffset = bv['byteOffset'] as int? ?? 0;
        final byteLength = bv['byteLength'] as int? ?? 0;
        if (byteLength <= 0 || byteOffset + byteLength > bin.length) continue;

        final imageBytes = bin.sublist(byteOffset, byteOffset + byteLength);
        final codec = await instantiateImageCodec(
          imageBytes,
          targetWidth: 1,
          targetHeight: 1,
        );
        final frame = await codec.getNextFrame();
        final byteData = await frame.image.toByteData(
          format: ImageByteFormat.rawRgba,
        );
        frame.image.dispose();
        if (byteData != null && byteData.lengthInBytes >= 4) {
          final r = byteData.getUint8(0);
          final g = byteData.getUint8(1);
          final b = byteData.getUint8(2);
          final a = byteData.getUint8(3);
          if (a > 10) {
            colors[i] = Color.fromARGB(a, r, g, b);
          }
        }
      } catch (_) {
        // Continue if any image cannot be downscaled
      }
    }
    return colors;
  }

  static ParsedModel _build(
    String fileName,
    Map<String, dynamic> gltf,
    Uint8List? bin, {
    Map<int, Color>? textureColors,
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

    // ── Parse meshes ────────────────────────────────────────────────────
    final jsonMaterials = gltf['materials'] as List<dynamic>? ?? [];
    final jsonTextures = gltf['textures'] as List<dynamic>? ?? [];
    final meshes = <MeshData>[];
    for (var mi = 0; mi < jsonMeshes.length; mi++) {
      final m = jsonMeshes[mi] as Map<String, dynamic>;
      final prims = m['primitives'] as List<dynamic>? ?? [];

      final allVerts = <Vec3>[];
      final allEdges = <Edge>{};
      final allTriangles = <Triangle>[];

      for (final prim in prims) {
        final attrs = prim['attributes'] as Map<String, dynamic>?;
        if (attrs == null) continue;
        final posIdx = attrs['POSITION'] as int?;
        if (posIdx == null) continue;

        // Resolve a viewport colour from the primitive's material.
        Color? materialColor;
        final matIdx = prim['material'] as int?;
        final meshName = m['name'] as String?;
        if (matIdx != null && matIdx >= 0 && matIdx < jsonMaterials.length) {
          materialColor = _resolveMaterialColor(
            jsonMaterials[matIdx] as Map<String, dynamic>?,
            meshName: meshName,
            textureColors: textureColors,
            jsonTextures: jsonTextures,
          );
        } else {
          materialColor = _resolveMaterialColor(
            null,
            meshName: meshName,
            textureColors: textureColors,
            jsonTextures: jsonTextures,
          );
        }

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

        final vOffset = allVerts.length;
        allVerts.addAll(
          _readVec3Accessor(
            jsonAccessors[posIdx] as Map<String, dynamic>,
            jsonBufferViews,
            bin,
          ),
        );

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
            vOffset,
            mode,
            allTriangles,
            allEdges,
            materialColor: materialColor,
            vertexColors: vertexColors,
          );
        } else {
          // glTF's default primitive mode is TRIANGLES.
          final vertexCount = allVerts.length - vOffset;
          _appendTriangles(
            List<int>.generate(vertexCount, (index) => index),
            vOffset,
            mode,
            allTriangles,
            allEdges,
            materialColor: materialColor,
            vertexColors: vertexColors,
          );
        }
      }

      meshes.add(
        MeshData(
          index: mi,
          name: m['name'] as String? ?? 'Mesh_$mi',
          vertices: allVerts,
          edges: allEdges.toList(),
          triangles: allTriangles,
          bbox: BBox.fromPoints(allVerts),
        ),
      );
    }

    // ── Build mesh instances (world-space) ──────────────────────────────
    final instances = <MeshInstance>[];
    for (final node in nodes) {
      if (node.meshIndex == null) continue;
      final mi = node.meshIndex!;
      if (mi >= meshes.length) continue;
      final mesh = meshes[mi];
      final wt = node.worldTransform;

      final worldVerts = mesh.vertices
          .map((v) => wt.transformPoint(v))
          .toList();

      // Invert triangle winding in world space if transform is mirrored (negative scale)
      final isInverted = wt.determinant3x3 < 0;
      final worldTriangles = isInverted
          ? mesh.triangles
              .map((t) => Triangle(t.a, t.c, t.b, t.color))
              .toList()
          : mesh.triangles;

      instances.add(
        MeshInstance(
          nodeIndex: node.index,
          meshIndex: mi,
          worldVertices: worldVerts,
          edges: mesh.edges,
          triangles: worldTriangles,
          worldBBox: BBox.fromPoints(worldVerts),
        ),
      );
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
            int imgIdx = texIdx;
            if (jsonTextures != null &&
                texIdx >= 0 &&
                texIdx < jsonTextures.length) {
              final texObj = jsonTextures[texIdx] as Map<String, dynamic>?;
              imgIdx = texObj?['source'] as int? ?? texIdx;
            }
            if (textureColors.containsKey(imgIdx)) {
              texColor = textureColors[imgIdx];
            }
          }
        }
      }

      final factor = pbr?['baseColorFactor'] as List<dynamic>?;
      double fr = 1.0, fg = 1.0, fb = 1.0, fa = 1.0;
      bool hasCustomFactor = false;
      if (factor != null && factor.length >= 3) {
        fr = (factor[0] as num).toDouble().clamp(0.0, 1.0);
        fg = (factor[1] as num).toDouble().clamp(0.0, 1.0);
        fb = (factor[2] as num).toDouble().clamp(0.0, 1.0);
        if (factor.length >= 4) {
          fa = (factor[3] as num).toDouble().clamp(0.0, 1.0);
        }
        if ((fr - 1.0).abs() > 0.05 ||
            (fg - 1.0).abs() > 0.05 ||
            (fb - 1.0).abs() > 0.05 ||
            (fa - 1.0).abs() > 0.05) {
          hasCustomFactor = true;
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
      } else if (hasCustomFactor) {
        final r = (fr * 255.0).round().clamp(0, 255);
        final g = (fg * 255.0).round().clamp(0, 255);
        final b = (fb * 255.0).round().clamp(0, 255);
        final a = (fa * 255.0).round().clamp(0, 255);
        resolved = Color.fromARGB(a, r, g, b);
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
  }) {
    Color? colorFor(int idx) {
      if (vertexColors != null && idx >= 0 && idx < vertexColors.length) {
        return vertexColors[idx];
      }
      return materialColor;
    }

    void addTriangle(int a, int b, int c) {
      final i0 = a + vertexOffset;
      final i1 = b + vertexOffset;
      final i2 = c + vertexOffset;
      final triCol = colorFor(a) ?? colorFor(b) ?? colorFor(c);
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
