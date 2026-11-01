import 'dart:math';
import 'dart:typed_data';

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
  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => sqrt(x * x + y * y + z * z);
  double get lengthSquared => x * x + y * y + z * z;

  Vec3 get normalized {
    final len = length;
    if (len < 1e-10) return Vec3.zero;
    return this * (1.0 / len);
  }

  Vec3 min(Vec3 o) => Vec3(
        x < o.x ? x : o.x,
        y < o.y ? y : o.y,
        z < o.z ? z : o.z,
      );
  Vec3 max(Vec3 o) => Vec3(
        x > o.x ? x : o.x,
        y > o.y ? y : o.y,
        z > o.z ? z : o.z,
      );

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(3)}, '
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
      1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0,
      2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0,
      2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0,
      0, 0, 0, 1,
    ]);
  }
}

/// 4×4 matrix stored **column-major**: `m[col * 4 + row]`.
class Mat4 {
  final List<double> m;
  Mat4(this.m) : assert(m.length == 16);

  static Mat4 identity() =>
      Mat4([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

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

  static Mat4 fromTRS(Vec3 t, Quat r, Vec3 s) {
    final rot = r.toRotationMatrix();
    return Mat4([
      rot.m[0] * s.x, rot.m[1] * s.x, rot.m[2] * s.x, 0,
      rot.m[4] * s.y, rot.m[5] * s.y, rot.m[6] * s.y, 0,
      rot.m[8] * s.z, rot.m[9] * s.z, rot.m[10] * s.z, 0,
      t.x, t.y, t.z, 1,
    ]);
  }

  static Mat4 lookAt(Vec3 eye, Vec3 target, Vec3 upHint) {
    final f = (target - eye).normalized;
    final r = f.cross(upHint).normalized;
    final u = r.cross(f);
    return Mat4([
      r.x, u.x, -f.x, 0,
      r.y, u.y, -f.y, 0,
      r.z, u.z, -f.z, 0,
      -r.dot(eye), -u.dot(eye), f.dot(eye), 1,
    ]);
  }

  static Mat4 perspective(double fovY, double aspect, double near, double far) {
    final f = 1.0 / tan(fovY / 2);
    final nf = 1.0 / (near - far);
    return Mat4([
      f / aspect, 0, 0, 0,
      0, f, 0, 0,
      0, 0, (far + near) * nf, -1,
      0, 0, 2 * far * near * nf, 0,
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
    Vec3(double.negativeInfinity, double.negativeInfinity,
        double.negativeInfinity),
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
  Edge(int v0, int v1)
      : a = v0 < v1 ? v0 : v1,
        b = v0 < v1 ? v1 : v0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Edge && a == other.a && b == other.b;
  @override
  int get hashCode => Object.hash(a, b);
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
  final int? meshIndex;
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
  final BBox bbox;

  const MeshData({
    required this.index,
    required this.name,
    required this.vertices,
    required this.edges,
    required this.bbox,
  });
}

/// A mesh instantiated in world space by a particular scene node.
class MeshInstance {
  final int nodeIndex;
  final int meshIndex;
  final List<Vec3> worldVertices;
  final List<Edge> edges;
  final BBox worldBBox;

  const MeshInstance({
    required this.nodeIndex,
    required this.meshIndex,
    required this.worldVertices,
    required this.edges,
    required this.worldBBox,
  });
}

class ParsedModel {
  final String fileName;
  final List<SceneNode> nodes;
  final List<MeshData> meshes;
  final List<MeshInstance> instances;
  final List<int> rootNodeIndices;
  final BBox worldBBox;

  const ParsedModel({
    required this.fileName,
    required this.nodes,
    required this.meshes,
    required this.instances,
    required this.rootNodeIndices,
    required this.worldBBox,
  });
}

// ── Auto-detection Results ──────────────────────────────────────────────────

class DetectedWheel {
  final int nodeIndex;
  final String nodeName;
  final Vec3 worldPosition;
  final double confidence;
  final int? meshIndex;
  String axle; // 'front' | 'rear'
  String side; // 'left' | 'right'

  DetectedWheel({
    required this.nodeIndex,
    required this.nodeName,
    required this.worldPosition,
    required this.confidence,
    this.meshIndex,
    this.axle = '',
    this.side = '',
  });

  String get label =>
      '${axle.isNotEmpty ? axle[0].toUpperCase() + axle.substring(1) : '?'} '
      '${side.isNotEmpty ? side[0].toUpperCase() + side.substring(1) : '?'}';
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

  const DetectionResult({
    required this.wheels,
    this.body,
    required this.suggestedDrive,
    required this.suggestedPreset,
    required this.warnings,
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
    this.wheelPositions,
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

  /// If set, contains [FL, FR, RL, RR] world positions from auto-detection.
  final List<Vec3>? wheelPositions;

  Vec3 _wp(int i, Vec3 fallback) =>
      wheelPositions != null && i < wheelPositions!.length
          ? wheelPositions![i]
          : fallback;

  Map<String, Object> toJson() => {
        'format': 'rig-car.godot.vehicle-body-3d/v1',
        'model': modelName,
        'preset': presetName,
        'godot': {'root_node': 'VehicleBody3D', 'wheel_node': 'VehicleWheel3D'},
        'vehicle_body': {
          'mass': mass,
          'engine_force': engineForce,
          'center_of_mass_y': centerOfMass,
          'drive': drive,
        },
        'wheels': {
          'front': {
            'use_as_steering': frontSteering,
            'use_as_traction': frontTraction,
          },
          'rear': {
            'use_as_steering': rearSteering,
            'use_as_traction': rearTraction,
            'wheel_friction_slip': grip,
            'suspension_stiffness': suspension,
          },
        },
      };

  String toGdScript() =>
      '''extends VehicleBody3D

@export var max_engine_force: float = ${engineForce.toStringAsFixed(1)}
@export var max_brake_force: float = 30.0
@export var max_steering_angle: float = 0.45

func _physics_process(_delta: float) -> void:
    var throttle := Input.get_axis("brake", "accelerate")
    var steer := Input.get_axis("steer_right", "steer_left")
    engine_force = throttle * max_engine_force
    steering = steer * max_steering_angle
    brake = max_brake_force if Input.is_action_pressed("brake") else 0.0
''';

  String toTscn() {
    final fl = _wp(0, const Vec3(-0.85, 0, -1.35));
    final fr = _wp(1, const Vec3(0.85, 0, -1.35));
    final rl = _wp(2, const Vec3(-0.85, 0, 1.35));
    final rr = _wp(3, const Vec3(0.85, 0, 1.35));
    String v3(Vec3 v) =>
        'Vector3(${v.x.toStringAsFixed(3)}, ${v.y.toStringAsFixed(3)}, '
        '${v.z.toStringAsFixed(3)})';
    return '''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://rig_car.gd" id="1_rig"]

[sub_resource type="BoxShape3D" id="BoxShape3D_body"]
size = Vector3(1.8, 0.6, 4.2)

[node name="RigCar" type="VehicleBody3D"]
mass = ${mass.toStringAsFixed(1)}
script = ExtResource("1_rig")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
position = Vector3(0, 0.35, 0)
shape = SubResource("BoxShape3D_body")

[node name="Wheel_FL" type="VehicleWheel3D" parent="."]
position = ${v3(fl)}
use_as_steering = $frontSteering
use_as_traction = $frontTraction
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${suspension.toStringAsFixed(2)}

[node name="Wheel_FR" type="VehicleWheel3D" parent="."]
position = ${v3(fr)}
use_as_steering = $frontSteering
use_as_traction = $frontTraction
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${suspension.toStringAsFixed(2)}

[node name="Wheel_RL" type="VehicleWheel3D" parent="."]
position = ${v3(rl)}
use_as_steering = $rearSteering
use_as_traction = $rearTraction
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${suspension.toStringAsFixed(2)}

[node name="Wheel_RR" type="VehicleWheel3D" parent="."]
position = ${v3(rr)}
use_as_steering = $rearSteering
use_as_traction = $rearTraction
wheel_friction_slip = ${grip.toStringAsFixed(2)}
suspension_stiffness = ${suspension.toStringAsFixed(2)}
''';
  }
}
