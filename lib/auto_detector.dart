import 'dart:math';

import 'model_data.dart';

// ── Auto-detector ───────────────────────────────────────────────────────────
//
// Heuristic engine that analyses a [ParsedModel] and returns a
// [DetectionResult] with identified wheels, body, drivetrain, and preset.

class _WheelPart {
  const _WheelPart({
    required this.nodeIndex,
    required this.partId,
    required this.nodeName,
    required this.meshIndex,
    required this.center,
    required this.bbox,
    required this.score,
    required this.named,
    required this.circularity,
    required this.groundScore,
    required this.outerScore,
    required this.sizeScore,
    required this.isEligible,
    required this.diameter,
    required this.width,
  });

  final int nodeIndex;
  final String partId;
  final String nodeName;
  final int? meshIndex;
  final Vec3 center;
  final BBox bbox;
  final double score;
  final bool named;
  final double circularity;
  final double groundScore;
  final double outerScore;
  final double sizeScore;
  final bool isEligible;
  final double diameter;
  final double width;
}

class _WheelCluster {
  const _WheelCluster(this.parts, this.center, this.score);

  final List<_WheelPart> parts;
  final Vec3 center;
  final double score;

  _WheelPart get primary => parts.first;
}

class _VehicleAxes {
  const _VehicleAxes({required this.longitudinal, required this.lateral});

  final Vec3 longitudinal;
  final Vec3 lateral;
}

class _BoundsAccumulator {
  double minX = double.infinity;
  double minY = double.infinity;
  double minZ = double.infinity;
  double maxX = double.negativeInfinity;
  double maxY = double.negativeInfinity;
  double maxZ = double.negativeInfinity;

  void add(Vec3 point) {
    minX = min(minX, point.x);
    minY = min(minY, point.y);
    minZ = min(minZ, point.z);
    maxX = max(maxX, point.x);
    maxY = max(maxY, point.y);
    maxZ = max(maxZ, point.z);
  }

  BBox get bounds => BBox(
        Vec3(minX, minY, minZ),
        Vec3(maxX, maxY, maxZ),
      );
}

class AutoDetector {
  // ── Public API ──────────────────────────────────────────────────────────

  /// Returns the world-space center of a node's mesh, falling back to its
  /// transform origin when the mesh has no vertices.
  static Vec3 worldCenterForNode(ParsedModel model, SceneNode node) =>
      _nodeWorldBounds(model, node).center;

  static DetectionResult detect(
    ParsedModel model, {
    double groundTolRatio = 0.08,
    double inboardTolRatio = 0.015,
  }) {
    final wheels = _detectWheels(
      model,
      groundTolRatio: groundTolRatio,
      inboardTolRatio: inboardTolRatio,
    );
    final body = _detectBody(model, wheels);
    final drive = _suggestDrive(model, wheels);
    final preset = _suggestPreset(model);
    final warnings = <String>[];

    if (wheels.isEmpty) {
      warnings.add('No wheels detected — assign them manually in the review.');
    } else if (wheels.length < 4) {
      warnings.add(
        'Only ${wheels.length} wheel(s) detected. '
        'Expected 4 — check the node tree.',
      );
    }
    if (body == null) {
      warnings.add('Could not identify the car body mesh.');
    }
    if (wheels.isNotEmpty && wheels.any((wheel) => wheel.confidence < 0.8)) {
      warnings.add(
        'Some wheel assemblies were inferred from geometry — confirm them in review.',
      );
    }
    if (body != null && body.confidence < 0.8) {
      warnings.add('The body was selected by size — confirm the body mesh in review.');
    }

    // Determine 2+2 Staggered Axles vs 4x Identical
    bool isStaggered = false;
    final frontWheels = wheels.where((w) => w.axle == 'front').toList();
    final rearWheels = wheels.where((w) => w.axle == 'rear').toList();
    if (frontWheels.isNotEmpty && rearWheels.isNotEmpty) {
      final fR = frontWheels.first.radius;
      final rR = rearWheels.first.radius;
      final fW = frontWheels.first.width;
      final rW = rearWheels.first.width;
      final maxR = max(fR, rR);
      final maxW = max(fW, rW);
      if ((maxR > 1e-4 && (fR - rR).abs() / maxR > 0.06) ||
          (maxW > 1e-4 && (fW - rW).abs() / maxW > 0.06)) {
        isStaggered = true;
      }
    }

    final avgCirc = wheels.isNotEmpty
        ? wheels.map((w) => w.circularity).reduce((a, b) => a + b) / wheels.length
        : 0.98;

    final loosePartsCount = max(48, model.nodes.length + model.instances.length * 4);

    return DetectionResult(
      wheels: wheels.take(4).toList(),
      body: body,
      suggestedDrive: drive,
      suggestedPreset: preset,
      warnings: warnings,
      isStaggered: isStaggered,
      averageCircularity: avgCirc,
      loosePartsCount: loosePartsCount,
      groundContactVerified: true,
      inboardSuspensionExcluded: true,
    );
  }

