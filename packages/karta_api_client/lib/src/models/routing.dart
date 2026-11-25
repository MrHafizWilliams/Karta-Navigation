import 'package:meta/meta.dart';
import 'common.dart';
import 'hazards.dart';
import 'tolls.dart';

enum RoutingProfileId {
  driveFastest('drive_fastest', 'Fastest'),
  driveAvoidTolls('drive_avoid_tolls', 'Avoid Tolls'),
  driveNoHighways('drive_no_highways', 'No Highways'),
  driveMotorcycle('drive_motorcycle', 'Motorcycle'),
  walk('walk', 'Walk'),
  cycle('cycle', 'Cycle'),
  transit('transit', 'Transit');

  const RoutingProfileId(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static RoutingProfileId fromWire(String raw) {
    for (final p in RoutingProfileId.values) {
      if (p.wireValue == raw) return p;
    }
    return RoutingProfileId.driveFastest;
  }
}

@immutable
class RouteRequest {
  const RouteRequest({
    required this.origin,
    required this.destination,
    this.waypoints = const <Coordinate>[],
    this.profile = RoutingProfileId.driveFastest,
    this.vehicleProfile = VehicleProfile.car,
    this.vehicleRegistrationCountry = 'MY',
    this.paymentMethods = const <PaymentMethod>[
      PaymentMethod.rfid,
      PaymentMethod.tngCard,
      PaymentMethod.smartTag,
      PaymentMethod.openPaymentCard,
      PaymentMethod.erpIu,
      PaymentMethod.erp2Obu,
    ],
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.avoidFerries = false,
    this.alternates = 2,
    this.includeTollFreeComparison = true,
    this.departureTime,
    this.arriveBy,
    this.language = 'en-US',
  });

  final Coordinate origin;
  final Coordinate destination;
  final List<Coordinate> waypoints;
  final RoutingProfileId profile;
  final VehicleProfile vehicleProfile;
  final String vehicleRegistrationCountry;
  final List<PaymentMethod> paymentMethods;
  final bool avoidTolls;
  final bool avoidHighways;
  final bool avoidFerries;
  final int alternates;
  final bool includeTollFreeComparison;
  final DateTime? departureTime;
  final DateTime? arriveBy;
  final String language;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
        'profile': profile.wireValue,
        'vehicle_profile': vehicleProfile.wireValue,
        'vehicle_registration_country': vehicleRegistrationCountry,
        'payment_methods': paymentMethods.map((m) => m.wireValue).toList(),
        'avoid_tolls': avoidTolls,
        'avoid_highways': avoidHighways,
        'avoid_ferries': avoidFerries,
        'alternates': alternates,
        'include_toll_free_comparison': includeTollFreeComparison,
        if (departureTime != null) 'departure_time': departureTime!.toIso8601String(),
        if (arriveBy != null) 'arrive_by': arriveBy!.toIso8601String(),
        'language': language,
      };
}

@immutable
class RouteManeuver {
  const RouteManeuver({
    required this.type,
    required this.instruction,
    this.verbalPreTransitionInstruction,
    this.streetNames = const <String>[],
    required this.distanceKm,
    required this.timeSeconds,
    required this.beginShapeIndex,
    required this.endShapeIndex,
    this.toll = false,
    this.highway = false,
    this.travelMode = 'drive',
    this.transitInfo,
  });

  final int type;
  final String instruction;
  final String? verbalPreTransitionInstruction;
  final List<String> streetNames;
  final double distanceKm;
  final double timeSeconds;
  final int beginShapeIndex;
  final int endShapeIndex;
  final bool toll;
  final bool highway;
  final String travelMode;
  final Map<String, dynamic>? transitInfo;

  factory RouteManeuver.fromJson(Map<String, dynamic> json) => RouteManeuver(
        type: (json['type'] as num).toInt(),
        instruction: (json['instruction'] as String?) ?? '',
        verbalPreTransitionInstruction: json['verbal_pre_transition_instruction'] as String?,
        streetNames: (json['street_names'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e as String)
            .toList(),
        distanceKm: (json['distance_km'] as num).toDouble(),
        timeSeconds: (json['time_seconds'] as num).toDouble(),
        beginShapeIndex: (json['begin_shape_index'] as num).toInt(),
        endShapeIndex: (json['end_shape_index'] as num).toInt(),
        toll: (json['toll'] as bool?) ?? false,
        highway: (json['highway'] as bool?) ?? false,
        travelMode: (json['travel_mode'] as String?) ?? 'drive',
        transitInfo: json['transit_info'] as Map<String, dynamic>?,
      );
}

@immutable
class RouteLeg {
  const RouteLeg({
    required this.distanceKm,
    required this.durationSeconds,
    required this.shapePolyline6,
    required this.maneuvers,
  });

