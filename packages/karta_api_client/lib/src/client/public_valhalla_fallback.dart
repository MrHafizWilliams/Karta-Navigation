import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/common.dart';
import '../models/routing.dart';
import '../models/tolls.dart';

/// Real live open-source routing fallback used transparently when the local
/// self-hosted Karta Docker backend (`localhost:8000`) is offline:
/// 1. FOSSGIS Public Valhalla (`https://valhalla1.openstreetmap.de/route`)
/// 2. Project OSRM Public API (`https://router.project-osrm.org/route/v1/...`)
///
/// Both engines compute real OpenStreetMap road-network routes with full
/// polyline6 geometries, turn-by-turn maneuvers, street names, and alternates.
abstract final class PublicValhallaFallback {
  static final Uri _valhallaRouteUri =
      Uri.parse('https://valhalla1.openstreetmap.de/route');
  static final Uri _valhallaStatusUri =
      Uri.parse('https://valhalla1.openstreetmap.de/status');

  static Future<bool> probeAlive(
    http.Client client, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final resp = await client
          .get(_valhallaStatusUri, headers: const <String, String>{'Accept': 'application/json'})
          .timeout(timeout);
      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.bodyBytes.isNotEmpty) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<RouteResponse> computeRoute(
    http.Client client,
    RouteRequest request, {
    Duration timeout = const Duration(seconds: 14),
  }) async {
    try {
      return await _computeViaValhalla(client, request, timeout: timeout);
    } catch (_) {
      return _computeViaOsrm(client, request, timeout: timeout);
    }
  }

