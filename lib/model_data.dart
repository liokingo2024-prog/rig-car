import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

// ── 3D Math ─────────────────────────────────────────────────────────────────

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
  static const zero = Vec3(0, 0, 0);
  static const one = Vec3(1, 1, 1);
  static const up = Vec3(0, 1, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  double get length => sqrt(x * x + y * y + z * z);
  double get lengthSquared => x * x + y * y + z * z;

  Vec3 get normalized {
    final len = length;
    if (len < 1e-10) return Vec3.zero;
    return this * (1.0 / len);
  }

  Vec3 min(Vec3 o) =>
      Vec3(x < o.x ? x : o.x, y < o.y ? y : o.y, z < o.z ? z : o.z);
  Vec3 max(Vec3 o) =>
      Vec3(x > o.x ? x : o.x, y > o.y ? y : o.y, z > o.z ? z : o.z);

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(3)}, '
      '${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

class Quat {
  final double x, y, z, w;
  const Quat(this.x, this.y, this.z, this.w);
  static const identity = Quat(0, 0, 0, 1);

  /// Convert to a 4×4 column-major rotation matrix.
  Mat4 toRotationMatrix() {
    final xx = x * x, yy = y * y, zz = z * z;
    final xy = x * y, xz = x * z, yz = y * z;
    final wx = w * x, wy = w * y, wz = w * z;
    return Mat4(<double>[
      1 - 2 * (yy + zz),
      2 * (xy + wz),
      2 * (xz - wy),
      0,
      2 * (xy - wz),
      1 - 2 * (xx + zz),
      2 * (yz + wx),
      0,
      2 * (xz + wy),
      2 * (yz - wx),
      1 - 2 * (xx + yy),
      0,
      0,
      0,
      0,
      1,
    ]);
  }
}

/// 4×4 matrix stored **column-major**: `m[col * 4 + row]`.
class Mat4 {
  final List<double> m;
  Mat4(this.m) : assert(m.length == 16);

  static Mat4 identity() =>
      Mat4([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  static Mat4 uniformScaleTranslate(double scale, Vec3 offset) => Mat4([
    scale,
    0,
    0,
    0,
    0,
    scale,
    0,
    0,
    0,
    0,
    scale,
    0,
    offset.x,
    offset.y,
    offset.z,
    1,
  ]);

  Vec3 get translation => Vec3(m[12], m[13], m[14]);

  Vec3 transformPoint(Vec3 v) {
    final w = m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15];
    final iw = w.abs() < 1e-15 ? 1.0 : 1.0 / w;
    return Vec3(
      (m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12]) * iw,
      (m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13]) * iw,
      (m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14]) * iw,
    );
  }

  /// Returns clip-space `[x, y, z, w]` without perspective divide.
  Float64List transformClip(Vec3 v) => Float64List.fromList([
    m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12],
    m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13],
    m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14],
    m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15],
  ]);

  Mat4 operator *(Mat4 o) {
    final r = List<double>.filled(16, 0.0);
    for (var col = 0; col < 4; col++) {
      for (var row = 0; row < 4; row++) {
        var s = 0.0;
        for (var k = 0; k < 4; k++) {
          s += m[k * 4 + row] * o.m[col * 4 + k];
        }
        r[col * 4 + row] = s;
      }
    }
    return Mat4(r);
  }

  /// Determinant of the upper-left 3×3 rotation/scale submatrix.
  /// A negative value indicates reflection (inverted polygon winding).
  double get determinant3x3 =>
      m[0] * (m[5] * m[10] - m[6] * m[9]) -
      m[4] * (m[1] * m[10] - m[2] * m[9]) +
      m[8] * (m[1] * m[6] - m[2] * m[5]);

  static Mat4 fromTRS(Vec3 t, Quat r, Vec3 s) {
    final rot = r.toRotationMatrix();
    return Mat4([
      rot.m[0] * s.x,
      rot.m[1] * s.x,
      rot.m[2] * s.x,
      0,
      rot.m[4] * s.y,
      rot.m[5] * s.y,
      rot.m[6] * s.y,
      0,
      rot.m[8] * s.z,
      rot.m[9] * s.z,
      rot.m[10] * s.z,
      0,
      t.x,
      t.y,
      t.z,
      1,
    ]);
  }

  static Mat4 lookAt(Vec3 eye, Vec3 target, Vec3 upHint) {
    final f = (target - eye).normalized;
    final r = f.cross(upHint).normalized;
    final u = r.cross(f);
    return Mat4([
      r.x,
      u.x,
      -f.x,
      0,
      r.y,
      u.y,
      -f.y,
      0,
      r.z,
      u.z,
      -f.z,
      0,
      -r.dot(eye),
      -u.dot(eye),
      f.dot(eye),
      1,
    ]);
  }

  static Mat4 perspective(double fovY, double aspect, double near, double far) {
    final f = 1.0 / tan(fovY / 2);
    final nf = 1.0 / (near - far);
    return Mat4([
      f / aspect,
      0,
      0,
      0,
      0,
      f,
      0,
      0,
      0,
      0,
      (far + near) * nf,
      -1,
      0,
      0,
      2 * far * near * nf,
      0,
    ]);
  }
}

// ── Bounding Box ────────────────────────────────────────────────────────────

class BBox {
  final Vec3 lo;
  final Vec3 hi;
  const BBox(this.lo, this.hi);

  static const empty = BBox(
    Vec3(double.infinity, double.infinity, double.infinity),
    Vec3(
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity,
    ),
  );

  Vec3 get center => (lo + hi) * 0.5;
  Vec3 get size => hi - lo;
  double get diagonal => size.length;

  BBox expandToInclude(Vec3 p) => BBox(lo.min(p), hi.max(p));

  static BBox fromPoints(List<Vec3> pts) {
    var b = BBox.empty;
    for (final p in pts) {
      b = b.expandToInclude(p);
    }
    return b;
  }

  static BBox union(List<BBox> boxes) {
    var b = BBox.empty;
    for (final box in boxes) {
      b = BBox(b.lo.min(box.lo), b.hi.max(box.hi));
    }
    return b;
  }
}

// ── Edge ────────────────────────────────────────────────────────────────────

/// A directed edge stored with ordered indices for deduplication.
class Edge {
  final int a, b;
  Edge(int v0, int v1) : a = v0 < v1 ? v0 : v1, b = v0 < v1 ? v1 : v0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Edge && a == other.a && b == other.b;
  @override
  int get hashCode => Object.hash(a, b);
}

/// A triangle in a mesh's local vertex index space.
class Triangle {
  final int a, b, c;
  final Color? color;
  const Triangle(this.a, this.b, this.c, [this.color]);
}

// ── Picked File ─────────────────────────────────────────────────────────────

class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
}

// ── Scene Graph ─────────────────────────────────────────────────────────────

class SceneNode {
  final int index;
  final String name;
  final Mat4 localTransform;
  int? meshIndex;
  final List<int> childIndices;
  final int? parentIndex;
  Mat4 worldTransform;

  SceneNode({
    required this.index,
    required this.name,
    required this.localTransform,
    required this.meshIndex,
    required this.childIndices,
    required this.parentIndex,
    Mat4? worldTransform,
  }) : worldTransform = worldTransform ?? Mat4.identity();
}

class MeshData {
  final int index;
  final String name;
  final List<Vec3> vertices;
  final List<Edge> edges;
  final List<Triangle> triangles;
  final BBox bbox;