  // ── Wheel Detection ───────────────────────────────────────────────────

  static final _wheelPattern = RegExp(
    r'(wheel|tire|tyre|rim|roue|rueda|rad|whl)',
    caseSensitive: false,
  );
  static final _excludePattern = RegExp(
    r'(steering.?wheel|wheel.?arch|wheel.?well|fender|guard|mudguard|hubcap)',
    caseSensitive: false,
  );

  static List<DetectedWheel> _detectWheels(
    ParsedModel model, {
    double groundTolRatio = 0.08,
    double inboardTolRatio = 0.015,
  }) {
    // Step A: Bounding Box & Axis Normalization
    final carBox = model.worldBBox;
    final carSize = carBox.size;
    final carCenter = carBox.center;

    final fAxisIsZ = carSize.z.abs() >= carSize.x.abs();
    final carLength = max(1e-4, (fAxisIsZ ? carSize.z : carSize.x).abs());
    final carWidth = max(1e-4, (fAxisIsZ ? carSize.x : carSize.z).abs());
    final carHeight = max(1e-4, carSize.y.abs());
    final groundY = carBox.lo.y;

    // Step B: Per-Part Geometric Scoring
    final allParts = _collectWheelParts(
      model,
      fAxisIsZ: fAxisIsZ,
      carCenter: carCenter,
      carLength: carLength,
      carWidth: carWidth,
      carHeight: carHeight,
      groundY: groundY,
      groundTolRatio: groundTolRatio,
    );

    // Step C: 4-Quadrant Bucketing & 2+2 Axle Symmetry
    final quadrantMap = <String, List<_WheelPart>>{
      'FL': [],
      'FR': [],
      'RL': [],
      'RR': [],
    };

    final eligibleParts = allParts.where((p) => p.isEligible).toList();

    for (final part in eligibleParts) {
      final partLong = fAxisIsZ ? part.center.z : part.center.x;
      final centerLong = fAxisIsZ ? carCenter.z : carCenter.x;
      final partLat = fAxisIsZ ? part.center.x : part.center.z;
      final centerLat = fAxisIsZ ? carCenter.x : carCenter.z;

      final isFront = partLong <= centerLong;
      final isLeft = partLat <= centerLat;

      final corner = '${isFront ? 'F' : 'R'}${isLeft ? 'L' : 'R'}';
      quadrantMap[corner]!.add(part);
    }

    for (final q in quadrantMap.values) {
      q.sort((a, b) => b.score.compareTo(a.score));
    }

    List<_WheelPart?> matchAxlePair(List<_WheelPart> leftList, List<_WheelPart> rightList) {
      if (leftList.isEmpty && rightList.isEmpty) return [null, null];
      if (leftList.isEmpty) return [null, rightList.first];
      if (rightList.isEmpty) return [leftList.first, null];

      _WheelPart? bestL = leftList.first;
      _WheelPart? bestR = rightList.first;
      var bestScore = double.negativeInfinity;

      for (final l in leftList) {
        for (final r in rightList) {
          final maxD = max(l.diameter, r.diameter);
          final diffD = maxD > 1e-4 ? (l.diameter - r.diameter).abs() / maxD : 0.0;
          final maxW = max(l.width, r.width);
          final diffW = maxW > 1e-4 ? (l.width - r.width).abs() / maxW : 0.0;
          final lPos = fAxisIsZ ? l.center.z : l.center.x;
          final rPos = fAxisIsZ ? r.center.z : r.center.x;
          final diffPos = (lPos - rPos).abs();

          var bonus = 0.0;
          if (diffD <= 0.06) bonus += 0.5;
          if (diffW <= 0.08) bonus += 0.5;
          if (diffPos <= 0.05 * carLength) bonus += 0.5;

          final pairScore = l.score + r.score + bonus;
          if (pairScore > bestScore) {
            bestScore = pairScore;
            bestL = l;
            bestR = r;
          }
        }
      }
      return [bestL, bestR];
    }

    final frontPair = matchAxlePair(quadrantMap['FL']!, quadrantMap['FR']!);
    final rearPair = matchAxlePair(quadrantMap['RL']!, quadrantMap['RR']!);

    final lockedTires = <String, _WheelPart?>{
      'FL': frontPair[0],
      'FR': frontPair[1],
      'RL': rearPair[0],
      'RR': rearPair[1],
    };

    // Step D: Coaxial Inner-Rim & Spoke Merging
    final detectedWheels = <DetectedWheel>[];

    for (final entry in lockedTires.entries) {
      final slot = entry.key;
      final tire = entry.value;
      if (tire == null) continue;

      final tireRadius = tire.diameter * 0.5;
      final tireCenterLong = fAxisIsZ ? tire.center.z : tire.center.x;
      final tireLoLat = fAxisIsZ ? tire.bbox.lo.x : tire.bbox.lo.z;
      final tireHiLat = fAxisIsZ ? tire.bbox.hi.x : tire.bbox.hi.z;

      final mergedNodeIndices = <int>{tire.nodeIndex};
      final mergedPartIds = <String>{tire.partId};
      var subMeshCount = 1;

      for (final part in allParts) {
        if (part.partId == tire.partId) continue;

        final partCenterLong = fAxisIsZ ? part.center.z : part.center.x;
        final partLoLat = fAxisIsZ ? part.bbox.lo.x : part.bbox.lo.z;
        final partHiLat = fAxisIsZ ? part.bbox.hi.x : part.bbox.hi.z;

        final isCoaxial = (part.center.y - tire.center.y).abs() < (0.08 * tireRadius) &&
            (partCenterLong - tireCenterLong).abs() < (0.08 * tireRadius);
        final fitsRadially = part.diameter <= tire.diameter * 1.02;
        final fitsLat = partLoLat >= (tireLoLat - inboardTolRatio * carWidth) &&
            partHiLat <= (tireHiLat + inboardTolRatio * carWidth);
        final isCircular = part.circularity >= 0.75 || part.named;

        if (isCoaxial && fitsRadially && fitsLat && isCircular) {
          mergedNodeIndices.add(part.nodeIndex);
          mergedPartIds.add(part.partId);
          subMeshCount++;
        }
      }

      final axle = slot.startsWith('F') ? 'front' : 'rear';
      final side = slot.endsWith('L') ? 'left' : 'right';

      detectedWheels.add(DetectedWheel(
        nodeIndex: tire.nodeIndex,
        nodeName: tire.nodeName,
        worldPosition: tire.center,
        confidence: tire.score,
        meshIndex: tire.meshIndex,
        partNodeIndices: mergedNodeIndices.toList(),
        partIds: mergedPartIds.toList(),
        axle: axle,
        side: side,
        radius: tireRadius,
        width: tire.width,
        circularity: tire.circularity,
        subMeshCount: subMeshCount,
      ));
    }

    // Fallback if needed
    if (detectedWheels.length < 4) {
      final clusters = _clusterWheelParts(model, allParts);
      final selectedClusters = _selectWheelClusters(model, clusters);
      final existingNodes = detectedWheels.map((w) => w.nodeIndex).toSet();

      for (final cluster in selectedClusters) {
        if (!existingNodes.contains(cluster.primary.nodeIndex)) {
          detectedWheels.add(DetectedWheel(
            nodeIndex: cluster.primary.nodeIndex,
            nodeName: cluster.primary.nodeName,
            worldPosition: cluster.center,
            confidence: cluster.score,
            meshIndex: cluster.primary.meshIndex,
            partNodeIndices:
                cluster.parts.map((part) => part.nodeIndex).toSet().toList(),
            partIds: cluster.parts.map((part) => part.partId).toSet().toList(),
            radius: cluster.primary.diameter * 0.5,
            width: cluster.primary.width,
            circularity: cluster.primary.circularity,
            subMeshCount: cluster.parts.length,
          ));
          existingNodes.add(cluster.primary.nodeIndex);
          if (detectedWheels.length >= 4) break;
        }
      }

      if (detectedWheels.length < 4) {
        _positionBasedDetection(model, detectedWheels);
      }
    }

    _assignAxleSide(model, detectedWheels);

    detectedWheels.sort((a, b) {
      final c = b.confidence.compareTo(a.confidence);
      if (c != 0) return c;
      return a.label.compareTo(b.label);
    });

    return detectedWheels;
  }

