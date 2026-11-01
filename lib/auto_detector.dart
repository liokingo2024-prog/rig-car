import 'model_data.dart';

// ── Auto-detector ───────────────────────────────────────────────────────────
//
// Heuristic engine that analyses a [ParsedModel] and returns a
// [DetectionResult] with identified wheels, body, drivetrain, and preset.

class AutoDetector {
  // ── Public API ──────────────────────────────────────────────────────────

  static DetectionResult detect(ParsedModel model) {
    final wheels = _detectWheels(model);
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

    return DetectionResult(
      wheels: wheels.take(4).toList(),
      body: body,
      suggestedDrive: drive,
      suggestedPreset: preset,
      warnings: warnings,
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

  static List<DetectedWheel> _detectWheels(ParsedModel model) {
    final candidates = <DetectedWheel>[];

    // Strategy 1 — name matching (high confidence)
    for (final node in model.nodes) {
      if (_excludePattern.hasMatch(node.name)) continue;
      if (_wheelPattern.hasMatch(node.name)) {
        candidates.add(DetectedWheel(
          nodeIndex: node.index,
          nodeName: node.name,
          worldPosition: node.worldTransform.translation,
          confidence: 0.9,
          meshIndex: node.meshIndex,
        ));
      }
    }

    // If we already have ≥4 by name, skip position-based detection.
    if (candidates.length < 4) {
      _positionBasedDetection(model, candidates);
    }

    // Assign front/rear and left/right based on positions.
    _assignAxleSide(candidates);

    // Sort by confidence, then by axle-side label for stability.
    candidates.sort((a, b) {
      final c = b.confidence.compareTo(a.confidence);
      if (c != 0) return c;
      return a.label.compareTo(b.label);
    });

    return candidates;
  }

  /// Fallback: find bottom-most mesh nodes that appear in symmetric pairs.
  static void _positionBasedDetection(
    ParsedModel model,
    List<DetectedWheel> existing,
  ) {
    final existingIndices = existing.map((w) => w.nodeIndex).toSet();

    // Collect candidate nodes: those that have a mesh and sit in the lower
    // quarter of the model's vertical extent.
    final bbox = model.worldBBox;
    final lowY = bbox.lo.y + bbox.size.y * 0.35;

    final lows = <SceneNode>[];
    for (final node in model.nodes) {
      if (existingIndices.contains(node.index)) continue;
      if (node.meshIndex == null) continue;
      if (node.worldTransform.translation.y <= lowY) {
        lows.add(node);
      }
    }

    // Look for symmetric pairs across the X axis.
    for (var i = 0; i < lows.length; i++) {
      final a = lows[i];
      final ap = a.worldTransform.translation;
      for (var j = i + 1; j < lows.length; j++) {
        final b = lows[j];
        final bp = b.worldTransform.translation;

        // Mirror test: similar |X|, similar Y, similar Z.
        if ((ap.x + bp.x).abs() < bbox.size.x * 0.15 &&
            (ap.y - bp.y).abs() < bbox.size.y * 0.15 &&
            (ap.z - bp.z).abs() < bbox.size.z * 0.15) {
          if (!existingIndices.contains(a.index)) {
            existing.add(DetectedWheel(
              nodeIndex: a.index,
              nodeName: a.name,
              worldPosition: ap,
              confidence: 0.55,
              meshIndex: a.meshIndex,
            ));
            existingIndices.add(a.index);
          }
          if (!existingIndices.contains(b.index)) {
            existing.add(DetectedWheel(
              nodeIndex: b.index,
              nodeName: b.name,
              worldPosition: bp,
              confidence: 0.55,
              meshIndex: b.meshIndex,
            ));
            existingIndices.add(b.index);
          }
        }
      }
    }
  }

  static void _assignAxleSide(List<DetectedWheel> wheels) {
    if (wheels.length < 2) {
      for (final w in wheels) {
        w.axle = 'front';
        w.side = w.worldPosition.x < 0 ? 'left' : 'right';
      }
      return;
    }

    // Determine the Z midpoint to split front / rear.
    final zValues = wheels.map((w) => w.worldPosition.z).toList()..sort();
    final midZ = (zValues.first + zValues.last) / 2;

    for (final w in wheels) {
      // glTF convention: -Z is often forward.  We compare relative to mid.
      w.axle = w.worldPosition.z <= midZ ? 'front' : 'rear';
      w.side = w.worldPosition.x < 0 ? 'left' : 'right';
    }
  }

  // ── Body Detection ────────────────────────────────────────────────────

  static DetectedBody? _detectBody(
    ParsedModel model,
    List<DetectedWheel> wheels,
  ) {
    final wheelNodeIndices = wheels.map((w) => w.nodeIndex).toSet();
    // Also exclude mesh indices used by wheels.
    final wheelMeshIndices = wheels
        .where((w) => w.meshIndex != null)
        .map((w) => w.meshIndex!)
        .toSet();

    // Strategy 1: name matching.
    final bodyPattern = RegExp(
      r'(body|chassis|car.?body|hull|frame|cabin|shell)',
      caseSensitive: false,
    );
    for (final node in model.nodes) {
      if (wheelNodeIndices.contains(node.index)) continue;
      if (bodyPattern.hasMatch(node.name) && node.meshIndex != null) {
        final inst = model.instances.firstWhere(
          (i) => i.nodeIndex == node.index,
          orElse: () => model.instances.first,
        );
        return DetectedBody(
          nodeIndex: node.index,
          nodeName: node.name,
          worldBBox: inst.worldBBox,
          confidence: 0.85,
        );
      }
    }

    // Strategy 2: largest non-wheel mesh instance by bounding-box volume.
    MeshInstance? best;
    double bestVol = 0;
    for (final inst in model.instances) {
      if (wheelNodeIndices.contains(inst.nodeIndex)) continue;
      if (wheelMeshIndices.contains(inst.meshIndex)) continue;
      final s = inst.worldBBox.size;
      final vol = s.x.abs() * s.y.abs() * s.z.abs();
      if (vol > bestVol) {
        bestVol = vol;
        best = inst;
      }
    }
    if (best == null) return null;

    return DetectedBody(
      nodeIndex: best.nodeIndex,
      nodeName: model.nodes[best.nodeIndex].name,
      worldBBox: best.worldBBox,
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