  const MeshData({
    required this.index,
    required this.name,
    required this.vertices,
    required this.edges,
    this.triangles = const [],
    required this.bbox,
  });
}

/// A mesh instantiated in world space by a particular scene node.
class MeshInstance {
  final int nodeIndex;
  final int meshIndex;
  List<Vec3> worldVertices;
  final List<Edge> edges;
  final List<Triangle> triangles;
  BBox worldBBox;

  MeshInstance({
    required this.nodeIndex,
    required this.meshIndex,
    required this.worldVertices,
    required this.edges,
    this.triangles = const [],
    required this.worldBBox,
  });
}

class ParsedModel {
  final String fileName;
  final List<SceneNode> nodes;
  final List<MeshData> meshes;
  List<MeshInstance> instances;
  final List<int> rootNodeIndices;
  BBox worldBBox;

  ParsedModel({
    required this.fileName,
    required this.nodes,
    required this.meshes,
    required this.instances,
    required this.rootNodeIndices,
    required this.worldBBox,
  });

  /// Returns a normalized copy for rigging and viewport display.
  ///
  /// Imported assets commonly use millimeters, centimeters, or arbitrary
  /// authoring units. This maps the largest horizontal vehicle dimension to
  /// [targetFootprint] meters, centers X/Z on the origin, and places the
  /// lowest geometry on Y=0. Local mesh data stays untouched; world-space
  /// nodes and instances are transformed together so detection, rendering,
  /// manual assignment, and Godot export use the same coordinates.
  ParsedModel normalizedForRigging({double targetFootprint = 4.2}) {
    if (instances.isEmpty || targetFootprint <= 0) return this;

    final size = worldBBox.size;
    final horizontal = max(size.x.abs(), size.z.abs());
    if (horizontal < 1e-9) return this;

    final scale = targetFootprint / horizontal;
    final offset = Vec3(
      -worldBBox.center.x * scale,
      -worldBBox.lo.y * scale,
      -worldBBox.center.z * scale,
    );
    if ((scale - 1).abs() < 0.0001 && offset.lengthSquared < 0.0001) {
      return this;
    }
    final normalization = Mat4.uniformScaleTranslate(scale, offset);
    Vec3 normalizePoint(Vec3 point) => normalization.transformPoint(point);

    final normalizedNodes = nodes.map((node) {
      return SceneNode(
        index: node.index,
        name: node.name,
        localTransform: node.localTransform,
        meshIndex: node.meshIndex,
        childIndices: node.childIndices,
        parentIndex: node.parentIndex,
        worldTransform: normalization * node.worldTransform,
      );
    }).toList();

    final normalizedInstances = instances.map((instance) {
      final vertices = instance.worldVertices.map(normalizePoint).toList();
      final bounds = vertices.isEmpty
          ? _normalizeBounds(instance.worldBBox, normalizePoint)
          : BBox.fromPoints(vertices);
      return MeshInstance(
        nodeIndex: instance.nodeIndex,
        meshIndex: instance.meshIndex,
        worldVertices: vertices,
        edges: instance.edges,
        triangles: instance.triangles,
        worldBBox: bounds,
      );
    }).toList();

    return ParsedModel(
      fileName: fileName,
      nodes: normalizedNodes,
      meshes: meshes,
      instances: normalizedInstances,
      rootNodeIndices: rootNodeIndices,
      worldBBox: BBox.union(
        normalizedInstances.map((instance) => instance.worldBBox).toList(),
      ),
    );
  }

  /// Normalizes this parsed model without allocating a second full copy of
  /// every world vertex. This is the upload path used by the web workbench.
  void normalizeForRiggingInPlace({double targetFootprint = 4.2}) {
    if (instances.isEmpty || targetFootprint <= 0) return;

    final size = worldBBox.size;
    final horizontal = max(size.x.abs(), size.z.abs());
    if (horizontal < 1e-9) return;

    final scale = targetFootprint / horizontal;
    final offset = Vec3(
      -worldBBox.center.x * scale,
      -worldBBox.lo.y * scale,
      -worldBBox.center.z * scale,
    );
    if ((scale - 1).abs() < 0.0001 && offset.lengthSquared < 0.0001) {
      return;
    }

    final normalization = Mat4.uniformScaleTranslate(scale, offset);
    for (final node in nodes) {
      node.worldTransform = normalization * node.worldTransform;
    }
    for (final instance in instances) {
      instance.worldVertices = List<Vec3>.generate(
        instance.worldVertices.length,
        (i) => normalization.transformPoint(instance.worldVertices[i]),
      );
      instance.worldBBox = instance.worldVertices.isEmpty
          ? _normalizeBounds(instance.worldBBox, normalization.transformPoint)
          : BBox.fromPoints(instance.worldVertices);
    }
    worldBBox = BBox.union(
      instances.map((instance) => instance.worldBBox).toList(),
    );
  }

  /// Rotates the model around the vertical Y axis by [angleRadians].
  void rotateYaw(double angleRadians) {
    if (instances.isEmpty) return;
    final cosA = cos(angleRadians);
    final sinA = sin(angleRadians);
    final rot = Mat4([
      cosA, 0, -sinA, 0,
      0, 1, 0, 0,
      sinA, 0, cosA, 0,
      0, 0, 0, 1,
    ]);
    for (final node in nodes) {
      node.worldTransform = rot * node.worldTransform;
    }
    for (final instance in instances) {
      instance.worldVertices = List<Vec3>.generate(
        instance.worldVertices.length,
        (i) {
          final p = instance.worldVertices[i];
          return Vec3(
            p.x * cosA + p.z * sinA,
            p.y,
            -p.x * sinA + p.z * cosA,
          );
        },
      );
      instance.worldBBox = instance.worldVertices.isEmpty
          ? _normalizeBounds(instance.worldBBox, rot.transformPoint)
          : BBox.fromPoints(instance.worldVertices);
    }
    worldBBox = BBox.union(
      instances.map((instance) => instance.worldBBox).toList(),
    );
  }

  /// Flips vehicle front to back (180 degree yaw rotation).
  void flipFrontBack() {
    rotateYaw(pi);
  }

