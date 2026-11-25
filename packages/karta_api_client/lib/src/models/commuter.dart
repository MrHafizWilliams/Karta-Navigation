import 'package:meta/meta.dart';
import 'common.dart';

@immutable
class CalendarEventItem {
  const CalendarEventItem({
    required this.id,
    required this.title,
    required this.provider,
    this.locationText,
    this.destination,
    this.countryCode,
    required this.startsAt,
    this.endsAt,
    this.parkingBufferSec = 600,
  });

  final String id;
  final String title;
  final String provider;
  final String? locationText;
  final Coordinate? destination;
  final String? countryCode;
  final DateTime startsAt;
  final DateTime? endsAt;
  final int parkingBufferSec;

  factory CalendarEventItem.fromJson(Map<String, dynamic> json) => CalendarEventItem(
        id: json['id'] as String,
        title: json['title'] as String,
        provider: (json['provider'] as String?) ?? 'manual',
        locationText: json['location_text'] as String?,
        destination: json['destination'] != null
            ? Coordinate.fromJson(json['destination'] as Map<String, dynamic>)
            : null,
        countryCode: json['country_code'] as String?,
        startsAt: DateTime.parse(json['starts_at'] as String),
        endsAt: json['ends_at'] != null ? DateTime.parse(json['ends_at'] as String) : null,
        parkingBufferSec: (json['parking_buffer_sec'] as num?)?.toInt() ?? 600,
      );
}

@immutable
class TimeToLeaveEvaluation {
  const TimeToLeaveEvaluation({
    required this.event,
    required this.baselineDurationSeconds,
    required this.liveTrafficDurationSeconds,
    required this.trafficDelaySeconds,
    required this.distanceKm,
    required this.estimatedTollDisplay,
    required this.recommendedDepartureAt,
    required this.minutesUntilDeparture,
    required this.urgencyLevel,
    required this.advisoryMessage,
  });

  final CalendarEventItem event;
  final double baselineDurationSeconds;
  final double liveTrafficDurationSeconds;
  final double trafficDelaySeconds;
  final double distanceKm;
  final String estimatedTollDisplay;
  final DateTime recommendedDepartureAt;
  final int minutesUntilDeparture;
  final String urgencyLevel;
  final String advisoryMessage;

  factory TimeToLeaveEvaluation.fromJson(Map<String, dynamic> json) => TimeToLeaveEvaluation(
        event: CalendarEventItem.fromJson(json['event'] as Map<String, dynamic>),
        baselineDurationSeconds: (json['baseline_duration_seconds'] as num).toDouble(),
        liveTrafficDurationSeconds: (json['live_traffic_duration_seconds'] as num).toDouble(),
        trafficDelaySeconds: (json['traffic_delay_seconds'] as num).toDouble(),
        distanceKm: (json['distance_km'] as num).toDouble(),
        estimatedTollDisplay: (json['estimated_toll_display'] as String?) ?? 'Free',
        recommendedDepartureAt: DateTime.parse(json['recommended_departure_at'] as String),
        minutesUntilDeparture: (json['minutes_until_departure'] as num).toInt(),
        urgencyLevel: (json['urgency_level'] as String?) ?? 'upcoming',
        advisoryMessage: (json['advisory_message'] as String?) ?? '',
      );
}

@immutable
class EvaluateDeparturesResponse {
  const EvaluateDeparturesResponse({
    required this.evaluatedAt,
    required this.origin,
    required this.count,
    required this.evaluations,
  });

  final DateTime evaluatedAt;
  final Coordinate origin;
  final int count;
  final List<TimeToLeaveEvaluation> evaluations;

