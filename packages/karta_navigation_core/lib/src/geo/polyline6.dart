import 'dart:math' as math;
import 'package:karta_api_client/karta_api_client.dart';

const double _earthRadiusM = 6371008.8;

/// Decodes a Valhalla precision-6 encoded polyline string into WGS 84 [Coordinate]s.
/// Uses arithmetic ZigZag decoding (no unary `~` or 32-bit shifts) so it produces
/// identical signed results on Dart VM (64-bit int), Dart Web (dart2js), and Wasm.
List<Coordinate> decodePolyline6(String encoded, {int precision = 6}) {
  if (encoded.isEmpty) return const <Coordinate>[];
  final factor = math.pow(10, precision).toDouble();
  final coords = <Coordinate>[];
  var index = 0;
  var lat = 0;
  var lon = 0;
  final len = encoded.length;

  int readSignedDelta() {
    var result = 0;
    var multiplier = 1;
    while (index < len) {
      final b = encoded.codeUnitAt(index++) - 63;
      result += (b & 0x1F) * multiplier;
      multiplier *= 32;
      if (b < 0x20) break;
    }
    return (result & 1) != 0 ? -((result ~/ 2) + 1) : (result ~/ 2);
  }

  while (index < len) {
    lat += readSignedDelta();
    lon += readSignedDelta();
    coords.add(Coordinate(lat: lat / factor, lon: lon / factor));
  }

  return coords;
}

/// Encodes a sequence of WGS 84 [Coordinate]s into Valhalla precision-6 polyline6 format.
/// Uses arithmetic ZigZag encoding so negative deltas are 100% safe on Dart Web (dart2js).
String encodePolyline6(List<Coordinate> coords, {int precision = 6}) {
  final factor = math.pow(10, precision).toDouble();
  final buf = StringBuffer();
  var prevLat = 0;
  var prevLon = 0;

  void encodeDelta(int delta) {
    var v = delta < 0 ? ((-delta) * 2 - 1) : (delta * 2);
    while (v >= 0x20) {
      buf.writeCharCode((0x20 | (v & 0x1F)) + 63);
      v = v ~/ 32;
    }
    buf.writeCharCode(v + 63);
  }

  for (final c in coords) {
    final iLat = (c.lat * factor).round();
    final iLon = (c.lon * factor).round();
    encodeDelta(iLat - prevLat);
    encodeDelta(iLon - prevLon);
    prevLat = iLat;
    prevLon = iLon;
  }
  return buf.toString();
}

double haversineMeters(Coordinate a, Coordinate b) {
  final phi1 = a.lat * math.pi / 180.0;
  final phi2 = b.lat * math.pi / 180.0;
  final dPhi = (b.lat - a.lat) * math.pi / 180.0;
  final dLam = (b.lon - a.lon) * math.pi / 180.0;
  final h = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) * math.cos(phi2) * math.sin(dLam / 2) * math.sin(dLam / 2);
  return 2 * _earthRadiusM * math.atan2(math.sqrt(h), math.sqrt(math.max(0.0, 1.0 - h)));
}

double initialBearingDeg(Coordinate a, Coordinate b) {
  final phi1 = a.lat * math.pi / 180.0;
  final phi2 = b.lat * math.pi / 180.0;
  final dLam = (b.lon - a.lon) * math.pi / 180.0;
  final x = math.sin(dLam) * math.cos(phi2);
  final y = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dLam);
  return (math.atan2(x, y) * 180.0 / math.pi + 360.0) % 360.0;
}

/// Smallest angular difference in degrees `[0, 180]`.
double angularDiffDeg(double a, double b) => ((a - b + 180.0) % 360.0 - 180.0).abs();

/// Shortest-arc bearing interpolation (`t` in `[0, 1]`).
double lerpBearingDeg(double fromDeg, double toDeg, double t) {
  final delta = ((toDeg - fromDeg + 540.0) % 360.0) - 180.0;
  return (fromDeg + delta * t + 360.0) % 360.0;
}

/// Pre-indexed route geometry across all legs with cumulative distance lookup
/// for O(log N) route interpolation, GPS projection, and maneuver distance countdowns.
class RouteGeometryIndex {
  RouteGeometryIndex._({
    required this.points,
    required this.cumulativeMeters,
    required this.legPointRanges,
  });