  /// Pre-detection pass to eliminate floor planes, shadow meshes, pedestals, or turntables
  /// that sit at the bottom of the bounding box and distort car dimensions before wheel detection.
  int purgeGroundFloorPrePass() {
    if (instances.length <= 1) return 0;
    final carH = max(0.2, worldBBox.size.y.abs());
    final groundY = worldBBox.lo.y;
    final floorPattern = RegExp(
      r'(shadow|ground|floor|plane|turntable|pedestal|stage|platform|base|backdrop|grid|plinth|stand)',
      caseSensitive: false,
    );

    final nodesToRemove = <int>{};
    final remainingInstances = <MeshInstance>[];
    bool removedMassivePlatform = false;

    for (final inst in instances) {
      final nodeName = inst.nodeIndex >= 0 && inst.nodeIndex < nodes.length
          ? nodes[inst.nodeIndex].name
          : '';
      final b = inst.worldBBox;
      final h = b.size.y.abs();
      final namedFloor = floorPattern.hasMatch(nodeName);

      // Thin floor sitting at the very bottom of the model
      final sitsAtBottom = b.lo.y <= groundY + 0.05;
      final isFlatThin = h <= max(0.08, 0.06 * carH);
      final isPlatform = namedFloor && b.hi.y <= groundY + 0.20 * carH && h <= 0.25 * carH;

      // Huge wide thin plane (larger horizontal footprint than typical car part, very flat)
      final isHugePlane = sitsAtBottom && isFlatThin &&
          (b.size.x >= 0.80 * worldBBox.size.x || b.size.z >= 0.80 * worldBBox.size.z);

      if ((namedFloor && sitsAtBottom) || isPlatform || (isHugePlane && namedFloor) || (isHugePlane && h <= 0.04)) {
        nodesToRemove.add(inst.nodeIndex);
        if (isPlatform || isHugePlane) {
          removedMassivePlatform = true;
        }
      } else {
        remainingInstances.add(inst);
      }
    }

    final removedCount = instances.length - remainingInstances.length;
    if (removedCount > 0 && remainingInstances.isNotEmpty) {
      instances.clear();
      instances.addAll(remainingInstances);
      for (final nodeIdx in nodesToRemove) {
        if (nodeIdx >= 0 && nodeIdx < nodes.length) {
          nodes[nodeIdx].meshIndex = null;
        }
      }
      worldBBox = BBox.union(instances.map((i) => i.worldBBox).toList());
      if (removedMassivePlatform) {
        normalizeForRiggingInPlace();
      }
    }
    return removedCount;
  }

  /// Detects and removes any under-wheel object meshes (e.g. shadow planes,
  /// showroom ground quads, turntables, pedestals) located beneath or flush
  /// with tire contact ($Y \le Y_{wheelMin} + 0.045$).
  /// Never deletes wheel meshes or significant body structures.
  int deleteUnderWheelObjects(List<DetectedWheel> wheels) {
    if (instances.isEmpty) return 0;

    // 1. Calculate lowest tire contact level
    var minTireY = double.infinity;
    for (final w in wheels) {
      minTireY = min(minTireY, w.worldPosition.y - w.radius);
    }

    final wheelNodeIndices = wheels
        .expand((w) => w.partNodeIndices.isEmpty ? [w.nodeIndex] : w.partNodeIndices)
        .toSet();
    for (final inst in instances) {
      if (wheelNodeIndices.contains(inst.nodeIndex) && inst.worldVertices.isNotEmpty) {
        minTireY = min(minTireY, inst.worldBBox.lo.y);
      }
    }

    if (minTireY.isInfinite) {
      minTireY = worldBBox.lo.y;
    }

    final carH = max(0.2, worldBBox.size.y.abs());
    final underWheelPattern = RegExp(
      r'(shadow|ground|floor|plane|turntable|pedestal|stage|platform|base|backdrop|grid|plinth|stand)',
      caseSensitive: false,
    );

    final nodesToRemove = <int>{};
    final remainingInstances = <MeshInstance>[];

    for (final inst in instances) {
      final isWheelNode = wheelNodeIndices.contains(inst.nodeIndex);
      if (isWheelNode) {
        remainingInstances.add(inst);
        continue;
      }

      final nodeName = inst.nodeIndex >= 0 && inst.nodeIndex < nodes.length
          ? nodes[inst.nodeIndex].name
          : '';
      final b = inst.worldBBox;
      final h = b.size.y.abs();
      final namedFloorOrShadow = underWheelPattern.hasMatch(nodeName);

      // Criteria for under-wheel object:
      // A: Sits at or below the wheel contact level + 0.045m tolerance
      final sitsUnderWheel = b.hi.y <= minTireY + 0.045;
      final isFlatThin = h <= max(0.08, 0.07 * carH);
      final isPlatform = namedFloorOrShadow &&
          b.hi.y <= minTireY + 0.08 * carH &&
          h <= 0.25 * carH;

      if ((sitsUnderWheel && isFlatThin) || isPlatform || (namedFloorOrShadow && sitsUnderWheel)) {
        nodesToRemove.add(inst.nodeIndex);
      } else {
        remainingInstances.add(inst);
      }
    }

    final removedCount = instances.length - remainingInstances.length;
    if (removedCount > 0) {
      instances.clear();
      instances.addAll(remainingInstances);
      for (final nodeIdx in nodesToRemove) {
        if (nodeIdx >= 0 && nodeIdx < nodes.length) {
          nodes[nodeIdx].meshIndex = null;
        }
      }
      worldBBox = instances.isEmpty
          ? BBox.empty
          : BBox.union(instances.map((i) => i.worldBBox).toList());
    }

    return removedCount;
  }

