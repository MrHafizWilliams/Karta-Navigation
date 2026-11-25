import 'dart:async';
import 'package:meta/meta.dart';

/// Unified cross-platform thermal severity mapped from:
/// - iOS: `ProcessInfo.ThermalState` (`.nominal`, `.fair`, `.serious`, `.critical`)
/// - Android: `PowerManager.THERMAL_STATUS_*` (`NONE`/`LIGHT`, `MODERATE`, `SEVERE`, `CRITICAL`+)
enum DeviceThermalLevel {
  nominal('nominal', 0, 'Nominal'),
  fair('fair', 1, 'Warm'),
  serious('serious', 2, 'Hot — Throttling'),
  critical('critical', 3, 'Critical — Cooling');

  const DeviceThermalLevel(this.wireValue, this.severityRank, this.label);

  final String wireValue;
  final int severityRank;
  final String label;

  static DeviceThermalLevel fromWire(String raw) {
    final norm = raw.trim().toLowerCase();
    for (final level in DeviceThermalLevel.values) {
      if (level.wireValue == norm) return level;
    }
    return DeviceThermalLevel.nominal;
  }

  /// Maps iOS `ProcessInfo.ThermalState.rawValue` (0..3).
  static DeviceThermalLevel fromIosRawValue(int rawValue) {
    return switch (rawValue) {
      <= 0 => DeviceThermalLevel.nominal,
      1 => DeviceThermalLevel.fair,
      2 => DeviceThermalLevel.serious,
      _ => DeviceThermalLevel.critical,
    };
  }

  /// Maps Android `PowerManager.THERMAL_STATUS_*` (0..6).
  static DeviceThermalLevel fromAndroidThermalStatus(int status) {
    if (status <= 1) return DeviceThermalLevel.nominal; // NONE, LIGHT
    if (status == 2) return DeviceThermalLevel.fair; // MODERATE
    if (status == 3) return DeviceThermalLevel.serious; // SEVERE
    return DeviceThermalLevel.critical; // CRITICAL, EMERGENCY, SHUTDOWN
  }
}

/// Raw device thermal & power telemetry reported by iOS CarPlay or Android Auto.
@immutable
class ThermalTelemetryInput {
  const ThermalTelemetryInput({
    this.deviceThermalLevel = DeviceThermalLevel.nominal,
    this.batteryLevelPercent,
    this.isCharging = false,
    this.batteryTempCelsius,
    this.isLowPowerMode = false,
    this.isProjectedToHeadUnit = false,
    this.headUnitPlatform,
    this.timestamp,
  });

  final DeviceThermalLevel deviceThermalLevel;
  final int? batteryLevelPercent;
  final bool isCharging;
  final double? batteryTempCelsius;
  final bool isLowPowerMode;
  final bool isProjectedToHeadUnit;
  final String? headUnitPlatform;
  final DateTime? timestamp;

  ThermalTelemetryInput copyWith({
    DeviceThermalLevel? deviceThermalLevel,
    int? batteryLevelPercent,
    bool? isCharging,
    double? batteryTempCelsius,
    bool? isLowPowerMode,
    bool? isProjectedToHeadUnit,
    String? headUnitPlatform,
    bool clearHeadUnitPlatform = false,
    DateTime? timestamp,
  }) =>
      ThermalTelemetryInput(
        deviceThermalLevel: deviceThermalLevel ?? this.deviceThermalLevel,
        batteryLevelPercent: batteryLevelPercent ?? this.batteryLevelPercent,
        isCharging: isCharging ?? this.isCharging,
        batteryTempCelsius: batteryTempCelsius ?? this.batteryTempCelsius,
        isLowPowerMode: isLowPowerMode ?? this.isLowPowerMode,
        isProjectedToHeadUnit: isProjectedToHeadUnit ?? this.isProjectedToHeadUnit,
        headUnitPlatform:
            clearHeadUnitPlatform ? null : (headUnitPlatform ?? this.headUnitPlatform),
        timestamp: timestamp ?? this.timestamp,
      );
}

/// Actionable rendering & polling budget applied simultaneously to:
/// 1. Vehicle head-unit MapLibre renderer (`MLNMapView` / Android `MapView`)
/// 2. Phone companion `KartaMapController`
/// 3. Bridge frame cadence & PostGIS road-context polling interval
@immutable
class ThermalRenderProfile {
  const ThermalRenderProfile({
    required this.effectiveTier,
    required this.headUnitTargetFps,
    required this.phoneTargetFps,
    required this.pausePhoneMapCanvas,
    required this.enableHeadUnit3DBuildings,
    required this.enablePhone3DBuildings,
    required this.enableVehicleHaloShader,
    required this.headUnitCameraPitchDeg,
    required this.bridgePublishIntervalMs,
    required this.roadContextPollIntervalMs,
    required this.maxOfflineTileCacheMb,
    required this.isProjectedToHeadUnit,
    required this.reason,
  });

