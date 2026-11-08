import 'dart:math';
import 'dart:typed_data';

import 'model_data.dart';

// ── Solid-view mesh preparation ─────────────────────────────────────────────
//
// The solid viewport is a painter's-algorithm renderer, so it needs three
// things the raw glTF triangle lists do not give it:
//
//  1. A *coherent* level of detail. Dropping every Nth triangle (the old
//     approach) punches holes in the surface and exposes the interior. Here
//     dense meshes are simplified by vertex clustering instead, which keeps
//     the surface closed.
//  2. No very large triangles. A single hood or bumper triangle cannot be
//     depth-sorted correctly against many small ones, so long edges are split.
//  3. Flat typed arrays (normals, centroids, colours) that are computed once
//     per model rather than once per frame.
//
// A [SolidScene] is cached per [ParsedModel] and builds its two levels of
// detail lazily.

const int solidKindBody = 0;
const int solidKindGlass = 1;
const int solidKindWheel = 2;
const int solidKindRim = 3;
const int solidKindInterior = 4;
const int solidKindTrim = 5;
const int solidKindHeadlight = 6;
const int solidKindTaillight = 7;
const int solidKindChassis = 8;

/// Render-ready triangle soup plus per-frame scratch buffers.
class SolidMesh {
  SolidMesh({
    required this.vertexCount,
    required this.triangleCount,
    required this.positions,
    required this.indices,
    required this.normals,
    required this.centroids,
    required this.triNode,
    required this.triKind,
    required this.triColor,
  });

  final int vertexCount;
  final int triangleCount;

  /// xyz per vertex, world space.
  final Float32List positions;

  /// Three vertex indices per triangle.
  final Int32List indices;

  /// Unit face normal per triangle.
  final Float32List normals;

  /// Triangle centroid per triangle.
  final Float32List centroids;

  /// Scene-node index per triangle (used for selection highlighting).
  final Int32List triNode;

  /// One of [solidKindBody], [solidKindGlass], [solidKindWheel].
  final Uint8List triKind;

  /// ARGB material colour per triangle, or 0 when the material has none.
  final Int32List triColor;

  // Scratch buffers reused by every frame (the painter itself is recreated
  // on each repaint, so they live here).
  late final Float32List screenX = Float32List(vertexCount);
  late final Float32List screenY = Float32List(vertexCount);
  late final Float32List screenW = Float32List(vertexCount);
  late final Int32List visTri = Int32List(triangleCount);
  late final Int32List visColor = Int32List(triangleCount);
  late final Float32List visDepth = Float32List(triangleCount);
  late final Int32List visBucket = Int32List(triangleCount);
  late final Int32List sortedOrder = Int32List(triangleCount);
  late final Float32List drawPositions = Float32List(triangleCount * 6);
  late final Int32List drawColors = Int32List(triangleCount * 3);
}

/// Lazily-built, cached solid meshes for one parsed model.
class SolidScene {
  SolidScene._(ParsedModel model) : _source = _Source.collect(model);

  static final Expando<SolidScene> _cache = Expando<SolidScene>('solidScene');

  static SolidScene of(ParsedModel model) =>
      _cache[model] ??= SolidScene._(model);

  final _Source _source;

  bool get isEmpty => _source.totalTriangles == 0;

  /// Detailed mesh used while the camera is still.
  late final SolidMesh full = _source.build(
    targetTriangles: 120000,
    maxEdgeFraction: 0.07,
  );

  /// Stable mesh used while orbiting or on the turntable.
  /// Avoid decimating geometry while orbiting so parts never disappear or pop.
  late final SolidMesh interactive = full;
}

class _Part {
  _Part(this.nodeIndex, this.kind, this.vertices, this.triangles);

  final int nodeIndex;
  final int kind;
  final List<Vec3> vertices;
  final List<Triangle> triangles;
}

class _Source {
  _Source._(
    this.parts,
    this.totalTriangles,
    this.minX,
    this.minY,
    this.minZ,
    this.diagonal,
  );