  /// Guesses the vehicle's forward direction and aligns it strictly to -Z (Godot 4 standard).
  ///
  /// 1. If length is along X instead of Z (wheelbase spread along X > Z), rotates 90° yaw.
  /// 2. If front features, front wheel labels, or hood slope indicate forward is +Z, rotates 180° yaw.
  /// 3. Re-maps the 4 wheels' axle ('front'|'rear') and side ('left'|'right') based on final coordinates.
  AutoAxisResult autoAlignForwardAxis(List<DetectedWheel> wheels) {
    if (instances.isEmpty && wheels.isEmpty) {
      return const AutoAxisResult();
    }

    double totalYaw = 0.0;
    bool axisSwapped = false;

    // Step A: Check if longitudinal axis is currently along X instead of Z
    final spreadZ = wheels.length >= 2
        ? (wheels.map((w) => w.worldPosition.z).reduce(max) -
           wheels.map((w) => w.worldPosition.z).reduce(min))
        : worldBBox.size.z.abs();
    final spreadX = wheels.length >= 2
        ? (wheels.map((w) => w.worldPosition.x).reduce(max) -
           wheels.map((w) => w.worldPosition.x).reduce(min))
        : worldBBox.size.x.abs();

    if (spreadX > spreadZ * 1.15 ||
        (spreadZ < 0.2 && spreadX > 0.8) ||
        (worldBBox.size.x.abs() > worldBBox.size.z.abs() * 1.25)) {
      // Vehicle length is along X! Rotate 90° yaw (+pi/2) so length is along Z.
      rotateYaw(pi / 2);
      totalYaw += pi / 2;
      axisSwapped = true;

      // Rotate wheel positions by +pi/2 yaw: (x, y, z) -> (z, y, -x)
      for (final w in wheels) {
        w.worldPosition = Vec3(w.worldPosition.z, w.worldPosition.y, -w.worldPosition.x);
      }
    }

    // Step B: Guess Forward Direction (-Z vs +Z)
    var frontAtNegZScore = 0.0;
    var frontAtPosZScore = 0.0;

    final midZ = wheels.isNotEmpty
        ? (wheels.map((w) => w.worldPosition.z).reduce((a, b) => a + b) / wheels.length)
        : worldBBox.center.z;

    // 1. Wheel and part names
    final frontPattern = RegExp(
      r'(front|^fl$|^fr$|_f_|_fl|_fr|f_wheel|wheel_f|avant|vorne|delantero|steer)',
      caseSensitive: false,
    );
    final rearPattern = RegExp(
      r'(rear|back|^rl$|^rr$|_r_|_rl|_rr|r_wheel|wheel_r|arriere|hinten|trasero)',
      caseSensitive: false,
    );

    for (final w in wheels) {
      final isAtNegZ = w.worldPosition.z < midZ;
      final name = w.nodeName.toLowerCase();
      if (frontPattern.hasMatch(name)) {
        if (isAtNegZ) {
          frontAtNegZScore += 3.0;
        } else {
          frontAtPosZScore += 3.0;
        }
      } else if (rearPattern.hasMatch(name)) {
        if (isAtNegZ) {
          frontAtPosZScore += 3.0;
        } else {
          frontAtNegZScore += 3.0;
        }
      }
    }

    // 2. Scene nodes front vs rear features
    final frontFeaturePattern = RegExp(
      r'(headlight|head_light|headlamp|front_light|light_front|drl|grille|grill|radiator|hood|bonnet|bumper_f|front_bumper|front_grill|windshield|windscreen|steering_wheel|steeringwheel|dashboard|dash_|intercooler|front_lamp)',
      caseSensitive: false,
    );
    final rearFeaturePattern = RegExp(
      r'(taillight|tail_light|tail_lamp|taillamp|rear_light|light_rear|brake_light|exhaust|muffler|trunk|boot|bumper_r|rear_bumper|diffuser|spoiler|wing|plate_r|rear_plate)',
      caseSensitive: false,
    );

    // Use each node's mesh bounds rather than its pivot: exported models often
    // keep every pivot at the origin, which hides which end a light/grille is on.
    final nodeZCents = <int, double>{};
    for (final inst in instances) {
      final z = inst.worldBBox.center.z;
      final prev = nodeZCents[inst.nodeIndex];
      nodeZCents[inst.nodeIndex] =
          prev == null ? z : (prev * 0.5 + z * 0.5);
    }

    for (final node in nodes) {
      final z = nodeZCents[node.index] ?? node.worldTransform.translation.z;
      if (frontFeaturePattern.hasMatch(node.name)) {
        if (z < midZ) {
          frontAtNegZScore += 2.0;
        } else {
          frontAtPosZScore += 2.0;
        }
      }
      if (rearFeaturePattern.hasMatch(node.name)) {
        if (z > midZ) {
          frontAtNegZScore += 2.0;
        } else {
          frontAtPosZScore += 2.0;
        }
      }
    }

    // 3. Aerodynamic silhouette / hood slope (Y front < Y rear)
    final box = worldBBox;
    final zSpan = box.size.z.abs();
    if (zSpan > 0.5) {
      final negZThreshold = box.lo.z + zSpan * 0.22;
      final posZThreshold = box.hi.z - zSpan * 0.22;
      var maxTopNegZ = double.negativeInfinity;
      var maxTopPosZ = double.negativeInfinity;
      for (final inst in instances) {
        for (final v in inst.worldVertices) {
          if (v.z <= negZThreshold && v.y > maxTopNegZ) {
            maxTopNegZ = v.y;
          }
          if (v.z >= posZThreshold && v.y > maxTopPosZ) {
            maxTopPosZ = v.y;
          }
        }
      }
      if (maxTopNegZ.isFinite && maxTopPosZ.isFinite) {
        if (maxTopNegZ < maxTopPosZ - 0.08 * box.size.y.abs()) {
          // NegZ is lower hood -> front is at -Z (correct)
          frontAtNegZScore += 1.5;
        } else if (maxTopPosZ < maxTopNegZ - 0.08 * box.size.y.abs()) {
          // PosZ is lower hood -> front is at +Z (reversed)
          frontAtPosZScore += 1.5;
        }
      }
    }

    // 4. Staggered setup (wider rear tires)
    if (wheels.length == 4) {
      final negZWheels = wheels.where((w) => w.worldPosition.z < midZ).toList();
      final posZWheels = wheels.where((w) => w.worldPosition.z >= midZ).toList();
      if (negZWheels.length == 2 && posZWheels.length == 2) {
        final avgWNeg = (negZWheels[0].width + negZWheels[1].width) / 2;
        final avgWPos = (posZWheels[0].width + posZWheels[1].width) / 2;
        if (avgWPos > avgWNeg * 1.05) {
          // Wider at +Z means rear is +Z, front is -Z
          frontAtNegZScore += 1.0;
        } else if (avgWNeg > avgWPos * 1.05) {
          frontAtPosZScore += 1.0;
        }
      }
    }

    bool frontFlipped = false;
    if (frontAtPosZScore > frontAtNegZScore) {
      // Vehicle is pointing towards +Z (backwards). Flip 180° yaw so forward is -Z.
      rotateYaw(pi);
      totalYaw += pi;
      frontFlipped = true;

      // Rotate wheel positions by 180° yaw: (x, y, z) -> (-x, y, -z)
      for (final w in wheels) {
        w.worldPosition = Vec3(-w.worldPosition.x, w.worldPosition.y, -w.worldPosition.z);
      }
    }

    // Step C: Re-assign axle ('front'|'rear') and side ('left'|'right') for all wheels
    final finalMidZ = wheels.isNotEmpty
        ? (wheels.map((w) => w.worldPosition.z).reduce((a, b) => a + b) / wheels.length)
        : worldBBox.center.z;
    final finalMidX = wheels.isNotEmpty
        ? (wheels.map((w) => w.worldPosition.x).reduce((a, b) => a + b) / wheels.length)
        : worldBBox.center.x;

    for (final w in wheels) {
      w.axle = w.worldPosition.z <= finalMidZ ? 'front' : 'rear';
      w.side = w.worldPosition.x <= finalMidX ? 'left' : 'right';
    }

    return AutoAxisResult(
      yawRotatedRadians: totalYaw,
      axisSwapped: axisSwapped,
      frontFlipped: frontFlipped,
      forwardDirection: '-Z',
    );
  }

  /// Translates vehicle vertices, node transforms, and wheel positions vertically
  /// so that the lowest tire vertex touches ground level Y = 0.000000 exactly
  /// (zero height clearance between land and wheel).
  double snapWheelsToLand(List<DetectedWheel> wheels) {
    if (instances.isEmpty && wheels.isEmpty) return 0.0;

    var lowestTireY = double.infinity;
    for (final w in wheels) {
      lowestTireY = min(lowestTireY, w.worldPosition.y - w.radius);
    }

    final wheelNodeIndices = wheels
        .expand((w) => w.partNodeIndices.isEmpty ? [w.nodeIndex] : w.partNodeIndices)
        .toSet();
    for (final inst in instances) {
      if (wheelNodeIndices.contains(inst.nodeIndex) && inst.worldVertices.isNotEmpty) {
        lowestTireY = min(lowestTireY, inst.worldBBox.lo.y);
      }
    }

    if (lowestTireY.isInfinite) {
      lowestTireY = worldBBox.lo.y;
    }

    if (lowestTireY.abs() < 1e-6) return 0.0;

    final trans = Mat4.uniformScaleTranslate(1.0, Vec3(0, -lowestTireY, 0));
    for (final node in nodes) {
      node.worldTransform = trans * node.worldTransform;
    }
    for (final instance in instances) {
      instance.worldVertices = List<Vec3>.generate(
        instance.worldVertices.length,
        (i) => Vec3(instance.worldVertices[i].x, instance.worldVertices[i].y - lowestTireY, instance.worldVertices[i].z),
      );
      instance.worldBBox = instance.worldVertices.isEmpty
          ? _normalizeBounds(instance.worldBBox, trans.transformPoint)
          : BBox.fromPoints(instance.worldVertices);
    }
    worldBBox = BBox.union(
      instances.map((instance) => instance.worldBBox).toList(),
    );

    for (final w in wheels) {
      w.worldPosition = Vec3(w.worldPosition.x, w.worldPosition.y - lowestTireY, w.worldPosition.z);
    }

    return lowestTireY;
  }

