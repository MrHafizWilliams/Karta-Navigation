import 'dart:math' as math;
import 'package:karta_api_client/karta_api_client.dart';
import 'package:meta/meta.dart';

/// User lighting mode preference.
enum KartaLightingPreference {
  auto('Auto'),
  day('Day'),
  night('Night');

  const KartaLightingPreference(this.label);
  final String label;
}

/// Active rendered visual palette mode.
enum KartaVisualMode {
  obsidianNight,
  tropicalDaylight,
}

enum KartaLightingReason {
  solarDaytime,
  solarNighttime,
  tunnelOverride,
  vehicleHeadlightSensor,
  manualDay,
  manualNight,
}

@immutable
class KartaLightingState {
  const KartaLightingState({
    required this.preference,
    required this.resolvedMode,
    required this.reason,
    required this.solarElevationDeg,
    required this.isInTunnel,
    required this.tunnelHoldActive,
    this.vehicleHeadlightSynced = false,
  });

  final KartaLightingPreference preference;
  final KartaVisualMode resolvedMode;
  final KartaLightingReason reason;
  final double solarElevationDeg;
  final bool isInTunnel;
  final bool tunnelHoldActive;
  final bool vehicleHeadlightSynced;

  bool get isDaylight => resolvedMode == KartaVisualMode.tropicalDaylight;
  bool get isNight => resolvedMode == KartaVisualMode.obsidianNight;

  String get statusChipLabel {
    if (reason == KartaLightingReason.tunnelOverride) {
      return 'TUNNEL · NIGHT';
    }
    if (reason == KartaLightingReason.vehicleHeadlightSensor) {
      return isDaylight ? 'CAR · DAY' : 'CAR · NIGHT';
    }
    if (preference == KartaLightingPreference.auto) {
      return isDaylight ? 'AUTO · DAY' : 'AUTO · NIGHT';
    }
    return isDaylight ? 'DAYLIGHT' : 'OBSIDIAN';
  }
}

/// Astronomical NOAA solar elevation calculator and tunnel-aware lighting resolver
/// for Malaysia, Singapore, and Brunei.
///
/// Automatically shifts between High-Glare Tropical Daylight Mode (e.g., Penang Bridge
/// at midday noon) and Obsidian Night Mode after sunset or when entering urban tunnels
/// (SMART Tunnel, TRX, CTE, MCE, KPE) with anti-flicker exit hysteresis.
class SolarTunnelLightingEngine {
  SolarTunnelLightingEngine({
    this.tunnelExitHysteresis = const Duration(seconds: 4),
    this.sunriseThresholdDeg = -0.833,
  });

  final Duration tunnelExitHysteresis;
  final double sunriseThresholdDeg;

  DateTime? _lastTunnelSeenAt;

  /// Computes solar altitude angle in degrees `[-90, +90]` for WGS 84 [coordinate]
  /// at [utcTime] using standard NOAA solar position equations.
  static double solarElevationDegrees({
    required Coordinate coordinate,
    required DateTime utcTime,
  }) {
    final utc = utcTime.toUtc();
    final dayOfYear = utc.difference(DateTime.utc(utc.year, 1, 1)).inDays + 1;
    final fractionalHour = utc.hour + (utc.minute / 60.0) + (utc.second / 3600.0);

    // Fractional year gamma (radians)
    final gamma = (2.0 * math.pi / 365.0) * (dayOfYear - 1 + (fractionalHour - 12.0) / 24.0);

    // Equation of time (minutes)
    final eqTime = 229.18 *
        (0.000075 +
            0.001868 * math.cos(gamma) -
            0.032077 * math.sin(gamma) -
            0.014615 * math.cos(2 * gamma) -
            0.040849 * math.sin(2 * gamma));

    // Solar declination angle (radians)
    final decl = 0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma) -
        0.006758 * math.cos(2 * gamma) +
        0.000907 * math.sin(2 * gamma) -
        0.002697 * math.cos(3 * gamma) +
        0.00148 * math.sin(3 * gamma);