  final List<_Part> parts;
  final int totalTriangles;
  final double minX;
  final double minY;
  final double minZ;
  final double diagonal;

  static _Source collect(ParsedModel model) {
    final parts = <_Part>[];
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    var total = 0;

    final mbb = model.worldBBox;
    final modelHeight = max(0.01, mbb.size.y);
    final modelWidth = max(0.01, mbb.size.x);
    final modelLength = max(0.01, mbb.size.z);

    for (final instance in model.instances) {
      if (instance.triangles.isEmpty || instance.worldVertices.isEmpty) {
        continue;
      }
      final nodeName =
          instance.nodeIndex >= 0 && instance.nodeIndex < model.nodes.length
              ? model.nodes[instance.nodeIndex].name.toLowerCase()
              : '';
      final meshName =
          instance.meshIndex >= 0 && instance.meshIndex < model.meshes.length
              ? model.meshes[instance.meshIndex].name.toLowerCase()
              : '';
      final combinedName = '$nodeName $meshName';

      final bb = instance.worldBBox;
      final relY = (bb.center.y - mbb.lo.y) / modelHeight;
      final relX = (bb.center.x - mbb.center.x).abs() / (modelWidth * 0.5);
      final relZ = (bb.center.z - mbb.center.z).abs() / (modelLength * 0.5);

      final hasWheelName = RegExp(
        r'(wheel|tire|tyre|rim|alloy|spoke|whl|rad|roue|rueda)',
      ).hasMatch(combinedName) &&
          !RegExp(
            r'(steering|arch|well|fender|guard|mudguard)',
          ).hasMatch(combinedName);
      final hasGlassName = RegExp(
        r'(glass|window|windshield|windscreen|visor|gls|wnd|sunroof|canopy|screen)',
      ).hasMatch(combinedName);
      final hasHeadlightName = RegExp(
        r'(headlight|headlamp|front_light|light_front|drl|front.*lamp|lens)',
      ).hasMatch(combinedName);
      final hasTaillightName = RegExp(
        r'(taillight|taillamp|tail_light|rear_light|light_rear|brake_light|red.*light)',
      ).hasMatch(combinedName);
      final hasInteriorName = RegExp(
        r'(interior|cockpit|seat|dash|dashboard|steering|console|carpet|cabin)',
      ).hasMatch(combinedName);
      final hasTrimName = RegExp(
        r'(carbon|trim|grill|grille|radiator|mesh|intake|diffuser|splitter|exhaust|muffler|spoiler|wing|mirror)',
      ).hasMatch(combinedName);
      final hasChassisName = RegExp(
        r'(chassis|underbody|undercarriage|suspension|subframe|axle)',
      ).hasMatch(combinedName);

      // Geometric classification fallback for models with unnamed or generic nodes/meshes:
      final isGeometricWheel = !hasGlassName &&
          !hasInteriorName &&
          relY < 0.48 &&
          relX > 0.45 &&
          bb.size.y < 0.60 * modelHeight &&
          bb.size.x < 0.48 * modelWidth &&
          bb.size.z < 0.42 * modelLength;

      final isGeometricChassis = !hasWheelName &&
          !hasGlassName &&
          relY < 0.22 &&
          relX < 0.42;

      final isGeometricGlass = !hasWheelName &&
          relY > 0.48 &&
          relX < 0.85 &&
          relZ < 0.82 &&
          (combinedName.contains('glass') ||
              combinedName.contains('wnd') ||
              combinedName.contains('gls'));

      int kind = solidKindBody;
      if (hasWheelName || isGeometricWheel) {
        kind = solidKindWheel;
      } else if (hasGlassName || isGeometricGlass) {
        kind = solidKindGlass;
      } else if (hasHeadlightName) {
        kind = solidKindHeadlight;
      } else if (hasTaillightName) {
        kind = solidKindTaillight;
      } else if (hasInteriorName) {
        kind = solidKindInterior;
      } else if (hasTrimName) {
        kind = solidKindTrim;
      } else if (hasChassisName || isGeometricChassis) {
        kind = solidKindChassis;
      }

      for (final v in instance.worldVertices) {
        if (!v.x.isFinite || !v.y.isFinite || !v.z.isFinite) continue;
        minX = min(minX, v.x);
        minY = min(minY, v.y);
        minZ = min(minZ, v.z);
        maxX = max(maxX, v.x);
        maxY = max(maxY, v.y);
        maxZ = max(maxZ, v.z);
      }
      parts.add(
        _Part(instance.nodeIndex, kind, instance.worldVertices, instance.triangles),
      );
      total += instance.triangles.length;
    }

    if (minX > maxX) {
      minX = minY = minZ = 0;
      maxX = maxY = maxZ = 0;
    }
    final dx = maxX - minX, dy = maxY - minY, dz = maxZ - minZ;
    return _Source._(
      parts,
      total,
      minX,
      minY,
      minZ,
      sqrt(dx * dx + dy * dy + dz * dz),
    );
  }