  final DeviceThermalLevel effectiveTier;
  final int headUnitTargetFps;
  final int phoneTargetFps;
  final bool pausePhoneMapCanvas;
  final bool enableHeadUnit3DBuildings;
  final bool enablePhone3DBuildings;
  final bool enableVehicleHaloShader;
  final double headUnitCameraPitchDeg;
  final int bridgePublishIntervalMs;
  final int roadContextPollIntervalMs;
  final int maxOfflineTileCacheMb;
  final bool isProjectedToHeadUnit;
  final String reason;

  Duration get roadContextPollInterval => Duration(milliseconds: roadContextPollIntervalMs);
  Duration get bridgePublishInterval => Duration(milliseconds: bridgePublishIntervalMs);

  Map<String, dynamic> toMap() => <String, dynamic>{
        'thermalTier': effectiveTier.wireValue,
        'headUnitTargetFps': headUnitTargetFps,
        'phoneTargetFps': phoneTargetFps,
        'pausePhoneMapCanvas': pausePhoneMapCanvas,
        'enableHeadUnit3DBuildings': enableHeadUnit3DBuildings,
        'enablePhone3DBuildings': enablePhone3DBuildings,
        'enableVehicleHaloShader': enableVehicleHaloShader,
        'headUnitCameraPitchDeg': headUnitCameraPitchDeg,
        'bridgePublishIntervalMs': bridgePublishIntervalMs,
        'roadContextPollIntervalMs': roadContextPollIntervalMs,
        'maxOfflineTileCacheMb': maxOfflineTileCacheMb,
        'isProjectedToHeadUnit': isProjectedToHeadUnit,
        'reason': reason,
      };

  factory ThermalRenderProfile.fromMap(Map<String, dynamic> map) => ThermalRenderProfile(
        effectiveTier: DeviceThermalLevel.fromWire((map['thermalTier'] as String?) ?? 'nominal'),
        headUnitTargetFps: (map['headUnitTargetFps'] as num?)?.toInt() ?? 60,
        phoneTargetFps: (map['phoneTargetFps'] as num?)?.toInt() ?? 60,
        pausePhoneMapCanvas: (map['pausePhoneMapCanvas'] as bool?) ?? false,
        enableHeadUnit3DBuildings: (map['enableHeadUnit3DBuildings'] as bool?) ?? true,
        enablePhone3DBuildings: (map['enablePhone3DBuildings'] as bool?) ?? true,
        enableVehicleHaloShader: (map['enableVehicleHaloShader'] as bool?) ?? true,
        headUnitCameraPitchDeg: (map['headUnitCameraPitchDeg'] as num?)?.toDouble() ?? 58.0,
        bridgePublishIntervalMs: (map['bridgePublishIntervalMs'] as num?)?.toInt() ?? 100,
        roadContextPollIntervalMs: (map['roadContextPollIntervalMs'] as num?)?.toInt() ?? 2000,
        maxOfflineTileCacheMb: (map['maxOfflineTileCacheMb'] as num?)?.toInt() ?? 128,
        isProjectedToHeadUnit: (map['isProjectedToHeadUnit'] as bool?) ?? false,
        reason: (map['reason'] as String?) ?? 'Nominal operation',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThermalRenderProfile &&
          effectiveTier == other.effectiveTier &&
          headUnitTargetFps == other.headUnitTargetFps &&
          phoneTargetFps == other.phoneTargetFps &&
          pausePhoneMapCanvas == other.pausePhoneMapCanvas &&
          enableHeadUnit3DBuildings == other.enableHeadUnit3DBuildings &&
          enablePhone3DBuildings == other.enablePhone3DBuildings &&
          enableVehicleHaloShader == other.enableVehicleHaloShader &&
          headUnitCameraPitchDeg == other.headUnitCameraPitchDeg &&
          bridgePublishIntervalMs == other.bridgePublishIntervalMs &&
          roadContextPollIntervalMs == other.roadContextPollIntervalMs &&
          maxOfflineTileCacheMb == other.maxOfflineTileCacheMb &&
          isProjectedToHeadUnit == other.isProjectedToHeadUnit;

  @override
  int get hashCode => Object.hash(
        effectiveTier,
        headUnitTargetFps,
        phoneTargetFps,
        pausePhoneMapCanvas,
        enableHeadUnit3DBuildings,
        enablePhone3DBuildings,
        enableVehicleHaloShader,
        headUnitCameraPitchDeg,
        bridgePublishIntervalMs,
        roadContextPollIntervalMs,
        maxOfflineTileCacheMb,
        isProjectedToHeadUnit,
      );
}

/// Adaptive frame-rate and thermal governor for extended CarPlay / Android Auto
/// navigation sessions in tropical MY/SG/BN cabin conditions.
///
/// - Escalates immediately when OS thermal pressure or battery heat increases.
/// - Applies anti-oscillation hysteresis ([recoveryCooldown]) before stepping
///   FPS or 3D building extrusions back up.
/// - Automatically throttles the phone companion GPU while vehicle head-unit
///   projection is active so dual-display rendering never causes thermal runaway.
class ThermalAdaptationController {
  ThermalAdaptationController({
    DateTime Function()? clock,
    this.recoveryCooldown = const Duration(seconds: 20),
  }) : _clock = clock ?? DateTime.now {
    _profile = _buildProfile(
      tier: DeviceThermalLevel.nominal,
      projected: false,
      reason: 'Nominal phone operation',
    );
  }

