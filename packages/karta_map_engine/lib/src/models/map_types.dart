import 'package:flutter/foundation.dart';
import 'package:karta_api_client/karta_api_client.dart';

/// Selectable 2D navigation arrow / marker style rendered cleanly on the map surface.
enum KartaVehicleAvatar {
  kartaPin3d(
    id: 'karta_pin_3d',
    name: 'Karta 2D Arrow',
    subtitle: 'Crisp Google/Waze-style circular teal navigation chevron',
  ),
  stealthSedan(
    id: 'stealth_sedan',
    name: 'Classic Blue Arrow',
    subtitle: 'Clean vivid navigation pointer with white ring',
  ),
  gtCoupe(
    id: 'gt_coupe',
    name: 'Sport Chevron',
    subtitle: 'Sharp high-contrast directional dart for expressways',
  ),
  evSuv(
    id: 'ev_suv',
    name: 'Emerald Compass',
    subtitle: 'High-visibility eco teal circular heading puck',
  ),
  touringMoto(
    id: 'touring_moto',
    name: 'Compact Moto Dart',
    subtitle: 'Slim agile 2D directional needle for tight city lanes',
  );

  const KartaVehicleAvatar({
    required this.id,
    required this.name,
    required this.subtitle,
  });

  final String id;
  final String name;
  final String subtitle;
}

@immutable
class KartaVehicleCustomization {
  const KartaVehicleCustomization({
    this.avatar = KartaVehicleAvatar.kartaPin3d,
    this.accentHex = '#5B9A94',
    this.showHaloRing = true,
    this.scale = 1.0,
  });

  final KartaVehicleAvatar avatar;
  final String accentHex;
  final bool showHaloRing;
  final double scale;

  KartaVehicleCustomization copyWith({
    KartaVehicleAvatar? avatar,
    String? accentHex,
    bool? showHaloRing,
    double? scale,
  }) =>
      KartaVehicleCustomization(
        avatar: avatar ?? this.avatar,
        accentHex: accentHex ?? this.accentHex,
        showHaloRing: showHaloRing ?? this.showHaloRing,
        scale: scale ?? this.scale,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'avatar': avatar.id,
        'accentHex': accentHex,
        'showHaloRing': showHaloRing,
        'scale': scale,
      };
}

@immutable
class KartaMapStopPin {
  const KartaMapStopPin({
    required this.label,
    required this.role,
    required this.coordinate,
  });

  final String label;

  /// 'origin', 'waypoint', or 'destination'
  final String role;
  final Coordinate coordinate;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'role': role,
        'lat': coordinate.lat,
        'lon': coordinate.lon,
      };
}

@immutable
class StreetLookAroundTarget {
  const StreetLookAroundTarget({
    required this.coordinate,
    this.headingDeg = 0,
    required this.title,
    this.subtitle,
  });

  final Coordinate coordinate;
  final double headingDeg;
  final String title;
  final String? subtitle;
}

@immutable
class CarpoolMapOverlay {
  const CarpoolMapOverlay({
    required this.corridorPoints,
    required this.originZoneCenter,
    required this.destZoneCenter,
    this.privacyRadiusMeters = 500,
    this.originLabel = '500m Pickup Zone',
    this.destLabel = '500m Dropoff Zone',
  });

  final List<Coordinate> corridorPoints;
  final Coordinate originZoneCenter;
  final Coordinate destZoneCenter;
  final int privacyRadiusMeters;
  final String originLabel;
  final String destLabel;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'corridor': corridorPoints.map((c) => <double>[c.lon, c.lat]).toList(),
        'originZone': <String, dynamic>{
          'lat': originZoneCenter.lat,
          'lon': originZoneCenter.lon,
          'label': originLabel,
        },
        'destZone': <String, dynamic>{
          'lat': destZoneCenter.lat,
          'lon': destZoneCenter.lon,
          'label': destLabel,
        },
        'privacyRadiusMeters': privacyRadiusMeters,
      };
}

@immutable
class KartaViewportBounds {
  const KartaViewportBounds({
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
    required this.zoom,
  });

  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;
  final double zoom;
}

/// Interactive floating ETA / delta callout pill anchored on a map route
/// (e.g., "Fastest · 3h 33m" or "+26 min slower") just like Google Maps / Waze.
@immutable
class KartaMapRouteCallout {
  const KartaMapRouteCallout({
    required this.routeIndex,
    required this.label,
    this.sublabel,
    required this.isSelected,
    required this.coordinate,
  });

  final int routeIndex;
  final String label;
  final String? sublabel;
  final bool isSelected;
  final Coordinate coordinate;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'routeIndex': routeIndex,
        'label': label,
        'sublabel': sublabel ?? '',
        'isSelected': isSelected,
        'lat': coordinate.lat,
        'lon': coordinate.lon,
      };
}

/// Road-snapped 2D curved turn direction arrow rendered directly onto the
/// road intersection at an upcoming navigation maneuver.
@immutable
class KartaMapTurnArrow {
  const KartaMapTurnArrow({
    required this.shaftPoints,
    required this.tipCoordinate,
    required this.tipBearingDeg,
    required this.isActive,
    required this.maneuverType,
  });

  final List<Coordinate> shaftPoints;
  final Coordinate tipCoordinate;
  final double tipBearingDeg;
  final bool isActive;
  final int maneuverType;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'shaft': shaftPoints.map((c) => <double>[c.lon, c.lat]).toList(),
        'tipLat': tipCoordinate.lat,
        'tipLon': tipCoordinate.lon,
        'bearingDeg': tipBearingDeg,
        'isActive': isActive,
        'maneuverType': maneuverType,
      };
}

/// User-saved place or landmark pin rendered on the live map.
@immutable
class KartaMapSavedPlacePin {
  const KartaMapSavedPlacePin({
    required this.id,
    required this.name,
    required this.category,
    required this.coordinate,
  });

  final String id;
  final String name;
  final String category;
  final Coordinate coordinate;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'category': category,
        'lat': coordinate.lat,
        'lon': coordinate.lon,
      };
}

/// Curated iconic Southeast Asian landmark, international airport, religious site,
/// or major rail hub rendered interactively on the 3D map.
@immutable
class KartaMapFeaturedPin {
  const KartaMapFeaturedPin({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.kind,
    required this.countryCode,
    required this.coordinate,
    this.iataCode,
    this.minZoom = 8.5,
  });

  final String id;
  final String name;
  final String shortLabel;

  /// One of: `'historic'`, `'modern'`, `'airport'`, `'mosque'`, `'temple'`,
  /// `'church'`, `'rail'`.
  final String kind;
  final String countryCode;
  final Coordinate coordinate;
  final String? iataCode;
  final double minZoom;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'shortLabel': shortLabel,
        'kind': kind,
        'countryCode': countryCode,
        'lat': coordinate.lat,
        'lon': coordinate.lon,
        if (iataCode != null) 'iataCode': iataCode,
        'minZoom': minZoom,
      };
}

/// Payload emitted when a user taps a vector-tile train station, airport,
/// mosque, temple, church, or landmark directly on the OpenMapTiles canvas.
@immutable
class KartaVectorFeatureTap {
  const KartaVectorFeatureTap({
    required this.name,
    required this.featureClass,
    required this.subclass,
    required this.coordinate,
    this.religion,
    this.iata,
  });

  final String name;
  final String featureClass;
  final String subclass;
  final Coordinate coordinate;
  final String? religion;
  final String? iata;
}
