import 'package:meta/meta.dart';
import 'common.dart';
import 'tolls.dart';

@immutable
class PoiItem {
  const PoiItem({
    required this.id,
    required this.name,
    required this.category,
    this.subcategory,
    this.brand,
    this.countryCode,
    required this.coordinate,
    this.distanceMeters,
    this.evMetadata,
    this.openingHours,
  });

  final int id;
  final String name;
  final String category;
  final String? subcategory;
  final String? brand;
  final String? countryCode;
  final Coordinate coordinate;
  final double? distanceMeters;
  final Map<String, dynamic>? evMetadata;
  final String? openingHours;

  factory PoiItem.fromJson(Map<String, dynamic> json) => PoiItem(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        category: json['category'] as String,
        subcategory: json['subcategory'] as String?,
        brand: json['brand'] as String?,
        countryCode: (json['country_code'] as String?)?.trim(),
        coordinate: Coordinate.fromJson(json['coordinate'] as Map<String, dynamic>),
        distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
        evMetadata: json['ev_metadata'] as Map<String, dynamic>?,
        openingHours: json['opening_hours'] as String?,
      );
}

@immutable
class PoiBBoxResponse {
  const PoiBBoxResponse({
    required this.source,
    required this.queryMs,
    required this.count,
    required this.items,
  });

  final String source;
  final double queryMs;
  final int count;
  final List<PoiItem> items;

  factory PoiBBoxResponse.fromJson(Map<String, dynamic> json) => PoiBBoxResponse(
        source: json['source'] as String,
        queryMs: (json['query_ms'] as num).toDouble(),
        count: (json['count'] as num).toInt(),
        items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => PoiItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class ApproachingSpeedZone {
  const ApproachingSpeedZone({
    required this.id,
    required this.zoneType,
    this.roadName,
    required this.limitKmh,
    required this.distanceMeters,
    required this.coordinate,
  });

  final int id;
  final String zoneType;
  final String? roadName;
  final int limitKmh;
  final double distanceMeters;
  final Coordinate coordinate;

  factory ApproachingSpeedZone.fromJson(Map<String, dynamic> json) => ApproachingSpeedZone(
        id: (json['id'] as num).toInt(),
        zoneType: json['zone_type'] as String,
        roadName: json['road_name'] as String?,
        limitKmh: (json['limit_kmh'] as num).toInt(),
        distanceMeters: (json['distance_meters'] as num).toDouble(),
        coordinate: Coordinate.fromJson(json['coordinate'] as Map<String, dynamic>),
      );
}

@immutable
class ApproachingGantry {
  const ApproachingGantry({
    required this.gantryId,
    required this.name,
    required this.corridorId,
    required this.systemType,
    required this.distanceMeters,
    required this.acceptedPayments,
    this.laneLayout = const <TollLaneGuidance>[],
    required this.coordinate,
  });

  final String gantryId;
  final String name;
  final String corridorId;
  final String systemType;
  final double distanceMeters;
  final List<PaymentMethod> acceptedPayments;
  final List<TollLaneGuidance> laneLayout;
  final Coordinate coordinate;

  factory ApproachingGantry.fromJson(Map<String, dynamic> json) => ApproachingGantry(
        gantryId: json['gantry_id'] as String,
        name: json['name'] as String,
        corridorId: json['corridor_id'] as String,
        systemType: json['system_type'] as String,
        distanceMeters: (json['distance_meters'] as num).toDouble(),
        acceptedPayments: (json['accepted_payments'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => PaymentMethod.fromWire(e as String))
            .toList(),
        laneLayout: (json['lane_layout'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => TollLaneGuidance.fromJson(e as Map<String, dynamic>))
            .toList(),
        coordinate: Coordinate.fromJson(json['coordinate'] as Map<String, dynamic>),
      );
}

@immutable
class RoadContextResponse {
  const RoadContextResponse({
    required this.coordinate,
    this.country,
    this.roadName,
    this.roadRef,
    this.highwayClass,
    this.speedLimitKmh,
    this.speedLimitSource,
    this.lanesTotal,
    this.turnLanes = const <String>[],
    this.isToll = false,
    this.isBridge = false,
    this.isTunnel = false,
    this.approachingSpeedZones = const <ApproachingSpeedZone>[],
    this.approachingGantries = const <ApproachingGantry>[],
  });

  final Coordinate coordinate;
  final CountryContext? country;
  final String? roadName;
  final String? roadRef;
  final String? highwayClass;
  final int? speedLimitKmh;
  final String? speedLimitSource;
  final int? lanesTotal;
  final List<String> turnLanes;
  final bool isToll;
  final bool isBridge;
  final bool isTunnel;
  final List<ApproachingSpeedZone> approachingSpeedZones;
  final List<ApproachingGantry> approachingGantries;

  factory RoadContextResponse.fromJson(Map<String, dynamic> json) => RoadContextResponse(
        coordinate: Coordinate.fromJson(json['coordinate'] as Map<String, dynamic>),
        country: json['country'] != null
            ? CountryContext.fromJson(json['country'] as Map<String, dynamic>)
            : null,
        roadName: json['road_name'] as String?,
        roadRef: json['road_ref'] as String?,
        highwayClass: json['highway_class'] as String?,
        speedLimitKmh: (json['speed_limit_kmh'] as num?)?.toInt(),
        speedLimitSource: json['speed_limit_source'] as String?,
        lanesTotal: (json['lanes_total'] as num?)?.toInt(),
        turnLanes: (json['turn_lanes'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e as String)
            .toList(),
        isToll: (json['is_toll'] as bool?) ?? false,
        isBridge: (json['is_bridge'] as bool?) ?? false,
        isTunnel: (json['is_tunnel'] as bool?) ?? false,
        approachingSpeedZones:
            (json['approaching_speed_zones'] as List<dynamic>? ?? const <dynamic>[])
                .map((e) => ApproachingSpeedZone.fromJson(e as Map<String, dynamic>))
                .toList(),
        approachingGantries:
            (json['approaching_gantries'] as List<dynamic>? ?? const <dynamic>[])
                .map((e) => ApproachingGantry.fromJson(e as Map<String, dynamic>))
                .toList(),
      );
}