  final DateTime Function() _clock;
  final Duration recoveryCooldown;
  final StreamController<ThermalRenderProfile> _controller =
      StreamController<ThermalRenderProfile>.broadcast();

  ThermalTelemetryInput _lastInput = const ThermalTelemetryInput();
  late ThermalRenderProfile _profile;
  DeviceThermalLevel _activeTier = DeviceThermalLevel.nominal;
  DateTime? _cooldownCandidateSince;
  DeviceThermalLevel? _cooldownCandidateTier;

  ThermalRenderProfile get currentProfile => _profile;
  ThermalTelemetryInput get lastInput => _lastInput;
  Stream<ThermalRenderProfile> get stream => _controller.stream;

  /// Updates projection state immediately (e.g., USB/wireless CarPlay or Android Auto connect).
  ThermalRenderProfile setProjectedToHeadUnit(bool projected, {String? platform}) {
    return updateTelemetry(
      _lastInput.copyWith(
        isProjectedToHeadUnit: projected,
        headUnitPlatform: platform,
        clearHeadUnitPlatform: !projected,
        timestamp: _clock(),
      ),
    );
  }

  /// Processes new device thermal/battery telemetry and computes the effective
  /// [ThermalRenderProfile] with immediate escalation and cooldown-gated recovery.
  ThermalRenderProfile updateTelemetry(ThermalTelemetryInput input) {
    final now = input.timestamp ?? _clock();
    _lastInput = input.copyWith(timestamp: now);

    final (:tier, :reason) = _evaluateRawPressure(input);

    if (tier.severityRank > _activeTier.severityRank) {
      // Escalate immediately to protect thermals and prevent OS GPU kill.
      _activeTier = tier;
      _cooldownCandidateSince = null;
      _cooldownCandidateTier = null;
    } else if (tier.severityRank < _activeTier.severityRank) {
      // Recovery requires sustained cool-down dwell to avoid 3D/FPS flicker.
      if (_cooldownCandidateTier == null ||
          tier.severityRank > _cooldownCandidateTier!.severityRank) {
        _cooldownCandidateTier = tier;
        _cooldownCandidateSince = now;
      } else if (_cooldownCandidateSince != null &&
          now.difference(_cooldownCandidateSince!) >= recoveryCooldown) {
        _activeTier = tier;
        _cooldownCandidateSince = null;
        _cooldownCandidateTier = null;
      }
    } else {
      _cooldownCandidateSince = null;
      _cooldownCandidateTier = null;
    }

    final nextProfile = _buildProfile(
      tier: _activeTier,
      projected: input.isProjectedToHeadUnit,
      reason: _activeTier == tier
          ? reason
          : 'Cooling hysteresis active (${_activeTier.label} -> ${tier.label})',
    );

    if (nextProfile != _profile) {
      _profile = nextProfile;
      if (!_controller.isClosed) {
        _controller.add(_profile);
      }
    }
    return _profile;
  }