    // True solar time (minutes)
    final timeOffset = eqTime + 4.0 * coordinate.lon;
    final trueSolarTimeMin = (fractionalHour * 60.0 + timeOffset) % 1440.0;
    final hourAngleDeg = (trueSolarTimeMin / 4.0) - 180.0;
    final hourAngleRad = hourAngleDeg * math.pi / 180.0;
    final latRad = coordinate.lat * math.pi / 180.0;

    final cosZenith = (math.sin(latRad) * math.sin(decl) +
            math.cos(latRad) * math.cos(decl) * math.cos(hourAngleRad))
        .clamp(-1.0, 1.0);
    final zenithRad = math.acos(cosZenith);
    return 90.0 - (zenithRad * 180.0 / math.pi);
  }

  /// Resolves the active lighting mode given preference, GPS location, current UTC time,
  /// live PostGIS `roadContext.isTunnel` signal, and optional vehicle headlight/dimmer
  /// sensor state (`vehicleHeadlightDark`) reported by CarPlay or Android Auto.
  KartaLightingState resolve({
    required KartaLightingPreference preference,
    required Coordinate coordinate,
    required DateTime nowUtc,
    bool isInTunnel = false,
    bool? vehicleHeadlightDark,
  }) {
    final elevation = solarElevationDegrees(coordinate: coordinate, utcTime: nowUtc);

    if (isInTunnel) {
      _lastTunnelSeenAt = nowUtc;
    }
    final tunnelHoldActive = !isInTunnel &&
        _lastTunnelSeenAt != null &&
        nowUtc.difference(_lastTunnelSeenAt!) < tunnelExitHysteresis;

    if (preference == KartaLightingPreference.day) {
      return KartaLightingState(
        preference: preference,
        resolvedMode: KartaVisualMode.tropicalDaylight,
        reason: KartaLightingReason.manualDay,
        solarElevationDeg: elevation,
        isInTunnel: isInTunnel,
        tunnelHoldActive: false,
      );
    }

    if (preference == KartaLightingPreference.night) {
      return KartaLightingState(
        preference: preference,
        resolvedMode: KartaVisualMode.obsidianNight,
        reason: KartaLightingReason.manualNight,
        solarElevationDeg: elevation,
        isInTunnel: isInTunnel,
        tunnelHoldActive: false,
      );
    }

    // Auto mode: tunnel dip overrides daytime to Obsidian Night cleanly
    if (isInTunnel || tunnelHoldActive) {
      return KartaLightingState(
        preference: preference,
        resolvedMode: KartaVisualMode.obsidianNight,
        reason: KartaLightingReason.tunnelOverride,
        solarElevationDeg: elevation,
        isInTunnel: isInTunnel,
        tunnelHoldActive: tunnelHoldActive,
        vehicleHeadlightSynced: vehicleHeadlightDark != null,
      );
    }

    // Auto mode while connected to CarPlay / Android Auto: obey vehicle headlight/dimmer sensor
    if (vehicleHeadlightDark != null) {
      return KartaLightingState(
        preference: preference,
        resolvedMode: vehicleHeadlightDark
            ? KartaVisualMode.obsidianNight
            : KartaVisualMode.tropicalDaylight,
        reason: KartaLightingReason.vehicleHeadlightSensor,
        solarElevationDeg: elevation,
        isInTunnel: false,
        tunnelHoldActive: false,
        vehicleHeadlightSynced: true,
      );
    }

    final isSunUp = elevation > sunriseThresholdDeg;
    return KartaLightingState(
      preference: preference,
      resolvedMode: isSunUp ? KartaVisualMode.tropicalDaylight : KartaVisualMode.obsidianNight,
      reason: isSunUp ? KartaLightingReason.solarDaytime : KartaLightingReason.solarNighttime,
      solarElevationDeg: elevation,
      isInTunnel: false,
      tunnelHoldActive: false,
    );
  }

  void resetTunnelHold() {
    _lastTunnelSeenAt = null;
  }
}
