import 'package:karta_api_client/karta_api_client.dart';
import 'package:meta/meta.dart';

enum SpeedAlertSeverity {
  normal,
  caution, // 1..9 km/h over limit
  alert, // >= 10 km/h over limit
}

@immutable
class SpeedTelemetryState {
  const SpeedTelemetryState({
    required this.currentSpeedKmh,
    this.speedLimitKmh,
    this.speedLimitSource,
    required this.severity,
    this.overLimitByKmh = 0,
    this.approachingCamera,
  });

  final double currentSpeedKmh;
  final int? speedLimitKmh;
  final String? speedLimitSource;
  final SpeedAlertSeverity severity;
  final int overLimitByKmh;
  final ApproachingSpeedZone? approachingCamera;
}

/// Evaluates live GPS speed against PostGIS road speed limits and approaching
/// Malaysian AWAS / Singapore TP speed enforcement cameras.
abstract final class SpeedLimitMonitor {
  static SpeedTelemetryState evaluate({
    required double currentSpeedKmh,
    int? roadSpeedLimitKmh,
    String? speedLimitSource,
    List<ApproachingSpeedZone> approachingZones = const <ApproachingSpeedZone>[],
  }) {
    final nearestZone = approachingZones.isNotEmpty ? approachingZones.first : null;
    final effectiveLimit =
        (nearestZone != null && nearestZone.distanceMeters <= 450 && nearestZone.limitKmh > 0)
            ? nearestZone.limitKmh
            : roadSpeedLimitKmh;

    if (effectiveLimit == null || effectiveLimit <= 0) {
      return SpeedTelemetryState(
        currentSpeedKmh: currentSpeedKmh,
        speedLimitKmh: null,
        speedLimitSource: speedLimitSource,
        severity: SpeedAlertSeverity.normal,
        approachingCamera: nearestZone,
      );
    }

    final delta = (currentSpeedKmh - effectiveLimit).round();
    final severity = delta >= 10
        ? SpeedAlertSeverity.alert
        : (delta >= 1 ? SpeedAlertSeverity.caution : SpeedAlertSeverity.normal);

    return SpeedTelemetryState(
      currentSpeedKmh: currentSpeedKmh,
      speedLimitKmh: effectiveLimit,
      speedLimitSource: speedLimitSource,
      severity: severity,
      overLimitByKmh: delta > 0 ? delta : 0,
      approachingCamera: nearestZone,
    );
  }
}