  ({DeviceThermalLevel tier, String reason}) _evaluateRawPressure(ThermalTelemetryInput input) {
    var rank = input.deviceThermalLevel.severityRank;
    final reasons = <String>[];

    if (input.deviceThermalLevel != DeviceThermalLevel.nominal) {
      reasons.add('OS thermal ${input.deviceThermalLevel.wireValue}');
    }

    // Tropical dashboard + wireless charger thermal guard (MY / SG / BN midday sun)
    final temp = input.batteryTempCelsius;
    if (temp != null) {
      if (temp >= 45.0) {
        if (rank < DeviceThermalLevel.critical.severityRank) {
          rank = DeviceThermalLevel.critical.severityRank;
        }
        reasons.add('Battery ${temp.toStringAsFixed(1)}°C');
      } else if (temp >= 41.5 || (input.isCharging && temp >= 39.5)) {
        if (rank < DeviceThermalLevel.serious.severityRank) {
          rank = DeviceThermalLevel.serious.severityRank;
        }
        reasons.add('Warm battery ${temp.toStringAsFixed(1)}°C');
      } else if (input.isCharging && temp >= 37.5) {
        if (rank < DeviceThermalLevel.fair.severityRank) {
          rank = DeviceThermalLevel.fair.severityRank;
        }
        reasons.add('Charging thermal rise (${temp.toStringAsFixed(1)}°C)');
      }
    }

    // Low Power Mode or critical battery (< 15% unplugged) steps down GPU load
    if (input.isLowPowerMode ||
        (!input.isCharging && (input.batteryLevelPercent ?? 100) <= 15)) {
      if (rank < DeviceThermalLevel.fair.severityRank) {
        rank = DeviceThermalLevel.fair.severityRank;
      }
      reasons.add(input.isLowPowerMode ? 'Low Power Mode' : 'Low battery <= 15%');
    }

    final effective = DeviceThermalLevel.values[rank.clamp(0, DeviceThermalLevel.values.length - 1)];
    final reason = reasons.isEmpty
        ? (input.isProjectedToHeadUnit
            ? 'Nominal vehicle projection (${input.headUnitPlatform ?? 'head-unit'})'
            : 'Nominal operation')
        : reasons.join(' · ');
    return (tier: effective, reason: reason);
  }

  static ThermalRenderProfile _buildProfile({
    required DeviceThermalLevel tier,
    required bool projected,
    required String reason,
  }) {
    return switch (tier) {
      DeviceThermalLevel.nominal => ThermalRenderProfile(
          effectiveTier: tier,
          headUnitTargetFps: 60,
          phoneTargetFps: projected ? 15 : 60,
          pausePhoneMapCanvas: false,
          enableHeadUnit3DBuildings: true,
          enablePhone3DBuildings: !projected,
          enableVehicleHaloShader: true,
          headUnitCameraPitchDeg: 58.0,
          bridgePublishIntervalMs: 100,
          roadContextPollIntervalMs: 2000,
          maxOfflineTileCacheMb: 128,
          isProjectedToHeadUnit: projected,
          reason: reason,
        ),
      DeviceThermalLevel.fair => ThermalRenderProfile(
          effectiveTier: tier,
          headUnitTargetFps: 45,
          phoneTargetFps: projected ? 10 : 45,
          pausePhoneMapCanvas: false,
          enableHeadUnit3DBuildings: true,
          enablePhone3DBuildings: !projected,
          enableVehicleHaloShader: false,
          headUnitCameraPitchDeg: 52.0,
          bridgePublishIntervalMs: 250,
          roadContextPollIntervalMs: 3000,
          maxOfflineTileCacheMb: 96,
          isProjectedToHeadUnit: projected,
          reason: reason,
        ),
      DeviceThermalLevel.serious => ThermalRenderProfile(
          effectiveTier: tier,
          headUnitTargetFps: 30,
          phoneTargetFps: projected ? 0 : 30,
          pausePhoneMapCanvas: projected,
          enableHeadUnit3DBuildings: false,
          enablePhone3DBuildings: false,
          enableVehicleHaloShader: false,
          headUnitCameraPitchDeg: 32.0,
          bridgePublishIntervalMs: 500,
          roadContextPollIntervalMs: 5000,
          maxOfflineTileCacheMb: 64,
          isProjectedToHeadUnit: projected,
          reason: reason,
        ),
      DeviceThermalLevel.critical => ThermalRenderProfile(
          effectiveTier: tier,
          headUnitTargetFps: 20,
          phoneTargetFps: projected ? 0 : 20,
          pausePhoneMapCanvas: projected,
          enableHeadUnit3DBuildings: false,
          enablePhone3DBuildings: false,
          enableVehicleHaloShader: false,
          headUnitCameraPitchDeg: 0.0,
          bridgePublishIntervalMs: 1000,
          roadContextPollIntervalMs: 8000,
          maxOfflineTileCacheMb: 32,
          isProjectedToHeadUnit: projected,
          reason: reason,
        ),
    };
  }

  void dispose() {
    _controller.close();
  }
}