  /// Snaps vehicle geometry so lowest tire vertices touch Y=0.0m.
  void snapToGround() {
    if (instances.isEmpty) return;
    final minY = worldBBox.lo.y;
    if (minY.abs() < 1e-4) return;
    final trans = Mat4.uniformScaleTranslate(1.0, Vec3(0, -minY, 0));
    for (final node in nodes) {
      node.worldTransform = trans * node.worldTransform;
    }
    for (final instance in instances) {
      instance.worldVertices = List<Vec3>.generate(
        instance.worldVertices.length,
        (i) => Vec3(instance.worldVertices[i].x, instance.worldVertices[i].y - minY, instance.worldVertices[i].z),
      );
      instance.worldBBox = instance.worldVertices.isEmpty
          ? _normalizeBounds(instance.worldBBox, trans.transformPoint)
          : BBox.fromPoints(instance.worldVertices);
    }
    worldBBox = BBox.union(
      instances.map((instance) => instance.worldBBox).toList(),
    );
  }

  static BBox _normalizeBounds(BBox bounds, Vec3 Function(Vec3) transform) {
    final corners = [
      Vec3(bounds.lo.x, bounds.lo.y, bounds.lo.z),
      Vec3(bounds.hi.x, bounds.lo.y, bounds.lo.z),
      Vec3(bounds.lo.x, bounds.hi.y, bounds.lo.z),
      Vec3(bounds.lo.x, bounds.lo.y, bounds.hi.z),
      Vec3(bounds.hi.x, bounds.hi.y, bounds.lo.z),
      Vec3(bounds.hi.x, bounds.lo.y, bounds.hi.z),
      Vec3(bounds.lo.x, bounds.hi.y, bounds.hi.z),
      Vec3(bounds.hi.x, bounds.hi.y, bounds.hi.z),
    ];
    return BBox.fromPoints(corners.map(transform).toList());
  }

  /// Creates a clean manifold procedural vehicle model with chassis and 4 wheels.
  /// Used as a fully functional default template so all workbench tools
  /// (rotation, flip, ground snap, scale) work seamlessly out of the box.
  static ParsedModel createProceduralDefault({
    String name = 'Apex GT Coupe',
    List<Vec3>? wheelPositions,
  }) {
    final bodyPoints = [
      const Vec3(-0.90, 0.18, -1.85), // 0: FL bottom
      const Vec3(0.90, 0.18, -1.85),  // 1: FR bottom
      const Vec3(0.90, 0.18, 1.85),   // 2: RR bottom
      const Vec3(-0.90, 0.18, 1.85),  // 3: RL bottom
      const Vec3(-0.85, 0.65, -1.65), // 4: FL hood
      const Vec3(0.85, 0.65, -1.65),  // 5: FR hood
      const Vec3(-0.80, 0.82, -0.60), // 6: FL windshield
      const Vec3(0.80, 0.82, -0.60),  // 7: FR windshield
      const Vec3(-0.65, 1.28, -0.15), // 8: FL roof front
      const Vec3(0.65, 1.28, -0.15),  // 9: FR roof front
      const Vec3(-0.65, 1.28, 0.75),  // 10: RL roof rear
      const Vec3(0.65, 1.28, 0.75),   // 11: RR roof rear
      const Vec3(-0.80, 0.82, 1.25),  // 12: RL rear window
      const Vec3(0.80, 0.82, 1.25),   // 13: RR rear window
      const Vec3(-0.85, 0.72, 1.80),  // 14: RL trunk
      const Vec3(0.85, 0.72, 1.80),   // 15: RR trunk
    ];

    final bodyTriangles = [
      const Triangle(4, 5, 1),
      const Triangle(4, 1, 0),
      const Triangle(4, 6, 7),
      const Triangle(4, 7, 5),
      const Triangle(6, 7, 9),
      const Triangle(6, 9, 8),
      const Triangle(8, 9, 11),
      const Triangle(8, 11, 10),
      const Triangle(10, 11, 13),
      const Triangle(10, 13, 12),
      const Triangle(12, 13, 15),
      const Triangle(12, 15, 14),
      const Triangle(14, 15, 2),
      const Triangle(14, 2, 3),
      const Triangle(0, 4, 6),
      const Triangle(0, 6, 3),
      const Triangle(6, 8, 10),
      const Triangle(6, 10, 12),
      const Triangle(3, 12, 14),
      const Triangle(1, 7, 5),
      const Triangle(1, 2, 7),
      const Triangle(7, 11, 9),
      const Triangle(7, 13, 11),
      const Triangle(2, 15, 13),
      const Triangle(0, 1, 2),
      const Triangle(0, 2, 3),
    ];

    final bodyEdges = [
      Edge(0, 1), Edge(1, 2), Edge(2, 3), Edge(3, 0),
      Edge(4, 5), Edge(6, 7), Edge(8, 9), Edge(10, 11),
      Edge(12, 13), Edge(14, 15),
      Edge(0, 4), Edge(4, 6), Edge(6, 8), Edge(8, 10),
      Edge(10, 12), Edge(12, 14), Edge(14, 3),
      Edge(1, 5), Edge(5, 7), Edge(7, 9), Edge(9, 11),
      Edge(11, 13), Edge(13, 15), Edge(15, 2),
    ];

    final chassisMesh = MeshData(
      index: 0,
      name: 'Body',
      vertices: bodyPoints,
      edges: bodyEdges,
      triangles: bodyTriangles,
      bbox: BBox.fromPoints(bodyPoints),
    );

    final chassisNode = SceneNode(
      index: 0,
      name: 'Body',
      localTransform: Mat4.identity(),
      meshIndex: 0,
      childIndices: const [],
      parentIndex: null,
      worldTransform: Mat4.identity(),
    );

    final chassisInstance = MeshInstance(
      nodeIndex: 0,
      meshIndex: 0,
      worldVertices: List.from(bodyPoints),
      edges: bodyEdges,
      triangles: bodyTriangles,
      worldBBox: chassisMesh.bbox,
    );

    final nodes = <SceneNode>[chassisNode];
    final meshes = <MeshData>[chassisMesh];
    final instances = <MeshInstance>[chassisInstance];
    final rootIndices = <int>[0, 1, 2, 3, 4];

    final defaultWheelPositions = wheelPositions ?? [
      const Vec3(-0.85, 0.34, -1.35),
      const Vec3(0.85, 0.34, -1.35),
      const Vec3(-0.85, 0.34, 1.35),
      const Vec3(0.85, 0.34, 1.35),
    ];

    const wheelNames = ['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'];
    const segments = 16;
    const r = 0.34;
    const w = 0.28;

    for (var wIdx = 0; wIdx < 4; wIdx++) {
      final center = defaultWheelPositions[wIdx];
      final isLeft = center.x < 0;
      final xOuter = isLeft ? center.x - w * 0.5 : center.x + w * 0.5;
      final xInner = isLeft ? center.x + w * 0.5 : center.x - w * 0.5;

      final wheelVerts = <Vec3>[];
      final wheelEdges = <Edge>[];
      final wheelTris = <Triangle>[];

      // 0: Outer center, 1: Inner center
      wheelVerts.add(Vec3(xOuter, center.y, center.z));
      wheelVerts.add(Vec3(xInner, center.y, center.z));

      // 2 .. 2+segments-1: Outer ring
      // 2+segments .. 2+2*segments-1: Inner ring
      for (var s = 0; s < segments; s++) {
        final angle = (s / segments) * 2 * pi;
        final dy = cos(angle) * r;
        final dz = sin(angle) * r;
        wheelVerts.add(Vec3(xOuter, center.y + dy, center.z + dz));
      }
      for (var s = 0; s < segments; s++) {
        final angle = (s / segments) * 2 * pi;
        final dy = cos(angle) * r;
        final dz = sin(angle) * r;
        wheelVerts.add(Vec3(xInner, center.y + dy, center.z + dz));
      }

      for (var s = 0; s < segments; s++) {
        final next = (s + 1) % segments;
        final o1 = 2 + s;
        final o2 = 2 + next;
        final i1 = 2 + segments + s;
        final i2 = 2 + segments + next;

        // Outer face (hub)
        wheelTris.add(Triangle(0, o1, o2));
        wheelEdges.add(Edge(o1, o2));

        // Inner face
        wheelTris.add(Triangle(1, i2, i1));
        wheelEdges.add(Edge(i1, i2));

        // Tread
        wheelTris.add(Triangle(o1, i1, o2));
        wheelTris.add(Triangle(o2, i1, i2));
        wheelEdges.add(Edge(o1, i1));
      }

      final meshIdx = wIdx + 1;
      final nodeIdx = wIdx + 1;
      final wMesh = MeshData(
        index: meshIdx,
        name: wheelNames[wIdx],
        vertices: wheelVerts,
        edges: wheelEdges,
        triangles: wheelTris,
        bbox: BBox.fromPoints(wheelVerts),
      );

      final wNode = SceneNode(
        index: nodeIdx,
        name: wheelNames[wIdx],
        localTransform: Mat4.identity(),
        meshIndex: meshIdx,
        childIndices: const [],
        parentIndex: null,
        worldTransform: Mat4.identity(),
      );

      final wInst = MeshInstance(
        nodeIndex: nodeIdx,
        meshIndex: meshIdx,
        worldVertices: List.from(wheelVerts),
        edges: wheelEdges,
        triangles: wheelTris,
        worldBBox: wMesh.bbox,
      );

      nodes.add(wNode);
      meshes.add(wMesh);
      instances.add(wInst);
    }

    final totalBBox = BBox.union(instances.map((i) => i.worldBBox).toList());

    return ParsedModel(
      fileName: '$name.glb',
      nodes: nodes,
      meshes: meshes,
      instances: instances,
      rootNodeIndices: rootIndices,
      worldBBox: totalBBox,
    );
  }
}