  SolidMesh build({
    required int targetTriangles,
    required double maxEdgeFraction,
  }) {
    final builder = _MeshBuilder();
    final cell = totalTriangles > targetTriangles
        ? _chooseCell(targetTriangles)
        : 0.0;

    for (final part in parts) {
      if (cell > 0) {
        _addClustered(builder, part, cell);
      } else {
        _addDirect(builder, part);
      }
    }

    // Only subdivide coarse low-poly meshes (< 3,000 triangles) where large
    // triangles cause depth sorting artifacts. Avoid subdividing models that
    // already have high geometric resolution, as it distorts authentic body lines.
    if (diagonal > 1e-9 && totalTriangles < 3000) {
      builder.subdivide(
        maxEdge: diagonal * maxEdgeFraction,
        cap: (targetTriangles * 1.6).ceil(),
      );
    }
    return builder.finish();
  }

  // ── Vertex clustering ───────────────────────────────────────────────────

  int _cellKey(Vec3 v, double cell) {
    if (!v.x.isFinite || !v.y.isFinite || !v.z.isFinite) return -1;
    final ix = ((v.x - minX) / cell).floor().clamp(0, 4095).toInt();
    final iy = ((v.y - minY) / cell).floor().clamp(0, 4095).toInt();
    final iz = ((v.z - minZ) / cell).floor().clamp(0, 4095).toInt();
    return (ix * 4096 + iy) * 4096 + iz;
  }

  /// Number of triangles that survive clustering at the given cell size.
  int _countClustered(double cell) {
    var count = 0;
    for (final part in parts) {
      final verts = part.vertices;
      final keys = List<int>.generate(
        verts.length,
        (i) => _cellKey(verts[i], cell),
        growable: false,
      );
      for (final t in part.triangles) {
        if (t.a >= keys.length || t.b >= keys.length || t.c >= keys.length) {
          continue;
        }
        final ka = keys[t.a], kb = keys[t.b], kc = keys[t.c];
        if (ka < 0 || kb < 0 || kc < 0) continue;
        if (ka != kb && kb != kc && ka != kc) count++;
      }
    }
    return count;
  }

  /// Finds the finest grid whose clustered triangle count fits the target.
  double _chooseCell(int target) {
    var resolution = 300.0;
    for (var i = 0; i < 12; i++) {
      final cell = diagonal / resolution;
      if (cell <= 0) return 0.0;
      final count = _countClustered(cell);
      if (count <= target || resolution <= 8.0) return cell;
      resolution = max(8.0, resolution * max(0.5, sqrt(target / count) * 0.97));
    }
    return diagonal / resolution;
  }