  static Future<RouteResponse> _computeViaValhalla(
    http.Client client,
    RouteRequest request, {
    required Duration timeout,
  }) async {
    final locations = <Map<String, dynamic>>[
      <String, dynamic>{'lat': request.origin.lat, 'lon': request.origin.lon},
      for (final wp in request.waypoints)
        <String, dynamic>{'lat': wp.lat, 'lon': wp.lon},
      <String, dynamic>{'lat': request.destination.lat, 'lon': request.destination.lon},
    ];

    final costing = switch (request.profile) {
      RoutingProfileId.driveMotorcycle => 'motorcycle',
      RoutingProfileId.walk => 'pedestrian',
      RoutingProfileId.cycle => 'bicycle',
      _ => 'auto',
    };

    final costingOptions = <String, dynamic>{};
    if (costing == 'auto' || costing == 'motorcycle') {
      costingOptions[costing] = <String, dynamic>{
        if (request.avoidHighways || request.profile == RoutingProfileId.driveNoHighways)
          'use_highways': 0.05,
        if (request.avoidTolls) 'use_tolls': 0.05,
        if (request.avoidFerries) 'use_ferry': 0.05,
      };
    }

    final payload = <String, dynamic>{
      'locations': locations,
      'costing': costing,
      if (costingOptions.isNotEmpty) 'costing_options': costingOptions,
      'alternates': request.alternates.clamp(0, 2),
      'directions_options': <String, dynamic>{
        'units': 'kilometers',
        'language': _valhallaLanguage(request.language),
      },
    };

    final resp = await client
        .post(
          _valhallaRouteUri,
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    if (resp.statusCode < 200 || resp.statusCode >= 300 || resp.bodyBytes.isEmpty) {
      throw StateError('Public Valhalla returned HTTP ${resp.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['trip'] is! Map<String, dynamic>) {
      throw StateError('Unexpected Valhalla JSON payload');
    }

    final trips = <Map<String, dynamic>>[
      decoded['trip'] as Map<String, dynamic>,
      for (final alt in (decoded['alternates'] as List<dynamic>? ?? const <dynamic>[]))
        if (alt is Map<String, dynamic> && alt['trip'] is Map<String, dynamic>)
          alt['trip'] as Map<String, dynamic>,
    ];

    final originCountry = _inferSeaCountry(request.origin);
    final destCountry = _inferSeaCountry(request.destination);
    final crossed = <String>{
      originCountry.isoA2,
      destCountry.isoA2,
    }.toList();

    final baseDuration =
        ((trips.first['summary'] as Map<String, dynamic>?)?['time'] as num?)?.toDouble() ?? 0.0;

    final candidates = <CandidateRoute>[];
    for (var idx = 0; idx < trips.length; idx++) {
      final trip = trips[idx];
      final summary = (trip['summary'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      final rawLegs = (trip['legs'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();

      final legs = <RouteLeg>[];
      var hasHighways = false;
      var hasTolls = false;
      var turnCount = 0;
      String? primaryCorridor;
      double longestCorridorKm = -1.0;

      for (final rawLeg in rawLegs) {
        final legSum = (rawLeg['summary'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
        final rawMans = (rawLeg['maneuvers'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList();

        final maneuvers = <RouteManeuver>[];
        for (final m in rawMans) {
          final mType = (m['type'] as num?)?.toInt() ?? 8;
          final distKm = (m['length'] as num?)?.toDouble() ?? 0.0;
          final timeSec = (m['time'] as num?)?.toDouble() ?? 0.0;
          final streets = (m['street_names'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e.toString())
              .where((s) => s.trim().isNotEmpty)
              .toList();
          final isHwy = (m['highway'] as bool?) ?? false;
          final isToll = (m['toll'] as bool?) ?? false;
          if (isHwy) hasHighways = true;
          if (isToll) hasTolls = true;
          if (mType != 1 && mType != 4 && mType != 5 && mType != 6 && mType != 8) {
            turnCount += 1;
          }
          if (streets.isNotEmpty && distKm > longestCorridorKm) {
            longestCorridorKm = distKm;
            primaryCorridor = 'via ${streets.first}';
          }

          maneuvers.add(
            RouteManeuver(
              type: mType,
              instruction: (m['instruction'] as String?) ?? 'Continue',
              verbalPreTransitionInstruction:
                  m['verbal_pre_transition_instruction'] as String?,
              streetNames: streets,
              distanceKm: distKm,
              timeSeconds: timeSec,
              beginShapeIndex: (m['begin_shape_index'] as num?)?.toInt() ?? 0,
              endShapeIndex: (m['end_shape_index'] as num?)?.toInt() ?? 0,
              toll: isToll,
              highway: isHwy,
              travelMode: (m['travel_mode'] as String?) ?? 'drive',
            ),
          );
        }

        legs.add(
          RouteLeg(
            distanceKm: (legSum['length'] as num?)?.toDouble() ?? 0.0,
            durationSeconds: (legSum['time'] as num?)?.toDouble() ?? 0.0,
            shapePolyline6: (rawLeg['shape'] as String?) ?? '',
            maneuvers: maneuvers,
          ),
        );
      }

      final totalDistKm = (summary['length'] as num?)?.toDouble() ??
          legs.fold<double>(0.0, (acc, l) => acc + l.distanceKm);
      final totalSec = (summary['time'] as num?)?.toDouble() ??
          legs.fold<double>(0.0, (acc, l) => acc + l.durationSeconds);
      final etaDelta = idx == 0 ? 0.0 : (totalSec - baseDuration);

      candidates.add(
        CandidateRoute(
          routeIndex: idx,
          profileUsed: request.profile.wireValue,
          summaryLabel: idx == 0 ? 'Fastest' : 'Alternate ${idx + 1}',
          uxPrimaryTag: idx == 0 ? 'Fastest Route' : 'Alternate Route',
          uxBadgeKind: idx == 0 ? 'fastest' : 'balanced',
          uxHighlights: <String>[
            'Live Valhalla OSM Graph',
            if (primaryCorridor != null) primaryCorridor,
          ],
          turnCount: turnCount,
          primaryCorridorName: primaryCorridor ?? 'Direct Road',
          etaDeltaSeconds: etaDelta,
          distanceKm: totalDistKm,
          durationSeconds: totalSec,
          baselineDurationSeconds: totalSec,
          hasTollRoads: hasTolls,
          hasHighways: hasHighways,
          countriesCrossed: crossed,
          legs: legs,
          tolls: const TollSummary(hasTolls: false, displayTotal: 'Free'),
        ),
      );
    }

    if (candidates.isEmpty) {
      throw StateError('Public Valhalla returned zero routes');
    }

    return RouteResponse(
      originCountry: originCountry,
      destinationCountry: destCountry,
      departureTime: request.departureTime ?? DateTime.now(),
      routes: candidates,
      cached: false,
    );
  }

  static Future<RouteResponse> _computeViaOsrm(
    http.Client client,
    RouteRequest request, {
    required Duration timeout,
  }) async {
    final profile = switch (request.profile) {
      RoutingProfileId.walk => 'foot',
      RoutingProfileId.cycle => 'bike',
      _ => 'driving',
    };
    final coords = <Coordinate>[
      request.origin,
      ...request.waypoints,
      request.destination,
    ].map((c) => '${c.lon.toStringAsFixed(6)},${c.lat.toStringAsFixed(6)}').join(';');

    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/$profile/$coords'
      '?overview=full&geometries=polyline6&steps=true&alternatives=true',
    );
    final resp = await client
        .get(uri, headers: const <String, String>{'Accept': 'application/json'})
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300 || resp.bodyBytes.isEmpty) {
      throw StateError('Public OSRM returned HTTP ${resp.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['code'] != 'Ok') {
      throw StateError('Unexpected OSRM payload');
    }

    final rawRoutes = (decoded['routes'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (rawRoutes.isEmpty) {
      throw StateError('OSRM returned zero routes');
    }

    final originCountry = _inferSeaCountry(request.origin);
    final destCountry = _inferSeaCountry(request.destination);
    final crossed = <String>{originCountry.isoA2, destCountry.isoA2}.toList();
    final baseDuration = (rawRoutes.first['duration'] as num?)?.toDouble() ?? 0.0;

    final candidates = <CandidateRoute>[];
    for (var idx = 0; idx < rawRoutes.length && idx < 3; idx++) {
      final r = rawRoutes[idx];
      final fullPoly6 = (r['geometry'] as String?) ?? '';
      final totalDistKm = ((r['distance'] as num?)?.toDouble() ?? 0.0) / 1000.0;
      final totalSec = (r['duration'] as num?)?.toDouble() ?? 0.0;
      final rawLegs = (r['legs'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();

      final maneuvers = <RouteManeuver>[];
      var hasHighways = false;
      var turnCount = 0;
      String? primaryCorridor;
      double longestStepKm = -1.0;

      // Approximate shape index progression proportional to cumulative distance
      final estimatedPts = _countPolyline6Points(fullPoly6);
      var accumKm = 0.0;

      for (final rawLeg in rawLegs) {
        final steps = (rawLeg['steps'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList();
        for (final step in steps) {
          final stepDistKm = ((step['distance'] as num?)?.toDouble() ?? 0.0) / 1000.0;
          final stepSec = (step['duration'] as num?)?.toDouble() ?? 0.0;
          final name = (step['name'] as String?)?.trim() ?? '';
          final ref = (step['ref'] as String?)?.trim() ?? '';
          final man = (step['maneuver'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
          final mTypeStr = (man['type'] as String?) ?? 'continue';
          final modifier = (man['modifier'] as String?) ?? '';
          final vType = _osrmToValhallaType(mTypeStr, modifier);

          final streets = <String>[
            if (name.isNotEmpty) name,
            if (ref.isNotEmpty && ref != name) ref,
          ];
          if (ref.toUpperCase().startsWith('E') || mTypeStr == 'on ramp' || mTypeStr == 'off ramp') {
            hasHighways = true;
          }
          if (vType != 1 && vType != 4 && vType != 5 && vType != 6 && vType != 8) {
            turnCount += 1;
          }
          if (streets.isNotEmpty && stepDistKm > longestStepKm) {
            longestStepKm = stepDistKm;
            primaryCorridor = 'via ${streets.first}';
          }

          final beginFrac = totalDistKm > 0 ? (accumKm / totalDistKm).clamp(0.0, 1.0) : 0.0;
          accumKm += stepDistKm;
          final endFrac = totalDistKm > 0 ? (accumKm / totalDistKm).clamp(0.0, 1.0) : 1.0;
          final maxIdx = estimatedPts > 1 ? estimatedPts - 1 : 1;

          maneuvers.add(
            RouteManeuver(
              type: vType,
              instruction: _formatOsrmInstruction(mTypeStr, modifier, name, ref),
              streetNames: streets,
              distanceKm: stepDistKm,
              timeSeconds: stepSec,
              beginShapeIndex: (beginFrac * maxIdx).round().clamp(0, maxIdx),
              endShapeIndex: (endFrac * maxIdx).round().clamp(0, maxIdx),
              highway: ref.toUpperCase().startsWith('E'),
            ),
          );
        }
      }

      candidates.add(
        CandidateRoute(
          routeIndex: idx,
          profileUsed: request.profile.wireValue,
          summaryLabel: idx == 0 ? 'Fastest' : 'Alternate ${idx + 1}',
          uxPrimaryTag: idx == 0 ? 'Fastest Route' : 'Alternate Route',
          uxBadgeKind: idx == 0 ? 'fastest' : 'balanced',
          uxHighlights: <String>[
            'Live OSM Road Routing',
            if (primaryCorridor != null) primaryCorridor,
          ],
          turnCount: turnCount,
          primaryCorridorName: primaryCorridor ?? 'Direct Road',
          etaDeltaSeconds: idx == 0 ? 0.0 : (totalSec - baseDuration),
          distanceKm: totalDistKm,
          durationSeconds: totalSec,
          baselineDurationSeconds: totalSec,
          hasTollRoads: false,
          hasHighways: hasHighways,
          countriesCrossed: crossed,
          legs: <RouteLeg>[
            RouteLeg(
              distanceKm: totalDistKm,
              durationSeconds: totalSec,
              shapePolyline6: fullPoly6,
              maneuvers: maneuvers,
            ),
          ],
          tolls: const TollSummary(hasTolls: false, displayTotal: 'Free'),
        ),
      );
    }

    return RouteResponse(
      originCountry: originCountry,
      destinationCountry: destCountry,
      departureTime: request.departureTime ?? DateTime.now(),
      routes: candidates,
      cached: false,
    );
  }

  static String _valhallaLanguage(String raw) {
    final code = raw.toLowerCase();
    if (code.startsWith('ms') || code.startsWith('id')) return 'en-US';
    if (code.startsWith('pt')) return 'pt-PT';
    if (code.startsWith('zh')) return 'zh-CN';
    if (code.startsWith('vi')) return 'vi-VN';
    return 'en-US';
  }

  static int _osrmToValhallaType(String type, String modifier) {
    if (type == 'depart') return 1;
    if (type == 'arrive') return 4;
    if (type == 'roundabout' || type == 'rotary') return 26;
    if (type == 'exit roundabout' || type == 'exit rotary') return 27;
    if (type == 'off ramp') return modifier.contains('left') ? 21 : 20;
    if (type == 'on ramp') return modifier.contains('left') ? 19 : 18;
    if (type == 'merge') return 25;
    if (modifier == 'uturn') return 12;
    if (modifier == 'sharp right') return 11;
    if (modifier == 'right') return 10;
    if (modifier == 'slight right') return 9;
    if (modifier == 'sharp left') return 14;
    if (modifier == 'left') return 15;
    if (modifier == 'slight left') return 16;
    return 8;
  }

  static String _formatOsrmInstruction(
    String type,
    String modifier,
    String name,
    String ref,
  ) {
    final road = name.isNotEmpty
        ? (ref.isNotEmpty && !name.contains(ref) ? '$name ($ref)' : name)
        : (ref.isNotEmpty ? 'Route $ref' : 'the road');
    switch (type) {
      case 'depart':
        return 'Head onto $road';
      case 'arrive':
        return 'Arrive at your destination';
      case 'roundabout':
      case 'rotary':
        return 'Enter roundabout toward $road';
      case 'exit roundabout':
      case 'exit rotary':
        return 'Exit roundabout onto $road';
      case 'off ramp':
        return 'Take exit ramp onto $road';
      case 'on ramp':
        return 'Merge onto $road';
      case 'merge':
        return 'Merge onto $road';
      case 'fork':
        return modifier.contains('left')
            ? 'Keep left at the fork toward $road'
            : 'Keep right at the fork toward $road';
      case 'new name':
      case 'continue':
        return 'Continue onto $road';
      default:
        if (modifier.contains('left')) return 'Turn left onto $road';
        if (modifier.contains('right')) return 'Turn right onto $road';
        if (modifier == 'uturn') return 'Make a U-turn onto $road';
        return 'Continue on $road';
    }
  }

  static int _countPolyline6Points(String encoded) {
    var idx = 0;
    var count = 0;
    final len = encoded.length;
    while (idx < len) {
      for (var dim = 0; dim < 2 && idx < len; dim++) {
        var b = 0;
        do {
          b = encoded.codeUnitAt(idx++) - 63;
        } while (b >= 0x20 && idx < len);
      }
      count += 1;
    }
    return count;
  }

  static CountryContext _inferSeaCountry(Coordinate c) {
    if (c.lat >= 1.13 && c.lat <= 1.475 && c.lon >= 103.58 && c.lon <= 104.12) {
      return const CountryContext(
        isoA2: 'SG',
        name: 'Singapore',
        currencyCode: 'SGD',
        currencySymbol: r'$',
        timezoneIana: 'Asia/Singapore',
      );
    }
    if (c.lat >= 4.0 && c.lat <= 5.1 && c.lon >= 114.06 && c.lon <= 115.36) {
      return const CountryContext(
        isoA2: 'BN',
        name: 'Brunei Darussalam',
        currencyCode: 'BND',
        currencySymbol: r'B$',
        timezoneIana: 'Asia/Brunei',
      );
    }
    if (c.lat < 0.8) {
      if (c.lon >= 124.0 && c.lat <= -8.0) {
        return const CountryContext(
          isoA2: 'TL',
          name: 'Timor-Leste',
          currencyCode: 'USD',
          currencySymbol: r'$',
          timezoneIana: 'Asia/Dili',
        );
      }
      return const CountryContext(
        isoA2: 'ID',
        name: 'Indonesia',
        currencyCode: 'IDR',
        currencySymbol: 'Rp',
        timezoneIana: 'Asia/Jakarta',
      );
    }
    if (c.lon >= 116.5 && c.lat >= 4.5) {
      return const CountryContext(
        isoA2: 'PH',
        name: 'Philippines',
        currencyCode: 'PHP',
        currencySymbol: '₱',
        timezoneIana: 'Asia/Manila',
      );
    }
    if (c.lat >= 6.4 && c.lon >= 97.3 && c.lon <= 105.6 && c.lat <= 20.5) {
      if (c.lon <= 98.8 && c.lat >= 10.0) {
        return const CountryContext(
          isoA2: 'MM',
          name: 'Myanmar',
          currencyCode: 'MMK',
          currencySymbol: 'K',
          timezoneIana: 'Asia/Yangon',
        );
      }
      if (c.lon >= 102.3 && c.lat <= 14.5) {
        return const CountryContext(
          isoA2: 'KH',
          name: 'Cambodia',
          currencyCode: 'KHR',
          currencySymbol: '៛',
          timezoneIana: 'Asia/Phnom_Penh',
        );
      }
      return const CountryContext(
        isoA2: 'TH',
        name: 'Thailand',
        currencyCode: 'THB',
        currencySymbol: '฿',
        timezoneIana: 'Asia/Bangkok',
      );
    }
    if (c.lon >= 102.0 && c.lat >= 8.5) {
      return const CountryContext(
        isoA2: 'VN',
        name: 'Vietnam',
        currencyCode: 'VND',
        currencySymbol: '₫',
        timezoneIana: 'Asia/Ho_Chi_Minh',
      );
    }
    return const CountryContext(
      isoA2: 'MY',
      name: 'Malaysia',
      currencyCode: 'MYR',
      currencySymbol: 'RM',
      timezoneIana: 'Asia/Kuala_Lumpur',
    );
  }
}