// ── Auto-detection Results ──────────────────────────────────────────────────

class DetectedWheel {
  final int nodeIndex;
  final String nodeName;
  Vec3 worldPosition;
  final double confidence;
  final int? meshIndex;

  /// All mesh nodes grouped into this wheel assembly. A wheel may contain
  /// separate tire, rim, hub, and brake meshes.
  final List<int> partNodeIndices;
  final List<String> partIds;
  final List<int> spinNodeIndices;
  final List<int> caliperHubNodeIndices;
  String axle; // 'front' | 'rear'
  String side; // 'left' | 'right'
  final double radius;
  final double width;
  final double circularity;
  final int subMeshCount;

  DetectedWheel({
    required this.nodeIndex,
    required this.nodeName,
    required this.worldPosition,
    required this.confidence,
    this.meshIndex,
    this.partNodeIndices = const [],
    this.partIds = const [],
    this.spinNodeIndices = const [],
    this.caliperHubNodeIndices = const [],
    this.axle = '',
    this.side = '',
    this.radius = 0.34,
    this.width = 0.25,
    this.circularity = 0.98,
    this.subMeshCount = 1,
  });

  DetectedWheel copyWith({
    int? nodeIndex,
    String? nodeName,
    Vec3? worldPosition,
    double? confidence,
    int? meshIndex,
    List<int>? partNodeIndices,
    List<String>? partIds,
    List<int>? spinNodeIndices,
    List<int>? caliperHubNodeIndices,
    String? axle,
    String? side,
    double? radius,
    double? width,
    double? circularity,
    int? subMeshCount,
  }) {
    return DetectedWheel(
      nodeIndex: nodeIndex ?? this.nodeIndex,
      nodeName: nodeName ?? this.nodeName,
      worldPosition: worldPosition ?? this.worldPosition,
      confidence: confidence ?? this.confidence,
      meshIndex: meshIndex ?? this.meshIndex,
      partNodeIndices: partNodeIndices ?? this.partNodeIndices,
      partIds: partIds ?? this.partIds,
      spinNodeIndices: spinNodeIndices ?? this.spinNodeIndices,
      caliperHubNodeIndices: caliperHubNodeIndices ?? this.caliperHubNodeIndices,
      axle: axle ?? this.axle,
      side: side ?? this.side,
      radius: radius ?? this.radius,
      width: width ?? this.width,
      circularity: circularity ?? this.circularity,
      subMeshCount: subMeshCount ?? this.subMeshCount,
    );
  }

  int get partCount => partIds.isNotEmpty
      ? partIds.length
      : (partNodeIndices.isEmpty ? 1 : partNodeIndices.length);

  String get label =>
      '${axle.isNotEmpty ? axle[0].toUpperCase() + axle.substring(1) : '?'} '
      '${side.isNotEmpty ? side[0].toUpperCase() + side.substring(1) : '?'}';
}

class AutoAxisResult {
  final double yawRotatedRadians;
  final bool axisSwapped;
  final bool frontFlipped;
  final String forwardDirection;

  const AutoAxisResult({
    this.yawRotatedRadians = 0.0,
    this.axisSwapped = false,
    this.frontFlipped = false,
    this.forwardDirection = '-Z',
  });
}

class DetectedBody {
  final int nodeIndex;
  final String nodeName;
  final BBox worldBBox;
  final double confidence;

  const DetectedBody({
    required this.nodeIndex,
    required this.nodeName,
    required this.worldBBox,
    required this.confidence,
  });
}

class DetectionResult {
  final List<DetectedWheel> wheels;
  final DetectedBody? body;
  final String suggestedDrive;
  final String suggestedPreset;
  final List<String> warnings;
  final bool isStaggered;
  final double averageCircularity;
  final int loosePartsCount;
  final bool groundContactVerified;
  final bool inboardSuspensionExcluded;
  final int underWheelObjectsDeleted;
  final AutoAxisResult? autoAxisResult;
  final double wheelGroundOffset;
  final List<int> suspensionNodes;

  const DetectionResult({
    required this.wheels,
    this.body,
    required this.suggestedDrive,
    required this.suggestedPreset,
    required this.warnings,
    this.isStaggered = false,
    this.averageCircularity = 0.98,
    this.loosePartsCount = 112,
    this.groundContactVerified = true,
    this.inboardSuspensionExcluded = true,
    this.underWheelObjectsDeleted = 0,
    this.autoAxisResult,
    this.wheelGroundOffset = 0.0,
    this.suspensionNodes = const [],
  });
}

// ── Rig Config (export) ─────────────────────────────────────────────────────