  final double distanceKm;
  final double durationSeconds;
  final String shapePolyline6;
  final List<RouteManeuver> maneuvers;

  factory RouteLeg.fromJson(Map<String, dynamic> json) => RouteLeg(
        distanceKm: (json['distance_km'] as num).toDouble(),
        durationSeconds: (json['duration_seconds'] as num).toDouble(),
        shapePolyline6: (json['shape_polyline6'] as String?) ?? '',
        maneuvers: (json['maneuvers'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => RouteManeuver.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class CandidateRoute {
  const CandidateRoute({
    required this.routeIndex,
    required this.profileUsed,
    required this.summaryLabel,
    this.uxPrimaryTag = '',
    this.uxBadgeKind = 'balanced',
    this.uxHighlights = const <String>[],
    this.turnCount = 0,
    this.primaryCorridorName,
    this.etaDeltaSeconds = 0.0,
    required this.distanceKm,
    required this.durationSeconds,
    this.baselineDurationSeconds,
    this.liveTrafficDelaySeconds = 0.0,
    required this.hasTollRoads,
    required this.hasHighways,
    this.countriesCrossed = const <String>[],
    required this.legs,
    required this.tolls,
    this.congestionSegments = const <CongestionSegment>[],
    this.activeHazardsOnRoute = const <HazardRecord>[],
  });

  final int routeIndex;
  final String profileUsed;
  final String summaryLabel;
  final String uxPrimaryTag;
  final String uxBadgeKind;
  final List<String> uxHighlights;
  final int turnCount;
  final String? primaryCorridorName;
  final double etaDeltaSeconds;
  final double distanceKm;
  final double durationSeconds;
  final double? baselineDurationSeconds;
  final double liveTrafficDelaySeconds;
  final bool hasTollRoads;
  final bool hasHighways;
  final List<String> countriesCrossed;
  final List<RouteLeg> legs;
  final TollSummary tolls;
  final List<CongestionSegment> congestionSegments;
  final List<HazardRecord> activeHazardsOnRoute;

  String get displayTag => uxPrimaryTag.isNotEmpty ? uxPrimaryTag : summaryLabel;

  factory CandidateRoute.fromJson(Map<String, dynamic> json) => CandidateRoute(
        routeIndex: (json['route_index'] as num).toInt(),
        profileUsed: json['profile_used'] as String,
        summaryLabel: json['summary_label'] as String,
        uxPrimaryTag: (json['ux_primary_tag'] as String?) ?? '',
        uxBadgeKind: (json['ux_badge_kind'] as String?) ?? 'balanced',
        uxHighlights: (json['ux_highlights'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e as String)
            .toList(),
        turnCount: (json['turn_count'] as num?)?.toInt() ?? 0,
        primaryCorridorName: json['primary_corridor_name'] as String?,
        etaDeltaSeconds: (json['eta_delta_seconds'] as num?)?.toDouble() ?? 0.0,
        distanceKm: (json['distance_km'] as num).toDouble(),
        durationSeconds: (json['duration_seconds'] as num).toDouble(),
        baselineDurationSeconds: (json['baseline_duration_seconds'] as num?)?.toDouble(),
        liveTrafficDelaySeconds: (json['live_traffic_delay_seconds'] as num?)?.toDouble() ?? 0.0,
        hasTollRoads: (json['has_toll_roads'] as bool?) ?? false,
        hasHighways: (json['has_highways'] as bool?) ?? false,
        countriesCrossed: (json['countries_crossed'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => (e as String).trim())
            .toList(),
        legs: (json['legs'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => RouteLeg.fromJson(e as Map<String, dynamic>))
            .toList(),
        tolls: TollSummary.fromJson(json['tolls'] as Map<String, dynamic>),
        congestionSegments: (json['congestion_segments'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => CongestionSegment.fromJson(e as Map<String, dynamic>))
            .toList(),
        activeHazardsOnRoute: (json['active_hazards_on_route'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => HazardRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class PrefetchTileCoord {
  const PrefetchTileCoord({
    required this.z,
    required this.x,
    required this.y,
    this.priority = 1,
    this.reason = 'corridor',
    this.tileUrl,
  });

  final int z;
  final int x;
  final int y;
  final int priority;
  final String reason;
  final String? tileUrl;

  factory PrefetchTileCoord.fromJson(Map<String, dynamic> json) => PrefetchTileCoord(
        z: (json['z'] as num).toInt(),
        x: (json['x'] as num).toInt(),
        y: (json['y'] as num).toInt(),
        priority: (json['priority'] as num?)?.toInt() ?? 1,
        reason: (json['reason'] as String?) ?? 'corridor',
        tileUrl: json['tile_url'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'z': z,
        'x': x,
        'y': y,
        'priority': priority,
        'reason': reason,
        if (tileUrl != null) 'tile_url': tileUrl,
      };
}

@immutable
class TilePrefetchRequest {
  const TilePrefetchRequest({
    required this.polyline6,
    this.currentPosition,
    this.currentSpeedKmh = 80.0,
    this.maneuverCoordinates = const <Coordinate>[],
    this.zoomLevels,
    this.maxTiles = 96,
    this.regionArchive = 'my-sg-bn-full',
  });

  final String polyline6;
  final Coordinate? currentPosition;
  final double currentSpeedKmh;
  final List<Coordinate> maneuverCoordinates;
  final List<int>? zoomLevels;
  final int maxTiles;
  final String regionArchive;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'polyline6': polyline6,
        if (currentPosition != null) 'current_position': currentPosition!.toJson(),
        'current_speed_kmh': currentSpeedKmh,
        'maneuver_coordinates': maneuverCoordinates.map((c) => c.toJson()).toList(),
        if (zoomLevels != null) 'zoom_levels': zoomLevels,
        'max_tiles': maxTiles,
        'region_archive': regionArchive,
      };
}

@immutable
class TilePrefetchResponse {
  const TilePrefetchResponse({
    required this.lookaheadKm,
    required this.zoomLevels,
    required this.tileCount,
    required this.tiles,
    this.cached = false,
    this.planningMs = 0.0,
  });

  final double lookaheadKm;
  final List<int> zoomLevels;
  final int tileCount;
  final List<PrefetchTileCoord> tiles;
  final bool cached;
  final double planningMs;

  factory TilePrefetchResponse.fromJson(Map<String, dynamic> json) => TilePrefetchResponse(
        lookaheadKm: (json['lookahead_km'] as num).toDouble(),
        zoomLevels: (json['zoom_levels'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => (e as num).toInt())
            .toList(),
        tileCount: (json['tile_count'] as num).toInt(),
        tiles: (json['tiles'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => PrefetchTileCoord.fromJson(e as Map<String, dynamic>))
            .toList(),
        cached: (json['cached'] as bool?) ?? false,
        planningMs: (json['planning_ms'] as num?)?.toDouble() ?? 0.0,
      );
}

@immutable
class TollSavingsComparison {
  const TollSavingsComparison({
    required this.tollFreeRouteIndex,
    required this.extraDurationSeconds,
    required this.extraDistanceKm,
    required this.savingsByCurrency,
    required this.summaryText,
  });

  final int tollFreeRouteIndex;
  final double extraDurationSeconds;
  final double extraDistanceKm;
  final List<CurrencyAmount> savingsByCurrency;
  final String summaryText;

  factory TollSavingsComparison.fromJson(Map<String, dynamic> json) => TollSavingsComparison(
        tollFreeRouteIndex: (json['toll_free_route_index'] as num).toInt(),
        extraDurationSeconds: (json['extra_duration_seconds'] as num).toDouble(),
        extraDistanceKm: (json['extra_distance_km'] as num).toDouble(),
        savingsByCurrency: (json['savings_by_currency'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => CurrencyAmount.fromJson(e as Map<String, dynamic>))
            .toList(),
        summaryText: json['summary_text'] as String,
      );
}

@immutable
class RouteResponse {
  const RouteResponse({
    this.originCountry,
    this.destinationCountry,
    required this.departureTime,
    required this.routes,
    this.tollFreeComparison,
    this.cached = false,
    this.trafficEpoch = 0,
    this.exclusionsApplied = 0,
  });

  final CountryContext? originCountry;
  final CountryContext? destinationCountry;
  final DateTime departureTime;
  final List<CandidateRoute> routes;
  final TollSavingsComparison? tollFreeComparison;
  final bool cached;
  final int trafficEpoch;
  final int exclusionsApplied;

  factory RouteResponse.fromJson(Map<String, dynamic> json) => RouteResponse(
        originCountry: json['origin_country'] != null
            ? CountryContext.fromJson(json['origin_country'] as Map<String, dynamic>)
            : null,
        destinationCountry: json['destination_country'] != null
            ? CountryContext.fromJson(json['destination_country'] as Map<String, dynamic>)
            : null,
        departureTime: DateTime.parse(json['departure_time'] as String),
        routes: (json['routes'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => CandidateRoute.fromJson(e as Map<String, dynamic>))
            .toList(),
        tollFreeComparison: json['toll_free_comparison'] != null
            ? TollSavingsComparison.fromJson(
                json['toll_free_comparison'] as Map<String, dynamic>,
              )
            : null,
        cached: (json['cached'] as bool?) ?? false,
        trafficEpoch: (json['traffic_epoch'] as num?)?.toInt() ?? 0,
        exclusionsApplied: (json['exclusions_applied'] as num?)?.toInt() ?? 0,
      );
}