  void _addClustered(_MeshBuilder b, _Part part, double cell) {
    final verts = part.vertices;
    final ids = Int32List(verts.length);
    final map = <int, int>{};
    final sumX = <double>[], sumY = <double>[], sumZ = <double>[];
    final counts = <int>[];

    for (var i = 0; i < verts.length; i++) {
      final key = _cellKey(verts[i], cell);
      if (key < 0) {
        ids[i] = -1;
        continue;
      }
      var id = map[key];
      if (id == null) {
        id = counts.length;
        map[key] = id;
        sumX.add(0);
        sumY.add(0);
        sumZ.add(0);
        counts.add(0);
      }
      sumX[id] += verts[i].x;
      sumY[id] += verts[i].y;
      sumZ[id] += verts[i].z;
      counts[id]++;
      ids[i] = id;
    }

    final base = b.vertexCount;
    for (var id = 0; id < counts.length; id++) {
      final n = counts[id];
      b.addVertex(sumX[id] / n, sumY[id] / n, sumZ[id] / n);
    }

    for (final t in part.triangles) {
      if (t.a >= ids.length || t.b >= ids.length || t.c >= ids.length) {
        continue;
      }
      final ia = ids[t.a], ib = ids[t.b], ic = ids[t.c];
      if (ia < 0 || ib < 0 || ic < 0) continue;
      if (ia == ib || ib == ic || ia == ic) continue;
      b.addTriangle(
        base + ia,
        base + ib,
        base + ic,
        part.nodeIndex,
        part.kind,
        t.color?.toARGB32() ?? 0,
      );
    }
  }

  void _addDirect(_MeshBuilder b, _Part part) {
    final verts = part.vertices;
    final base = b.vertexCount;
    for (final v in verts) {
      b.addVertex(v.x, v.y, v.z);
    }
    for (final t in part.triangles) {
      if (t.a >= verts.length || t.b >= verts.length || t.c >= verts.length) {
        continue;
      }
      b.addTriangle(
        base + t.a,
        base + t.b,
        base + t.c,
        part.nodeIndex,
        part.kind,
        t.color?.toARGB32() ?? 0,
      );
    }
  }
}

class _MeshBuilder {
  final List<double> pos = <double>[];
  List<int> idx = <int>[];
  List<int> node = <int>[];
  List<int> kind = <int>[];
  List<int> color = <int>[];

  int get vertexCount => pos.length ~/ 3;

  int addVertex(double x, double y, double z) {
    final index = vertexCount;
    pos
      ..add(x)
      ..add(y)
      ..add(z);
    return index;
  }

  void addTriangle(int a, int b, int c, int n, int k, int col) {
    idx
      ..add(a)
      ..add(b)
      ..add(c);
    node.add(n);
    kind.add(k);
    color.add(col);
  }

  double _distSq(int a, int b) {
    final dx = pos[a * 3] - pos[b * 3];
    final dy = pos[a * 3 + 1] - pos[b * 3 + 1];
    final dz = pos[a * 3 + 2] - pos[b * 3 + 2];
    return dx * dx + dy * dy + dz * dz;
  }

  final Map<int, int> _midpoints = <int, int>{};