class RigConfig {
  const RigConfig({
    required this.modelName,
    required this.presetName,
    required this.drive,
    required this.mass,
    required this.engineForce,
    required this.grip,
    required this.suspension,
    required this.centerOfMass,
    required this.frontSteering,
    required this.rearSteering,
    required this.frontTraction,
    required this.rearTraction,
    this.springRestLength = 0.15,
    this.springStiffness = 35.0,
    this.dampingCompression = 0.83,
    this.steerAngle = 26.0,
    this.wheelRadius = 0.35,
    this.wheelPositions,
    this.bodyNodeName,
    this.chassisSize,
    this.godotArchitecture = 'standard',
    this.wheelNodeNames = const {},
  });

  final String modelName;
  final String presetName;
  final String drive;
  final double mass;
  final double engineForce;
  final double grip;
  final double suspension;
  final double centerOfMass;
  final bool frontSteering;
  final bool rearSteering;
  final bool frontTraction;
  final bool rearTraction;
  final double springRestLength;
  final double springStiffness;
  final double dampingCompression;
  final double steerAngle;
  final double wheelRadius;
  final Vec3? chassisSize;
  final String godotArchitecture;

  /// If set, contains [FL, FR, RL, RR] world positions from auto-detection.
  final List<Vec3>? wheelPositions;

  /// The confirmed body node from the imported model, when available.
  final String? bodyNodeName;

  /// Assigned visual wheel node names per corner (FL/FR/RL/RR), so the exported
  /// Godot script can spin and steer the model's own wheels.
  final Map<String, String> wheelNodeNames;

  Vec3 _wp(int i, Vec3 fallback) =>
      wheelPositions != null && i < wheelPositions!.length
      ? wheelPositions![i]
      : fallback;

  Map<String, Object> toJson() => {
    'format': 'rig-car.godot.vehicle-body-3d/v1',
    'model': modelName,
    'preset': presetName,
    'architecture': godotArchitecture,
    'godot': {
      'root_node': godotArchitecture == 'raycast' ? 'RigidBody3D' : 'VehicleBody3D',
      'wheel_node': godotArchitecture == 'raycast' ? 'RayCast3D' : 'VehicleWheel3D',
    },
    'vehicle_body': {
      'mass': mass,
      'engine_force': engineForce,
      'center_of_mass_y': centerOfMass,
      'drive': drive,
      'steer_angle_deg': steerAngle,
      'spring_rest_length': springRestLength,
      'spring_stiffness': springStiffness,
      'damping_compression': dampingCompression,
      'wheel_radius': wheelRadius,
    },
    if (bodyNodeName != null) 'body': {'node': bodyNodeName!},
    if (wheelNodeNames.isNotEmpty) 'wheel_nodes': wheelNodeNames,
    'wheels': {
      'front': {
        'use_as_steering': frontSteering,
        'use_as_traction': frontTraction,
        'wheel_radius': wheelRadius,
        'wheel_friction_slip': grip,
        'suspension_stiffness': springStiffness,
        'damping_compression': dampingCompression,
        'spring_rest_length': springRestLength,
      },
      'rear': {
        'use_as_steering': rearSteering,
        'use_as_traction': rearTraction,
        'wheel_radius': wheelRadius,
        'wheel_friction_slip': grip,
        'suspension_stiffness': springStiffness,
        'damping_compression': dampingCompression,
        'spring_rest_length': springRestLength,
      },
    },
  };