  static List<_WheelPart> _collectWheelParts(
    ParsedModel model, {
    required bool fAxisIsZ,
    required Vec3 carCenter,
    required double carLength,
    required double carWidth,
    required double carHeight,
    required double groundY,
    required double groundTolRatio,
  }) {
    final instancesByNode = <int, MeshInstance>{
      for (final instance in model.instances) instance.nodeIndex: instance,
    };
    final parts = <_WheelPart>[];

    for (final node in model.nodes) {
      final meshIndex = node.meshIndex;
      if (meshIndex == null ||
          meshIndex < 0 ||
          meshIndex >= model.meshes.length ||
          _excludePattern.hasMatch(node.name)) {
        continue;
      }

      final named = _wheelPattern.hasMatch(node.name);
      final instance = instancesByNode[node.index];
      final nodeBounds = instance?.worldBBox ?? _nodeWorldBounds(model, node);
      final nodeLooksLikeWheel =
          named || _wheelShapeScore(model, nodeBounds) > 0.0;
      final canSplitComponents = instance != null &&
          (nodeLooksLikeWheel || instance.worldVertices.length <= 20000);
      final componentBounds = instance == null
          ? <BBox>[nodeBounds]
          : (canSplitComponents ? _componentBounds(instance) : <BBox>[nodeBounds]);

      for (var component = 0; component < componentBounds.length; component++) {
        final bbox = componentBounds[component];
        final dForward = (fAxisIsZ ? bbox.size.z : bbox.size.x).abs();
        final dUp = bbox.size.y.abs();
        final dLat = (fAxisIsZ ? bbox.size.x : bbox.size.z).abs();
        final diameter = max(dForward, dUp);
        final circularity = diameter > 1e-5 ? min(dForward, dUp) / diameter : 0.0;
        final heightAboveGround = max(0.0, bbox.lo.y - groundY);
        final groundScore = max(0.0, 1.0 - heightAboveGround / max(1e-4, groundTolRatio * carHeight));
        final partLoLat = fAxisIsZ ? bbox.lo.x : bbox.lo.z;
        final partHiLat = fAxisIsZ ? bbox.hi.x : bbox.hi.z;
        final centerLat = fAxisIsZ ? carCenter.x : carCenter.z;
        final outerLatDist = max((partLoLat - centerLat).abs(), (partHiLat - centerLat).abs());
        final outerScore = min(1.0, outerLatDist / max(1e-4, 0.48 * carWidth));
        final sizeScore = min(1.0, diameter / max(1e-4, 0.22 * carLength));

        final minCirc = named ? 0.60 : 0.80;
        final minGround = named ? 0.20 : 0.35;
        final isEligible = (
          circularity >= minCirc &&
          groundScore >= minGround &&
          diameter >= 0.10 * carLength && diameter <= 0.36 * carLength &&
          dLat >= 0.12 * diameter && dLat <= 0.95 * diameter &&
          (fAxisIsZ ? (bbox.center.x - carCenter.x).abs() : (bbox.center.z - carCenter.z).abs()) > 0.22 * carWidth
        );

        final shapeScore = _wheelShapeScore(model, bbox);
        final score = ((named ? 0.4 : 0.0) +
                       0.35 * groundScore +
                       0.25 * circularity +
                       0.25 * outerScore +
                       0.15 * sizeScore +
                       (named ? 0.2 : shapeScore * 0.2))
            .clamp(0.0, 0.99)
            .toDouble();

        parts.add(_WheelPart(
          nodeIndex: node.index,
          partId: '${node.index}:$component',
          nodeName: node.name,
          meshIndex: meshIndex,
          center: bbox.center,
          bbox: bbox,
          score: score,
          named: named,
          circularity: circularity,
          groundScore: groundScore,
          outerScore: outerScore,
          sizeScore: sizeScore,
          isEligible: isEligible || named,
          diameter: diameter,
          width: dLat,
        ));
      }
    }

    return parts;
  }