  factory EvaluateDeparturesResponse.fromJson(Map<String, dynamic> json) =>
      EvaluateDeparturesResponse(
        evaluatedAt: DateTime.parse(json['evaluated_at'] as String),
        origin: Coordinate.fromJson(json['origin'] as Map<String, dynamic>),
        count: (json['count'] as num).toInt(),
        evaluations: (json['evaluations'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => TimeToLeaveEvaluation.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class CarpoolOfferPublic {
  const CarpoolOfferPublic({
    required this.id,
    required this.driverAlias,
    this.verifiedBadge,
    required this.countryCode,
    required this.originZoneCenter,
    required this.originLandmarkName,
    required this.destZoneCenter,
    required this.destLandmarkName,
    this.privacyRadiusM = 500,
    required this.routePolyline6,
    required this.routeDistanceKm,
    required this.departureAt,
    required this.flexibilityMinutes,
    required this.seatsTotal,
    required this.seatsAvailable,
    required this.estimatedSplitMinor,
    required this.estimatedSplitFormatted,
    required this.currencyCode,
    this.notes,
    this.status = 'active',
  });

  final String id;
  final String driverAlias;
  final String? verifiedBadge;
  final String countryCode;
  final Coordinate originZoneCenter;
  final String originLandmarkName;
  final Coordinate destZoneCenter;
  final String destLandmarkName;
  final int privacyRadiusM;
  final String routePolyline6;
  final double routeDistanceKm;
  final DateTime departureAt;
  final int flexibilityMinutes;
  final int seatsTotal;
  final int seatsAvailable;
  final int estimatedSplitMinor;
  final String estimatedSplitFormatted;
  final String currencyCode;
  final String? notes;
  final String status;

  factory CarpoolOfferPublic.fromJson(Map<String, dynamic> json) => CarpoolOfferPublic(
        id: json['id'] as String,
        driverAlias: json['driver_alias'] as String,
        verifiedBadge: json['verified_badge'] as String?,
        countryCode: (json['country_code'] as String?) ?? 'MY',
        originZoneCenter: Coordinate.fromJson(json['origin_zone_center'] as Map<String, dynamic>),
        originLandmarkName: json['origin_landmark_name'] as String,
        destZoneCenter: Coordinate.fromJson(json['dest_zone_center'] as Map<String, dynamic>),
        destLandmarkName: json['dest_landmark_name'] as String,
        privacyRadiusM: (json['privacy_radius_m'] as num?)?.toInt() ?? 500,
        routePolyline6: (json['route_polyline6'] as String?) ?? '',
        routeDistanceKm: (json['route_distance_km'] as num?)?.toDouble() ?? 0.0,
        departureAt: DateTime.parse(json['departure_at'] as String),
        flexibilityMinutes: (json['flexibility_minutes'] as num?)?.toInt() ?? 20,
        seatsTotal: (json['seats_total'] as num).toInt(),
        seatsAvailable: (json['seats_available'] as num).toInt(),
        estimatedSplitMinor: (json['estimated_split_minor'] as num).toInt(),
        estimatedSplitFormatted: json['estimated_split_formatted'] as String,
        currencyCode: json['currency_code'] as String,
        notes: json['notes'] as String?,
        status: (json['status'] as String?) ?? 'active',
      );
}

@immutable
class CarpoolMatchCandidate {
  const CarpoolMatchCandidate({
    required this.offer,
    required this.pickupZoneCenter,
    required this.pickupLandmarkName,
    required this.dropoffZoneCenter,
    required this.dropoffLandmarkName,
    required this.overlapPct,
    required this.detourMeters,
    required this.splitCostMinor,
    required this.splitCostFormatted,
    required this.currencyCode,
  });

  final CarpoolOfferPublic offer;
  final Coordinate pickupZoneCenter;
  final String pickupLandmarkName;
  final Coordinate dropoffZoneCenter;
  final String dropoffLandmarkName;
  final double overlapPct;
  final double detourMeters;
  final int splitCostMinor;
  final String splitCostFormatted;
  final String currencyCode;

  factory CarpoolMatchCandidate.fromJson(Map<String, dynamic> json) => CarpoolMatchCandidate(
        offer: CarpoolOfferPublic.fromJson(json['offer'] as Map<String, dynamic>),
        pickupZoneCenter: Coordinate.fromJson(json['pickup_zone_center'] as Map<String, dynamic>),
        pickupLandmarkName: json['pickup_landmark_name'] as String,
        dropoffZoneCenter: Coordinate.fromJson(json['dropoff_zone_center'] as Map<String, dynamic>),
        dropoffLandmarkName: json['dropoff_landmark_name'] as String,
        overlapPct: (json['overlap_pct'] as num).toDouble(),
        detourMeters: (json['detour_meters'] as num).toDouble(),
        splitCostMinor: (json['split_cost_minor'] as num).toInt(),
        splitCostFormatted: json['split_cost_formatted'] as String,
        currencyCode: json['currency_code'] as String,
      );
}

@immutable
class CarpoolMatchRecord {
  const CarpoolMatchRecord({
    required this.id,
    required this.offerId,
    required this.driverAlias,
    required this.riderAlias,
    required this.pickupZoneCenter,
    required this.pickupLandmarkName,
    required this.dropoffZoneCenter,
    required this.dropoffLandmarkName,
    required this.overlapPct,
    required this.detourMeters,
    required this.splitCostMinor,
    required this.splitCostFormatted,
    required this.currencyCode,
    required this.status,
    this.rendezvousNote,
    this.privacyShieldActive = true,
  });

  final String id;
  final String offerId;
  final String driverAlias;
  final String riderAlias;
  final Coordinate pickupZoneCenter;
  final String pickupLandmarkName;
  final Coordinate dropoffZoneCenter;
  final String dropoffLandmarkName;
  final double overlapPct;
  final double detourMeters;
  final int splitCostMinor;
  final String splitCostFormatted;
  final String currencyCode;
  final String status;
  final String? rendezvousNote;
  final bool privacyShieldActive;

  factory CarpoolMatchRecord.fromJson(Map<String, dynamic> json) => CarpoolMatchRecord(
        id: json['id'] as String,
        offerId: json['offer_id'] as String,
        driverAlias: json['driver_alias'] as String,
        riderAlias: json['rider_alias'] as String,
        pickupZoneCenter: Coordinate.fromJson(json['pickup_zone_center'] as Map<String, dynamic>),
        pickupLandmarkName: json['pickup_landmark_name'] as String,
        dropoffZoneCenter: Coordinate.fromJson(json['dropoff_zone_center'] as Map<String, dynamic>),
        dropoffLandmarkName: json['dropoff_landmark_name'] as String,
        overlapPct: (json['overlap_pct'] as num).toDouble(),
        detourMeters: (json['detour_meters'] as num).toDouble(),
        splitCostMinor: (json['split_cost_minor'] as num).toInt(),
        splitCostFormatted: json['split_cost_formatted'] as String,
        currencyCode: json['currency_code'] as String,
        status: json['status'] as String,
        rendezvousNote: json['rendezvous_note'] as String?,
        privacyShieldActive: (json['privacy_shield_active'] as bool?) ?? true,
      );
}

@immutable
class CustomVoiceClipMeta {
  const CustomVoiceClipMeta({
    required this.cueKey,
    required this.mimeType,
    required this.durationMs,
    this.audioBase64,
    required this.updatedAt,
  });

  final String cueKey;
  final String mimeType;
  final int durationMs;
  final String? audioBase64;
  final DateTime updatedAt;

  factory CustomVoiceClipMeta.fromJson(Map<String, dynamic> json) => CustomVoiceClipMeta(
        cueKey: json['cue_key'] as String,
        mimeType: (json['mime_type'] as String?) ?? 'audio/webm',
        durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
        audioBase64: json['audio_base64'] as String?,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

@immutable
class CustomVoicePackRecord {
  const CustomVoicePackRecord({
    required this.id,
    required this.ownerToken,
    required this.name,
    required this.locale,
    required this.baseTtsVoice,
    this.recordedCues = const <String>[],
    this.totalCueSlots = 12,
    this.clips = const <String, CustomVoiceClipMeta>{},
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String ownerToken;
  final String name;
  final String locale;
  final String baseTtsVoice;
  final List<String> recordedCues;
  final int totalCueSlots;
  final Map<String, CustomVoiceClipMeta> clips;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CustomVoicePackRecord.fromJson(Map<String, dynamic> json) {
    final rawClips = json['clips'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    return CustomVoicePackRecord(
      id: json['id'] as String,
      ownerToken: json['owner_token'] as String,
      name: json['name'] as String,
      locale: (json['locale'] as String?) ?? 'en-MY',
      baseTtsVoice: (json['base_tts_voice'] as String?) ?? 'karta_studio_en',
      recordedCues: (json['recorded_cues'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e as String)
          .toList(),
      totalCueSlots: (json['total_cue_slots'] as num?)?.toInt() ?? 12,
      clips: rawClips.map(
        (k, v) => MapEntry(k, CustomVoiceClipMeta.fromJson(v as Map<String, dynamic>)),
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