  factory RouteGeometryIndex.fromRoute(CandidateRoute route) {
    final pts = <Coordinate>[];
    final cum = <double>[];
    final ranges = <(int start, int end)>[];
    var totalM = 0.0;

    for (final leg in route.legs) {
      final decoded = decodePolyline6(leg.shapePolyline6);
      final legStart = pts.isEmpty ? 0 : pts.length - 1;
      for (var i = 0; i < decoded.length; i++) {
        if (pts.isNotEmpty && i == 0 && haversineMeters(pts.last, decoded[i]) < 1.0) {
          continue;
        }
        if (pts.isNotEmpty) {
          totalM += haversineMeters(pts.last, decoded[i]);
        }
        pts.add(decoded[i]);
        cum.add(totalM);
      }
      final legEnd = math.max(legStart, pts.length - 1);
      ranges.add((legStart, legEnd));
    }

    return RouteGeometryIndex._(
      points: pts,
      cumulativeMeters: cum,
      legPointRanges: ranges,
    );
  }

  final List<Coordinate> points;
  final List<double> cumulativeMeters;
  final List<(int start, int end)> legPointRanges;

  double get totalMeters => cumulativeMeters.isEmpty ? 0.0 : cumulativeMeters.last;

  /// Samples an interpolated point and heading at `distanceMeters` along the route.
  ({Coordinate coordinate, double bearingDeg, int segmentIndex}) sampleAtDistance(
    double distanceMeters,
  ) {
    if (points.isEmpty) {
      return (coordinate: const Coordinate(lat: 3.1579, lon: 101.7116), bearingDeg: 0, segmentIndex: 0);
    }
    if (points.length == 1 || distanceMeters <= 0) {
      final b = points.length > 1 ? initialBearingDeg(points[0], points[1]) : 0.0;
      return (coordinate: points.first, bearingDeg: b, segmentIndex: 0);
    }
    if (distanceMeters >= totalMeters) {
      final b = initialBearingDeg(points[points.length - 2], points.last);
      return (coordinate: points.last, bearingDeg: b, segmentIndex: points.length - 2);
    }

    var lo = 0;
    var hi = cumulativeMeters.length - 1;
    while (lo + 1 < hi) {
      final mid = (lo + hi) >> 1;
      if (cumulativeMeters[mid] <= distanceMeters) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final segStartM = cumulativeMeters[lo];
    final segEndM = cumulativeMeters[hi];
    final frac = (segEndM > segStartM) ? ((distanceMeters - segStartM) / (segEndM - segStartM)) : 0.0;
    final a = points[lo];
    final b = points[hi];
    final coord = Coordinate(
      lat: a.lat + (b.lat - a.lat) * frac,
      lon: a.lon + (b.lon - a.lon) * frac,
    );
    return (
      coordinate: coord,
      bearingDeg: initialBearingDeg(a, b),
      segmentIndex: lo,
    );
  }

  /// Distance in meters from start of route to a `(legIndex, shapeIndex)` point.
  double distanceAtLegShapeIndex(int legIndex, int shapeIndex) {
    if (legIndex < 0 || legIndex >= legPointRanges.length || cumulativeMeters.isEmpty) return 0;
    final (start, end) = legPointRanges[legIndex];
    final globalIdx = (start + shapeIndex).clamp(start, end);
    return cumulativeMeters[globalIdx];
  }

  /// Projects a raw GPS position onto the closest vertex window along the route.
  ({double routeDistanceMeters, double crossTrackMeters, int nearestIndex}) snapToRoute(
    Coordinate raw, {
    int? hintIndex,
  }) {
    if (points.isEmpty) {
      return (routeDistanceMeters: 0, crossTrackMeters: 0, nearestIndex: 0);
    }
    final searchStart = hintIndex != null ? math.max(0, hintIndex - 30) : 0;
    final searchEnd = hintIndex != null ? math.min(points.length - 1, hintIndex + 120) : points.length - 1;

    var bestIdx = searchStart;
    var bestDist = double.infinity;

    for (var i = searchStart; i <= searchEnd; i++) {
      final d = haversineMeters(raw, points[i]);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }

    // Fallback global scan if far from hint window
    if (bestDist > 120 && hintIndex != null) {
      for (var i = 0; i < points.length; i++) {
        final d = haversineMeters(raw, points[i]);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }
    }

    return (
      routeDistanceMeters: cumulativeMeters[bestIdx],
      crossTrackMeters: bestDist,
      nearestIndex: bestIdx,
    );
  }
}