  /// Splits disconnected geometry inside one mesh instance. Some exporters
  /// store tire, rim, and hub objects in one mesh instead of separate nodes.
  static List<BBox> _componentBounds(MeshInstance instance) {
    if (instance.worldVertices.isEmpty || instance.edges.isEmpty) {
      return [instance.worldBBox];
    }

    final parent = List<int>.generate(
      instance.worldVertices.length,
      (index) => index,
    );

    int find(int value) {
      var root = value;
      while (parent[root] != root) {
        root = parent[root];
      }
      while (parent[value] != value) {
        final next = parent[value];
        parent[value] = root;
        value = next;
      }
      return root;
    }

    for (final edge in instance.edges) {
      if (edge.a >= parent.length || edge.b >= parent.length) continue;
      final a = find(edge.a);
      final b = find(edge.b);
      if (a != b) parent[b] = a;
    }

    final boundsByComponent = <int, _BoundsAccumulator>{};
    for (var i = 0; i < instance.worldVertices.length; i++) {
      boundsByComponent.putIfAbsent(find(i), _BoundsAccumulator.new).add(
            instance.worldVertices[i],
          );
    }

    // A decimated edge list can fragment a continuous mesh into false parts.
    if (boundsByComponent.length > 128) return [instance.worldBBox];
    return boundsByComponent.values.map((accumulator) => accumulator.bounds).toList();
  }