  String _gdEscape(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ');

  String toGdScript() {
    final maxSteerRad = (steerAngle * pi / 180.0).toStringAsFixed(3);
    String wheelName(String corner) =>
        _gdEscape(wheelNodeNames[corner] ?? '');
    if (godotArchitecture == 'raycast') {
      return '''extends RigidBody3D

@export var engine_power: float = ${engineForce.toStringAsFixed(1)}
@export var max_steering_angle: float = $maxSteerRad
@export var spring_stiffness: float = ${springStiffness.toStringAsFixed(1)}
@export var damping_compression: float = ${dampingCompression.toStringAsFixed(2)}
@export var rest_length: float = ${springRestLength.toStringAsFixed(2)}
@export var wheel_radius: float = ${wheelRadius.toStringAsFixed(3)}

@onready var idle_audio: AudioStreamPlayer3D = get_node_or_null("IdleAudio")
@onready var high_rpm_audio: AudioStreamPlayer3D = get_node_or_null("HighRpmAudio")
@onready var skid_audio: AudioStreamPlayer3D = get_node_or_null("SkidAudio")

func _physics_process(delta: float) -> void:
    var throttle := Input.get_axis("brake", "accelerate")
    var steer := Input.get_axis("steer_right", "steer_left") * max_steering_angle
    
    # Raycast suspension & drive integration (spring + damper)
    for child in get_children():
        if child is RayCast3D and child.is_colliding():
            var contact_point := child.get_collision_point()
            var current_dist := (global_position - contact_point).length()
            var point_offset := contact_point - global_position
            var point_vel := linear_velocity + angular_velocity.cross(point_offset)
            var ray_up := child.global_transform.basis.y
            var rel_vel := ray_up.dot(point_vel)
            var spring_force := (rest_length + wheel_radius - current_dist) * spring_stiffness - rel_vel * damping_compression
            apply_force(ray_up * maxf(0.0, spring_force), point_offset)
            if throttle != 0:
                apply_force(-global_transform.basis.z * throttle * (engine_power / 4.0), point_offset)
    
    # Audio RPM tracking
    if high_rpm_audio:
        high_rpm_audio.pitch_scale = clampf(0.8 + (linear_velocity.length() / 20.0), 0.7, 2.4)
''';
    }

    return '''extends VehicleBody3D

@export var max_engine_force: float = ${engineForce.toStringAsFixed(1)}
@export var max_brake_force: float = 30.0
@export var max_steering_angle: float = $maxSteerRad

@onready var idle_audio: AudioStreamPlayer3D = get_node_or_null("IdleAudio")
@onready var high_rpm_audio: AudioStreamPlayer3D = get_node_or_null("HighRpmAudio")
@onready var skid_audio: AudioStreamPlayer3D = get_node_or_null("SkidAudio")
@onready var visual_model: Node3D = get_node_or_null("VisualModel")
@onready var physics_wheels: Dictionary = {
    "FL": get_node_or_null("Wheel_FL"),
    "FR": get_node_or_null("Wheel_FR"),
    "RL": get_node_or_null("Wheel_RL"),
    "RR": get_node_or_null("Wheel_RR"),
}

# Visual wheel nodes authored inside the imported model.
const WHEEL_NODE_NAMES := {
    "FL": "${wheelName('FL')}",
    "FR": "${wheelName('FR')}",
    "RL": "${wheelName('RL')}",
    "RR": "${wheelName('RR')}",
}

var visual_wheels: Dictionary = {}
var _wheel_rest_offsets: Dictionary = {}

func _ready() -> void:
    # Bind the model's own wheel nodes to the physics wheels so the exported car
    # visibly steers and spins instead of rolling on frozen geometry.
    for corner in WHEEL_NODE_NAMES.keys():
        var target_name: String = WHEEL_NODE_NAMES[corner]
        if target_name.is_empty() or visual_model == null:
            continue
        var found := visual_model.find_child(target_name, true, false)
        var physics_wheel := physics_wheels.get(corner) as Node3D
        if found is Node3D and physics_wheel != null:
            visual_wheels[corner] = found
            # Preserve the authored mesh offset relative to its wheel origin.
            _wheel_rest_offsets[corner] = physics_wheel.global_transform.affine_inverse() * (found as Node3D).global_transform

func _sync_visual_wheels() -> void:
    for corner in visual_wheels.keys():
        var visual_wheel := visual_wheels[corner] as Node3D
        var physics_wheel := physics_wheels.get(corner) as Node3D
        if visual_wheel != null and physics_wheel != null:
            var rest: Transform3D = _wheel_rest_offsets[corner]
            visual_wheel.global_transform = physics_wheel.global_transform * rest

func _physics_process(_delta: float) -> void:
    _sync_visual_wheels()
    var throttle := Input.get_axis("brake", "accelerate")
    var steer := Input.get_axis("steer_right", "steer_left")
    engine_force = throttle * max_engine_force
    steering = steer * max_steering_angle
    brake = max_brake_force if Input.is_action_pressed("brake") else 0.0
    
    # Dynamic audio scaling
    if high_rpm_audio and engine_force != 0:
        high_rpm_audio.pitch_scale = clampf(0.8 + (linear_velocity.length() / 22.0), 0.7, 2.2)
''';
  }

  String toTscn() {
    final fl = _wp(0, const Vec3(-0.85, 0.35, -1.35));
    final fr = _wp(1, const Vec3(0.85, 0.35, -1.35));
    final rl = _wp(2, const Vec3(-0.85, 0.35, 1.35));
    final rr = _wp(3, const Vec3(0.85, 0.35, 1.35));
    final cs = chassisSize ?? const Vec3(1.8, 0.6, 4.2);

    String v3(Vec3 v) =>
        'Vector3(${v.x.toStringAsFixed(3)}, ${v.y.toStringAsFixed(3)}, '
        '${v.z.toStringAsFixed(3)})';

    final hasCustomModel = modelName.isNotEmpty &&
        modelName != 'No model loaded' &&
        !modelName.contains('Template');
    final extResourceIndex = hasCustomModel ? 3 : 2;

    if (godotArchitecture == 'raycast') {
      return '''[gd_scene load_steps=$extResourceIndex format=3]

[ext_resource type="Script" path="res://rig_car.gd" id="1_rig"]
${hasCustomModel ? '[ext_resource type="PackedScene" path="res://$modelName" id="2_model"]\n' : ''}
[sub_resource type="BoxShape3D" id="BoxShape3D_body"]
size = Vector3(${cs.x.toStringAsFixed(3)}, ${cs.y.toStringAsFixed(3)}, ${cs.z.toStringAsFixed(3)})

[node name="RigCar" type="RigidBody3D"]
mass = ${mass.toStringAsFixed(1)}
center_of_mass_mode = 1
center_of_mass = Vector3(0, ${centerOfMass.toStringAsFixed(3)}, 0)
script = ExtResource("1_rig")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
position = Vector3(0, ${(cs.y * 0.5).toStringAsFixed(3)}, 0)
shape = SubResource("BoxShape3D_body")

${hasCustomModel ? '[node name="VisualModel" parent="." instance=ExtResource("2_model")]\n' : ''}
[node name="WheelRay_FL" type="RayCast3D" parent="."]
position = ${v3(fl)}
target_position = Vector3(0, -${(wheelRadius + springRestLength).toStringAsFixed(3)}, 0)

[node name="WheelRay_FR" type="RayCast3D" parent="."]
position = ${v3(fr)}
target_position = Vector3(0, -${(wheelRadius + springRestLength).toStringAsFixed(3)}, 0)

[node name="WheelRay_RL" type="RayCast3D" parent="."]
position = ${v3(rl)}
target_position = Vector3(0, -${(wheelRadius + springRestLength).toStringAsFixed(3)}, 0)

[node name="WheelRay_RR" type="RayCast3D" parent="."]
position = ${v3(rr)}
target_position = Vector3(0, -${(wheelRadius + springRestLength).toStringAsFixed(3)}, 0)

[node name="IdleAudio" type="AudioStreamPlayer3D" parent="."]
[node name="HighRpmAudio" type="AudioStreamPlayer3D" parent="."]
[node name="SkidAudio" type="AudioStreamPlayer3D" parent="."]
''';
    }

    return '''[gd_scene load_steps=$extResourceIndex format=3]

[ext_resource type="Script" path="res://rig_car.gd" id="1_rig"]
${hasCustomModel ? '[ext_resource type="PackedScene" path="res://$modelName" id="2_model"]\n' : ''}
[sub_resource type="BoxShape3D" id="BoxShape3D_body"]
size = Vector3(${cs.x.toStringAsFixed(3)}, ${cs.y.toStringAsFixed(3)}, ${cs.z.toStringAsFixed(3)})

[node name="RigCar" type="VehicleBody3D"]
mass = ${mass.toStringAsFixed(1)}
center_of_mass_mode = 1
center_of_mass = Vector3(0, ${centerOfMass.toStringAsFixed(3)}, 0)
script = ExtResource("1_rig")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
position = Vector3(0, ${(cs.y * 0.5).toStringAsFixed(3)}, 0)
shape = SubResource("BoxShape3D_body")

${hasCustomModel ? '[node name="VisualModel" parent="." instance=ExtResource("2_model")]\n' : ''}
[node name="Wheel_FL" type="VehicleWheel3D" parent="."]
position = ${v3(fl)}
wheel_radius = ${wheelRadius.toStringAsFixed(3)}
wheel_rest_length = ${springRestLength.toStringAsFixed(3)}
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${springStiffness.toStringAsFixed(2)}
damping_compression = ${dampingCompression.toStringAsFixed(2)}
suspension_travel = 0.20
use_as_steering = $frontSteering
use_as_traction = $frontTraction

[node name="Wheel_FR" type="VehicleWheel3D" parent="."]
position = ${v3(fr)}
wheel_radius = ${wheelRadius.toStringAsFixed(3)}
wheel_rest_length = ${springRestLength.toStringAsFixed(3)}
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${springStiffness.toStringAsFixed(2)}
damping_compression = ${dampingCompression.toStringAsFixed(2)}
suspension_travel = 0.20
use_as_steering = $frontSteering
use_as_traction = $frontTraction

[node name="Wheel_RL" type="VehicleWheel3D" parent="."]
position = ${v3(rl)}
wheel_radius = ${wheelRadius.toStringAsFixed(3)}
wheel_rest_length = ${springRestLength.toStringAsFixed(3)}
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${springStiffness.toStringAsFixed(2)}
damping_compression = ${dampingCompression.toStringAsFixed(2)}
suspension_travel = 0.20
use_as_steering = $rearSteering
use_as_traction = $rearTraction

[node name="Wheel_RR" type="VehicleWheel3D" parent="."]
position = ${v3(rr)}
wheel_radius = ${wheelRadius.toStringAsFixed(3)}
wheel_rest_length = ${springRestLength.toStringAsFixed(3)}
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${springStiffness.toStringAsFixed(2)}
damping_compression = ${dampingCompression.toStringAsFixed(2)}
suspension_travel = 0.20
use_as_steering = $rearSteering
use_as_traction = $rearTraction

[node name="IdleAudio" type="AudioStreamPlayer3D" parent="."]
[node name="HighRpmAudio" type="AudioStreamPlayer3D" parent="."]
[node name="SkidAudio" type="AudioStreamPlayer3D" parent="."]
''';
  }
}