  int _midpoint(int a, int b) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    final key = lo * 8388608 + hi;
    final cached = _midpoints[key];
    if (cached != null) return cached;
    final index = addVertex(
      (pos[a * 3] + pos[b * 3]) * 0.5,
      (pos[a * 3 + 1] + pos[b * 3 + 1]) * 0.5,
      (pos[a * 3 + 2] + pos[b * 3 + 2]) * 0.5,
    );
    _midpoints[key] = index;
    return index;
  }

  /// Splits every triangle that has an edge longer than [maxEdge] by
  /// bisecting its longest edge, preserving winding. Stops adding triangles
  /// once the total would reach [cap].
  void subdivide({required double maxEdge, required int cap}) {
    final maxSq = maxEdge * maxEdge;
    final originalCount = idx.length ~/ 3;

    final outIdx = <int>[];
    final outNode = <int>[];
    final outKind = <int>[];
    final outColor = <int>[];
    final stack = <int>[]; // a, b, c, depth

    for (var t = 0; t < originalCount; t++) {
      final n = node[t], k = kind[t], col = color[t];
      stack
        ..add(idx[t * 3])
        ..add(idx[t * 3 + 1])
        ..add(idx[t * 3 + 2])
        ..add(0);

      while (stack.isNotEmpty) {
        final depth = stack.removeLast();
        final c = stack.removeLast();
        final b = stack.removeLast();
        final a = stack.removeLast();

        final lab = _distSq(a, b);
        final lbc = _distSq(b, c);
        final lca = _distSq(c, a);
        final longest = max(lab, max(lbc, lca));

        final produced = outIdx.length ~/ 3;
        final pending = stack.length ~/ 4;
        final remaining = originalCount - t - 1;
        final canSplit = longest.isFinite &&
            longest > maxSq &&
            depth < 6 &&
            produced + pending + remaining + 2 < cap;

        if (!canSplit) {
          outIdx
            ..add(a)
            ..add(b)
            ..add(c);
          outNode.add(n);
          outKind.add(k);
          outColor.add(col);
          continue;
        }

        final d = depth + 1;
        if (longest == lab) {
          final m = _midpoint(a, b);
          stack
            ..addAll([m, b, c, d])
            ..addAll([a, m, c, d]);
        } else if (longest == lbc) {
          final m = _midpoint(b, c);
          stack
            ..addAll([a, m, c, d])
            ..addAll([a, b, m, d]);
        } else {
          final m = _midpoint(c, a);
          stack
            ..addAll([m, b, c, d])
            ..addAll([a, b, m, d]);
        }
      }
    }

    idx = outIdx;
    node = outNode;
    kind = outKind;
    color = outColor;
  }

  SolidMesh finish() {
    final triTotal = idx.length ~/ 3;
    final verts = vertexCount;

    final positions = Float32List(verts * 3);
    for (var i = 0; i < positions.length; i++) {
      positions[i] = pos[i];
    }

    final indices = Int32List(triTotal * 3);
    final normals = Float32List(triTotal * 3);
    final centroids = Float32List(triTotal * 3);
    final triNode = Int32List(triTotal);
    final triKind = Uint8List(triTotal);
    final triColor = Int32List(triTotal);

    var out = 0;
    for (var t = 0; t < triTotal; t++) {
      final a = idx[t * 3], b = idx[t * 3 + 1], c = idx[t * 3 + 2];
      final ax = pos[a * 3], ay = pos[a * 3 + 1], az = pos[a * 3 + 2];
      final bx = pos[b * 3], by = pos[b * 3 + 1], bz = pos[b * 3 + 2];
      final cx = pos[c * 3], cy = pos[c * 3 + 1], cz = pos[c * 3 + 2];

      final e1x = bx - ax, e1y = by - ay, e1z = bz - az;
      final e2x = cx - ax, e2y = cy - ay, e2z = cz - az;
      final nx = e1y * e2z - e1z * e2y;
      final ny = e1z * e2x - e1x * e2z;
      final nz = e1x * e2y - e1y * e2x;
      final lenSq = nx * nx + ny * ny + nz * nz;
      // Also rejects NaN, since NaN > x is false.
      if (!(lenSq > 1e-16)) continue;
      final inv = 1.0 / sqrt(lenSq);

      final o3 = out * 3;
      indices[o3] = a;
      indices[o3 + 1] = b;
      indices[o3 + 2] = c;
      normals[o3] = nx * inv;
      normals[o3 + 1] = ny * inv;
      normals[o3 + 2] = nz * inv;
      centroids[o3] = (ax + bx + cx) / 3.0;
      centroids[o3 + 1] = (ay + by + cy) / 3.0;
      centroids[o3 + 2] = (az + bz + cz) / 3.0;
      triNode[out] = node[t];
      triKind[out] = kind[t];
      triColor[out] = color[t];
      out++;
    }

    return SolidMesh(
      vertexCount: verts,
      triangleCount: out,
      positions: positions,
      indices: Int32List.sublistView(indices, 0, out * 3),
      normals: Float32List.sublistView(normals, 0, out * 3),
      centroids: Float32List.sublistView(centroids, 0, out * 3),
      triNode: Int32List.sublistView(triNode, 0, out),
      triKind: Uint8List.sublistView(triKind, 0, out),
      triColor: Int32List.sublistView(triColor, 0, out),
    );
  }
}
