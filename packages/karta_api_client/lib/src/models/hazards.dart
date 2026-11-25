import 'package:meta/meta.dart';
import 'common.dart';
import 'routing.dart';

enum HazardCategory {
  police('police', 'Police'),
  accident('accident', 'Accident'),
  pothole('pothole', 'Pothole'),
  hiddenVehicle('hidden_vehicle', 'Hidden Vehicle'),
  roadDebris('road_debris', 'Road Debris'),
  roadClosure('road_closure', 'Road Closure');

  const HazardCategory(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static HazardCategory fromWire(String raw) {
    for (final c in HazardCategory.values) {
      if (c.wireValue == raw) return c;
    }
    return HazardCategory.accident;
  }
}

enum HazardSeverity {
  low('low', 'Minor'),
  medium('medium', 'Moderate'),
  high('high', 'Major');

  const HazardSeverity(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static HazardSeverity fromWire(String raw) {
    for (final s in HazardSeverity.values) {
      if (s.wireValue == raw) return s;
    }
    return HazardSeverity.medium;
  }
}

enum CongestionLevel {
  free('free'),
  moderate('moderate'),
  heavy('heavy'),
  blocked('blocked');

  const CongestionLevel(this.wireValue);

  final String wireValue;

  static CongestionLevel fromWire(String raw) {
    for (final l in CongestionLevel.values) {
      if (l.wireValue == raw) return l;
    }
    return CongestionLevel.moderate;
  }
}

@immutable
class HazardRecord {
  const HazardRecord({
    required this.id,
    required this.category,
    this.subtype,
    this.severity = HazardSeverity.medium,
    this.status = 'active',
    required this.coordinate,
    this.roadHeadingDeg,
    this.oneway = 0,
    this.affectsBothDirections = false,
    this.roadName,
    this.roadRef,
    this.countryCode,
    this.laneHint,
    this.description,
    this.source = 'radial',
    this.confirmations = 1,
    this.denials = 0,
    this.confidenceScore = 0.7,
    this.distanceMeters,
    this.bearingDeltaDeg,
    this.onActiveRoute = false,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final HazardCategory category;
  final String? subtype;
  final HazardSeverity severity;
  final String status;
  final Coordinate coordinate;
  final double? roadHeadingDeg;
  final int oneway;
  final bool affectsBothDirections;
  final String? roadName;
  final String? roadRef;
  final String? countryCode;
  final String? laneHint;
  final String? description;
  final String source;
  final int confirmations;
  final int denials;
  final double confidenceScore;
  final double? distanceMeters;
  final double? bearingDeltaDeg;
  final bool onActiveRoute;
  final DateTime createdAt;
  final DateTime expiresAt;

  factory HazardRecord.fromJson(Map<String, dynamic> json) => HazardRecord(
        id: json['id'] as String,
        category: HazardCategory.fromWire((json['category'] as String?) ?? 'accident'),
        subtype: json['subtype'] as String?,
        severity: HazardSeverity.fromWire((json['severity'] as String?) ?? 'medium'),
        status: (json['status'] as String?) ?? 'active',
        coordinate: Coordinate.fromJson(json['coordinate'] as Map<String, dynamic>),
        roadHeadingDeg: (json['road_heading_deg'] as num?)?.toDouble(),
        oneway: (json['oneway'] as num?)?.toInt() ?? 0,
        affectsBothDirections: (json['affects_both_directions'] as bool?) ?? false,
        roadName: json['road_name'] as String?,
        roadRef: json['road_ref'] as String?,
        countryCode: json['country_code'] as String?,
        laneHint: json['lane_hint'] as String?,
        description: json['description'] as String?,
        source: (json['source'] as String?) ?? 'radial',
        confirmations: (json['confirmations'] as num?)?.toInt() ?? 1,
        denials: (json['denials'] as num?)?.toInt() ?? 0,
        confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.7,
        distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
        bearingDeltaDeg: (json['bearing_delta_deg'] as num?)?.toDouble(),
        onActiveRoute: (json['on_active_route'] as bool?) ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

@immutable
class HazardReportRequest {
  const HazardReportRequest({
    required this.category,
    this.subtype,
    this.severity = HazardSeverity.medium,
    required this.coordinate,
    this.headingDeg,
    this.affectsBothDirections = false,
    this.laneHint,
    this.description,
    this.source = 'radial',
    this.reporterSessionId,
  });

  final HazardCategory category;
  final String? subtype;
  final HazardSeverity severity;
  final Coordinate coordinate;
  final double? headingDeg;
  final bool affectsBothDirections;
  final String? laneHint;
  final String? description;
  final String source;
  final String? reporterSessionId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'category': category.wireValue,
        if (subtype != null) 'subtype': subtype,
        'severity': severity.wireValue,
        'coordinate': coordinate.toJson(),
        if (headingDeg != null) 'heading_deg': headingDeg! % 360.0,
        'affects_both_directions': affectsBothDirections,
        if (laneHint != null) 'lane_hint': laneHint,
        if (description != null) 'description': description,
        'source': source,
        if (reporterSessionId != null) 'reporter_session_id': reporterSessionId,
      };
}

@immutable
class NearbyHazardsResponse {
  const NearbyHazardsResponse({
    required this.effectiveRadiusMeters,
    this.headingDeg,
    required this.speedKmh,
    required this.count,
    required this.hazards,
  });

  final double effectiveRadiusMeters;
  final double? headingDeg;
  final double speedKmh;
  final int count;
  final List<HazardRecord> hazards;

  factory NearbyHazardsResponse.fromJson(Map<String, dynamic> json) => NearbyHazardsResponse(
        effectiveRadiusMeters: (json['effective_radius_meters'] as num).toDouble(),
        headingDeg: (json['heading_deg'] as num?)?.toDouble(),
        speedKmh: (json['speed_kmh'] as num?)?.toDouble() ?? 0.0,
        count: (json['count'] as num).toInt(),
        hazards: (json['hazards'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => HazardRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class CongestionSegment {
  const CongestionSegment({
    required this.startFraction,
    required this.endFraction,
    required this.severity,
    required this.speedKmh,
    this.delaySeconds = 0.0,
    this.hazardId,
    this.label,
  });

  final double startFraction;
  final double endFraction;
  final CongestionLevel severity;
  final int speedKmh;
  final double delaySeconds;
  final String? hazardId;
  final String? label;

  factory CongestionSegment.fromJson(Map<String, dynamic> json) => CongestionSegment(
        startFraction: (json['start_fraction'] as num).toDouble(),
        endFraction: (json['end_fraction'] as num).toDouble(),
        severity: CongestionLevel.fromWire((json['severity'] as String?) ?? 'moderate'),
        speedKmh: (json['speed_kmh'] as num).toInt(),
        delaySeconds: (json['delay_seconds'] as num?)?.toDouble() ?? 0.0,
        hazardId: json['hazard_id'] as String?,
        label: json['label'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'startFraction': startFraction,
        'endFraction': endFraction,
        'severity': severity.wireValue,
        'speedKmh': speedKmh,
        'delaySeconds': delaySeconds,
        if (hazardId != null) 'hazardId': hazardId,
        if (label != null) 'label': label,
      };
}

@immutable
class RerouteProposal {
  const RerouteProposal({
    required this.proposalId,
    required this.reason,
    this.triggerHazardId,
    this.triggerCategory,
    this.currentDelaySeconds = 0.0,
    required this.timeSavedSeconds,
    required this.tollDeltaDisplay,
    this.autoAcceptSeconds = 0,
    required this.proposedRoute,
  });

  final String proposalId;
  final String reason;
  final String? triggerHazardId;
  final HazardCategory? triggerCategory;
  final double currentDelaySeconds;
  final double timeSavedSeconds;
  final String tollDeltaDisplay;
  final int autoAcceptSeconds;
  final CandidateRoute proposedRoute;

  factory RerouteProposal.fromJson(Map<String, dynamic> json) => RerouteProposal(
        proposalId: json['proposal_id'] as String,
        reason: json['reason'] as String,
        triggerHazardId: json['trigger_hazard_id'] as String?,
        triggerCategory: json['trigger_category'] != null
            ? HazardCategory.fromWire(json['trigger_category'] as String)
            : null,
        currentDelaySeconds: (json['current_delay_seconds'] as num?)?.toDouble() ?? 0.0,
        timeSavedSeconds: (json['time_saved_seconds'] as num?)?.toDouble() ?? 0.0,
        tollDeltaDisplay: (json['toll_delta_display'] as String?) ?? 'No toll change',
        autoAcceptSeconds: (json['auto_accept_seconds'] as num?)?.toInt() ?? 0,
        proposedRoute: CandidateRoute.fromJson(json['proposed_route'] as Map<String, dynamic>),
      );
}

@immutable
class VoiceIntentResult {
  const VoiceIntentResult({
    required this.intent,
    required this.confidence,
    this.hazardCategory,
    this.subtype,
    this.severity = HazardSeverity.medium,
    this.direction = 'ahead',
    this.laneHint,
    this.roadHint,
    required this.confirmationSpeech,
    this.matchedTerms = const <String>[],
    required this.normalizedTranscript,
  });

  final String intent;
  final double confidence;
  final HazardCategory? hazardCategory;
  final String? subtype;
  final HazardSeverity severity;
  final String direction;
  final String? laneHint;
  final String? roadHint;
  final String confirmationSpeech;
  final List<String> matchedTerms;
  final String normalizedTranscript;

  factory VoiceIntentResult.fromJson(Map<String, dynamic> json) => VoiceIntentResult(
        intent: json['intent'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        hazardCategory: json['hazard_category'] != null
            ? HazardCategory.fromWire(json['hazard_category'] as String)
            : null,
        subtype: json['subtype'] as String?,
        severity: HazardSeverity.fromWire((json['severity'] as String?) ?? 'medium'),
        direction: (json['direction'] as String?) ?? 'ahead',
        laneHint: json['lane_hint'] as String?,
        roadHint: json['road_hint'] as String?,
        confirmationSpeech: json['confirmation_speech'] as String,
        matchedTerms: (json['matched_terms'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e as String)
            .toList(),
        normalizedTranscript: (json['normalized_transcript'] as String?) ?? '',
      );
}