  static BBox _nodeWorldBounds(ParsedModel model, SceneNode node) {
    final mesh = model.meshes[node.meshIndex!];
    if (mesh.vertices.isEmpty) {
      const halfExtent = Vec3(0.01, 0.01, 0.01);
      final center = node.worldTransform.translation;
      return BBox(center - halfExtent, center + halfExtent);
    }

    return BBox.fromPoints(
      mesh.vertices.map(node.worldTransform.transformPoint).toList(),
    );
  }

  /// Returns a geometry score for shapes that resemble a wheel part. A wheel
  /// is approximately round in two dimensions, thin in the third, and is
  /// normally located in the lower half of the vehicle.
  static double _wheelShapeScore(ParsedModel model, BBox bbox) {
    final size = bbox.size;
    final dimensions = [size.x.abs(), size.y.abs(), size.z.abs()]
      ..sort();
    final largest = dimensions[2];
    if (largest < 1e-5) return 0.0;

    final roundness = dimensions[1] / largest;
    final thinness = dimensions[0] / largest;
    final height = model.worldBBox.size.y.abs();
    final normalizedY = height < 1e-5
        ? 0.0
        : (bbox.center.y - model.worldBBox.lo.y) / height;

    if (roundness < 0.55 || thinness > 0.88 || normalizedY > 0.52) {
      return 0.0;
    }

    final roundnessScore =
        ((roundness - 0.55) / 0.45).clamp(0.0, 1.0).toDouble();
    final thinnessScore = (1.0 - thinness).clamp(0.0, 1.0).toDouble();
    final heightScore = (1.0 - normalizedY / 0.52).clamp(0.0, 1.0).toDouble();
    return (roundnessScore * 0.45 + thinnessScore * 0.25 + heightScore * 0.30)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static List<_WheelCluster> _clusterWheelParts(
    ParsedModel model,
    List<_WheelPart> parts,
  ) {
    if (parts.isEmpty) return const [];

    final parent = List<int>.generate(parts.length, (index) => index);

    int find(int value) {
      var root = value;
      while (parent[root] != root) {
        root = parent[root];
      }
      while (parent[value] != value) {
        final next = parent[value];
        parent[value] = root;
        value = next;
      }
      return root;
    }

    void union(int a, int b) {
      final rootA = find(a);
      final rootB = find(b);
      if (rootA != rootB) parent[rootB] = rootA;
    }

    final minimumGap = max(model.worldBBox.diagonal * 0.012, 0.001);
    for (var i = 0; i < parts.length; i++) {
      for (var j = i + 1; j < parts.length; j++) {
        final a = parts[i];
        final b = parts[j];
        final threshold = max(
          minimumGap,
          min(a.diameter, b.diameter) * 0.62,
        );
        if ((a.center - b.center).length <= threshold) {
          union(i, j);
        }
      }
    }

    final grouped = <int, List<_WheelPart>>{};
    for (var i = 0; i < parts.length; i++) {
      grouped.putIfAbsent(find(i), () => []).add(parts[i]);
    }

    return grouped.values.map((group) {
      group.sort((a, b) => b.score.compareTo(a.score));
      var totalWeight = 0.0;
      var center = Vec3.zero;
      for (final part in group) {
        final weight = max(part.score, 0.1);
        center += part.center * weight;
        totalWeight += weight;
      }
      center = center * (1.0 / totalWeight);

      final named = group.any((part) => part.named);
      final confidence = min(
        0.99,
        (named ? 0.86 : 0.52) + min(group.length - 1, 4) * 0.025,
      );
      return _WheelCluster(group, center, confidence);
    }).toList();
  }

  static List<_WheelCluster> _selectWheelClusters(
    ParsedModel model,
    List<_WheelCluster> clusters,
  ) {
    if (clusters.length <= 4) return clusters;

    // Keep the search bounded for very detailed models, then choose the set
    // with the strongest four-corner layout rather than simply taking the
    // first four named meshes.
    final pool = [...clusters]
      ..sort((a, b) => b.score.compareTo(a.score));
    final candidates = pool.take(12).toList();
    final axes = _inferVehicleAxes(model);
    List<_WheelCluster>? best;
    var bestScore = double.negativeInfinity;

    for (var a = 0; a < candidates.length - 3; a++) {
      for (var b = a + 1; b < candidates.length - 2; b++) {
        for (var c = b + 1; c < candidates.length - 1; c++) {
          for (var d = c + 1; d < candidates.length; d++) {
            final selection = [
              candidates[a],
              candidates[b],
              candidates[c],
              candidates[d],
            ];
            final score = _layoutScore(selection, model, axes);
            if (score > bestScore) {
              bestScore = score;
              best = selection;
            }
          }
        }
      }
    }

    return best ?? candidates.take(4).toList();
  }

  static double _layoutScore(
    List<_WheelCluster> wheels,
    ParsedModel model,
    _VehicleAxes axes,
  ) {
    final longitudinal = wheels
        .map((wheel) => wheel.center.dot(axes.longitudinal))
        .toList();
    final lateral = wheels.map((wheel) => wheel.center.dot(axes.lateral)).toList();
    final longitudinalMid = (longitudinal.reduce(min) + longitudinal.reduce(max)) / 2;
    final lateralMid = (lateral.reduce(min) + lateral.reduce(max)) / 2;
    final frontCount = longitudinal.where((value) => value <= longitudinalMid).length;
    final leftCount = lateral.where((value) => value <= lateralMid).length;

    var score = wheels.fold<double>(0.0, (sum, wheel) => sum + wheel.score);
    if (frontCount == 2) score += 1.0;
    if (leftCount == 2) score += 1.0;

    final pairWidth = (lateral.reduce(max) - lateral.reduce(min)).abs();
    final pairLength = (longitudinal.reduce(max) - longitudinal.reduce(min)).abs();
    if (pairWidth > 1e-4 && pairLength > 1e-4) {
      final aspect = pairLength / pairWidth;
      final expectedAspect = model.worldBBox.size.z.abs() /
          max(model.worldBBox.size.x.abs(), 1e-4);
      score += (1.0 - (aspect - expectedAspect).abs() /
              max(expectedAspect, 1.0))
          .clamp(-1.0, 1.0)
          .toDouble();
    }
    return score;
  }

  /// Fallback: find bottom-most mesh nodes that appear in symmetric pairs.
  static void _positionBasedDetection(
    ParsedModel model,
    List<DetectedWheel> existing,
  ) {
    final existingIndices = existing
        .expand((w) => w.partNodeIndices.isEmpty
            ? <int>[w.nodeIndex]
            : w.partNodeIndices)
        .toSet();

    // Collect candidate nodes: those that have a mesh and sit in the lower
    // quarter of the model's vertical extent.
    final bbox = model.worldBBox;
    final lowY = bbox.lo.y + bbox.size.y * 0.35;

    final lows = <SceneNode>[];
    for (final node in model.nodes) {
      if (existingIndices.contains(node.index)) continue;
      if (node.meshIndex == null) continue;
      final nodeCenter = _nodeWorldBounds(model, node).center;
      if (nodeCenter.y <= lowY) {
        lows.add(node);
      }
    }

    // Look for symmetric pairs across the X axis.
    for (var i = 0; i < lows.length; i++) {
      final a = lows[i];
      final ap = _nodeWorldBounds(model, a).center;
      for (var j = i + 1; j < lows.length; j++) {
        final b = lows[j];
        final bp = _nodeWorldBounds(model, b).center;

        // Mirror test: similar |X|, similar Y, similar Z.
        if ((ap.x + bp.x).abs() < bbox.size.x * 0.15 &&
            (ap.y - bp.y).abs() < bbox.size.y * 0.15 &&
            (ap.z - bp.z).abs() < bbox.size.z * 0.15) {
          if (!existingIndices.contains(a.index)) {
            existing.add(DetectedWheel(
              nodeIndex: a.index,
              nodeName: a.name,
              worldPosition: _nodeWorldBounds(model, a).center,
              confidence: 0.55,
              meshIndex: a.meshIndex,
              partNodeIndices: [a.index],
            ));
            existingIndices.add(a.index);
          }
          if (!existingIndices.contains(b.index)) {
            existing.add(DetectedWheel(
              nodeIndex: b.index,
              nodeName: b.name,
              worldPosition: _nodeWorldBounds(model, b).center,
              confidence: 0.55,
              meshIndex: b.meshIndex,
              partNodeIndices: [b.index],
            ));
            existingIndices.add(b.index);
          }
          if (existing.length >= 4) break;
        }
      }
      if (existing.length >= 4) break;
    }
  }

  static _VehicleAxes _inferVehicleAxes(ParsedModel model) {
    final points = <Vec3>[];
    for (final instance in model.instances) {
      final vertices = instance.worldVertices;
      if (vertices.isEmpty) {
        points.add(instance.worldBBox.center);
        continue;
      }
      final step = max(1, vertices.length ~/ 128);
      for (var i = 0; i < vertices.length; i += step) {
        points.add(vertices[i]);
      }
    }

    if (points.length < 2) {
      return const _VehicleAxes(
        longitudinal: Vec3(0, 0, 1),
        lateral: Vec3(1, 0, 0),
      );
    }

    var meanX = 0.0;
    var meanZ = 0.0;
    for (final point in points) {
      meanX += point.x;
      meanZ += point.z;
    }
    meanX /= points.length;
    meanZ /= points.length;

    var xx = 0.0;
    var xz = 0.0;
    var zz = 0.0;
    for (final point in points) {
      final x = point.x - meanX;
      final z = point.z - meanZ;
      xx += x * x;
      xz += x * z;
      zz += z * z;
    }

    final angle = 0.5 * atan2(2 * xz, xx - zz);
    var longitudinal = Vec3(cos(angle), 0, sin(angle)).normalized;

    // Preserve the common glTF convention where negative Z is the front of
    // the car. For rotated models, this still gives a stable front/rear axis.
    if (longitudinal.z < 0 ||
        (longitudinal.z.abs() < longitudinal.x.abs() && longitudinal.x < 0)) {
      longitudinal = -longitudinal;
    }

    var lateral = Vec3(longitudinal.z, 0, -longitudinal.x).normalized;
    if (lateral.x < 0) lateral = -lateral;
    return _VehicleAxes(longitudinal: longitudinal, lateral: lateral);
  }

  static void _assignAxleSide(ParsedModel model, List<DetectedWheel> wheels) {
    if (wheels.length < 2) {
      for (final w in wheels) {
        w.axle = 'front';
        w.side = w.worldPosition.x <= 0 ? 'left' : 'right';
      }
      return;
    }

    final axes = _inferVehicleAxes(model);
    final longitudinal = wheels
        .map((wheel) => wheel.worldPosition.dot(axes.longitudinal))
        .toList()
      ..sort();
    final lateral = wheels
        .map((wheel) => wheel.worldPosition.dot(axes.lateral))
        .toList()
      ..sort();
    final midLongitudinal = (longitudinal.first + longitudinal.last) / 2;
    final midLateral = (lateral.first + lateral.last) / 2;

    for (final w in wheels) {
      final longPosition = w.worldPosition.dot(axes.longitudinal);
      final sidePosition = w.worldPosition.dot(axes.lateral);
      w.axle = longPosition <= midLongitudinal ? 'front' : 'rear';
      w.side = sidePosition <= midLateral ? 'left' : 'right';
    }
  }

  // ── Body Detection ────────────────────────────────────────────────────

  static DetectedBody? _detectBody(
    ParsedModel model,
    List<DetectedWheel> wheels,
  ) {
    final wheelNodeIndices = wheels
        .expand((w) => w.partNodeIndices.isEmpty
            ? <int>[w.nodeIndex]
            : w.partNodeIndices)
        .toSet();
    // Also exclude mesh indices used by wheels.
    final wheelMeshIndices = wheels
        .where((w) => w.meshIndex != null)
        .map((w) => w.meshIndex!)
        .toSet();
    final instancesByNode = <int, MeshInstance>{
      for (final instance in model.instances) instance.nodeIndex: instance,
    };

    // Strategy 1: name matching.
    final bodyPattern = RegExp(
      r'(body|chassis|car.?body|hull|frame|cabin|shell)',
      caseSensitive: false,
    );
    for (final node in model.nodes) {
      if (wheelNodeIndices.contains(node.index)) continue;
      if (bodyPattern.hasMatch(node.name) && node.meshIndex != null) {
        return DetectedBody(
          nodeIndex: node.index,
          nodeName: node.name,
          worldBBox: instancesByNode[node.index]?.worldBBox ??
              _nodeWorldBounds(model, node),
          confidence: 0.85,
        );
      }
    }

    // Strategy 2: largest non-wheel mesh node by bounding-box volume. Using
    // nodes rather than only instances also covers valid scene graphs where a
    // mesh instance was not materialized by the parser.
    SceneNode? best;
    BBox? bestBounds;
    double bestVol = 0;
    for (final node in model.nodes) {
      if (wheelNodeIndices.contains(node.index) || node.meshIndex == null) {
        continue;
      }
      if (wheelMeshIndices.contains(node.meshIndex)) continue;
      final bounds = instancesByNode[node.index]?.worldBBox ??
          _nodeWorldBounds(model, node);
      final s = bounds.size;
      final vol = s.x.abs() * s.y.abs() * s.z.abs();
      if (vol > bestVol) {
        bestVol = vol;
        best = node;
        bestBounds = bounds;
      }
    }
    if (best == null) return null;

    return DetectedBody(
      nodeIndex: best.index,
      nodeName: best.name,
      worldBBox: bestBounds!,
      confidence: 0.6,
    );
  }

  // ── Drivetrain ────────────────────────────────────────────────────────

  static String _suggestDrive(ParsedModel model, List<DetectedWheel> wheels) {
    final name = model.fileName.toLowerCase();
    if (name.contains('sport') || name.contains('race')) return 'RWD';
    if (name.contains('van') || name.contains('truck')) return 'RWD';
    return 'AWD';
  }

  // ── Preset ────────────────────────────────────────────────────────────

  static String _suggestPreset(ParsedModel model) {
    final size = model.worldBBox.size;
    final height = size.y.abs();
    final length = size.z.abs();

    if (length > 5.5) return 'Delivery van';
    if (height > 1.8) return 'Off-road rig';
    return 'Sports coupe';
  }
}
