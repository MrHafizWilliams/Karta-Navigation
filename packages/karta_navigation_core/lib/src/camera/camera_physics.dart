import 'package:meta/meta.dart';

@immutable
class AdaptiveCameraPose {
  const AdaptiveCameraPose({
    required this.zoom,
    required this.pitchDeg,
    required this.paddingTopPx,
    required this.paddingBottomPx,
    required this.declutterMinorLabels,
  });

  final double zoom;
  final double pitchDeg;
  final double paddingTopPx;
  final double paddingBottomPx;
  final bool declutterMinorLabels;
}

/// Smooth speed-adaptive camera physics model for active 3D driving.
///
/// Continuously interpolates zoom, pitch, and look-ahead horizon framing as speed
/// climbs from 30 km/h city streets (George Town / KLCC / Orchard) to 110 km/h
/// on the North-South Expressway (E1 / E2), while softly zooming back in when
/// approaching a turn maneuver within 350 m.
class CameraPhysicsModel {
  CameraPhysicsModel({
    this.smoothingAlpha = 0.28,
  });

  final double smoothingAlpha;

  double? _smoothedZoom;
  double? _smoothedPitch;
  double? _smoothedTopPadding;
  bool _declutterActive = false;

  /// Pure stateless target calculation for a given speed and turn proximity.
  static AdaptiveCameraPose computeTarget({
    required double speedKmh,
    required bool is3DEnabled,
    double? distanceToManeuverMeters,
    bool previousDeclutterActive = false,
  }) {
    // Normalize speed across [30 km/h .. 110 km/h] using smoothstep curve
    final rawT = ((speedKmh - 30.0) / 80.0).clamp(0.0, 1.0);
    final t = rawT * rawT * (3.0 - 2.0 * rawT);

    // City (30 km/h): zoom 17.6, pitch 48°, paddingTop 160
    // Highway (110 km/h): zoom 15.0, pitch 66°, paddingTop 235
    var targetZoom = 17.6 - (2.6 * t);
    var targetPitch = is3DEnabled ? (48.0 + (18.0 * t)) : 0.0;
    var targetTopPad = 160.0 + (75.0 * t);

    // Anticipate upcoming turns (< 350m): ease closer and soften pitch for junction clarity
    if (distanceToManeuverMeters != null &&
        distanceToManeuverMeters > 0 &&
        distanceToManeuverMeters < 350.0) {
      final turnWeight = (1.0 - (distanceToManeuverMeters / 350.0)).clamp(0.0, 1.0);
      targetZoom = (targetZoom + 0.75 * turnWeight).clamp(14.8, 18.2);
      if (is3DEnabled) {
        targetPitch = (targetPitch - 6.0 * turnWeight).clamp(44.0, 66.0);
      }
      targetTopPad = targetTopPad - 20.0 * turnWeight;
    }

    // Hysteresis around 60 km/h for minor street label declutter (on >= 60, off <= 55)
    final declutter = previousDeclutterActive
        ? speedKmh > 55.0
        : speedKmh >= 60.0;

    return AdaptiveCameraPose(
      zoom: targetZoom,
      pitchDeg: targetPitch,
      paddingTopPx: targetTopPad,
      paddingBottomPx: 96.0,
      declutterMinorLabels: declutter,
    );
  }

  /// Critically-damped exponential filter preventing harsh camera jerks during speed spikes.
  AdaptiveCameraPose step({
    required double speedKmh,
    required bool is3DEnabled,
    double? distanceToManeuverMeters,
  }) {
    final target = computeTarget(
      speedKmh: speedKmh,
      is3DEnabled: is3DEnabled,
      distanceToManeuverMeters: distanceToManeuverMeters,
      previousDeclutterActive: _declutterActive,
    );
    _declutterActive = target.declutterMinorLabels;

    if (_smoothedZoom == null || _smoothedPitch == null || _smoothedTopPadding == null) {
      _smoothedZoom = target.zoom;
      _smoothedPitch = target.pitchDeg;
      _smoothedTopPadding = target.paddingTopPx;
    } else {
      _smoothedZoom = _smoothedZoom! + (target.zoom - _smoothedZoom!) * smoothingAlpha;
      _smoothedPitch = _smoothedPitch! + (target.pitchDeg - _smoothedPitch!) * smoothingAlpha;
      _smoothedTopPadding =
          _smoothedTopPadding! + (target.paddingTopPx - _smoothedTopPadding!) * smoothingAlpha;
    }

    return AdaptiveCameraPose(
      zoom: _smoothedZoom!,
      pitchDeg: _smoothedPitch!,
      paddingTopPx: _smoothedTopPadding!,
      paddingBottomPx: target.paddingBottomPx,
      declutterMinorLabels: _declutterActive,
    );
  }

  void reset() {
    _smoothedZoom = null;
    _smoothedPitch = null;
    _smoothedTopPadding = null;
    _declutterActive = false;
  }
}
