import 'dart:collection';
import 'dart:math' as math;
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import 'package:meta/meta.dart';

@immutable
class VectorTileCoord {
  const VectorTileCoord({
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

  String get key => '$z/$x/$y';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'z': z,
        'x': x,
        'y': y,
        'priority': priority,
        'reason': reason,
        if (tileUrl != null) 'tileUrl': tileUrl,
      };
}

@immutable
class PrefetchBatchPlan {
  const PrefetchBatchPlan({
    required this.tilesToFetch,
    required this.lookaheadKm,
    required this.zoomLevels,
    required this.cacheHitsSkipped,
    required this.planningMs,
  });

  final List<VectorTileCoord> tilesToFetch;
  final double lookaheadKm;
  final List<int> zoomLevels;
  final int cacheHitsSkipped;
  final double planningMs;
}

/// Zero-latency predictive vector tile pre-fetcher along the active route corridor
/// and probable next turns (±60° alternate-exit fan-out + 3D pitch horizon buffer).
///
/// Tracks already-warmed Slippy-Map Web Mercator tiles in a bounded LRU cache so
/// highway-speed navigation (90-110 km/h on PLUS E1/E2 or Singapore CTE/PIE)
/// warms upcoming tiles well before MapLibre's viewport arrives.
class PredictiveTilePrefetcher {
  PredictiveTilePrefetcher({this.maxLruEntries = 512});

  final int maxLruEntries;
  final LinkedHashMap<String, DateTime> _warmedLru = LinkedHashMap<String, DateTime>();

  int _totalWarmed = 0;
  int _totalCacheHits = 0;
  double _lastPlanMs = 0.0;
  double _lastLookaheadKm = 0.0;

  int get warmedTileCount => _warmedLru.length;
  int get totalPrefetchedTiles => _totalWarmed;
  int get totalCacheHits => _totalCacheHits;
  double get lastPlanMs => _lastPlanMs;
  double get lastLookaheadKm => _lastLookaheadKm;

  static ({int x, int y}) latLonToTileXY(double lat, double lon, int zoom) {
    final clampedLat = lat.clamp(-85.05112878, 85.05112878);
    final latRad = clampedLat * math.pi / 180.0;
    final n = 1 << zoom;
    final x = ((lon + 180.0) / 360.0 * n).floor().clamp(0, n - 1);
    final y = ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n)
        .floor()
        .clamp(0, n - 1);
    return (x: x, y: y);
  }

  static ({double lookaheadKm, List<int> zooms}) adaptiveWindow(double speedKmh) {
    if (speedKmh >= 90.0) {
      return (lookaheadKm: 14.0, zooms: const <int>[12, 13, 14]);
    }
    if (speedKmh >= 55.0) {
      return (lookaheadKm: 7.0, zooms: const <int>[13, 14, 15]);
    }
    return (lookaheadKm: 3.0, zooms: const <int>[14, 15]);
  }

  /// Plans only the NEW (not-yet-warmed) vector tiles needed ahead of [currentPosition]
  /// along [routePoints], prioritizing upcoming turns and highway horizon tiles.
  PrefetchBatchPlan planCorridorPrefetch({
    required List<Coordinate> routePoints,
    required Coordinate currentPosition,
    required double speedKmh,
    List<Coordinate> upcomingTurnCoords = const <Coordinate>[],
    int maxBatchSize = 36,
    bool isOfflineMode = false,
  }) {
    final sw = Stopwatch()..start();
    final win = adaptiveWindow(speedKmh);
    if (isOfflineMode || routePoints.length < 2) {
      sw.stop();
      _lastPlanMs = sw.elapsedMicroseconds / 1000.0;
      _lastLookaheadKm = win.lookaheadKm;
      return PrefetchBatchPlan(
        tilesToFetch: const <VectorTileCoord>[],
        lookaheadKm: win.lookaheadKm,
        zoomLevels: win.zooms,
        cacheHitsSkipped: 0,
        planningMs: _lastPlanMs,
      );
    }

    // Locate closest vertex on corridor
    var startIdx = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < routePoints.length; i++) {
      final d = haversineMeters(currentPosition, routePoints[i]);
      if (d < bestDist) {
        bestDist = d;
        startIdx = i;
      }
    }

    final candidates = <String, VectorTileCoord>{};
    var cacheHits = 0;

    void consider(int z, int x, int y, int priority, String reason) {
      final n = 1 << z;
      if (x < 0 || y < 0 || x >= n || y >= n) return;
      final tile = VectorTileCoord(z: z, x: x, y: y, priority: priority, reason: reason);
      if (_warmedLru.containsKey(tile.key)) {
        // Touch LRU timestamp
        final ts = _warmedLru.remove(tile.key)!;
        _warmedLru[tile.key] = ts;
        cacheHits += 1;
        return;
      }
      final prev = candidates[tile.key];
      if (prev == null || priority < prev.priority) {
        candidates[tile.key] = tile;
      }
    }

    // 1. Priority 0 & 2: Upcoming turn coordinates + probable alternate-turn neighborhood
    final detailZoom = math.min(15, win.zooms.last);
    for (final turn in upcomingTurnCoords.take(4)) {
      final xy = latLonToTileXY(turn.lat, turn.lon, detailZoom);
      consider(detailZoom, xy.x, xy.y, 0, 'next_turn');
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          if (dx != 0 || dy != 0) {
            consider(detailZoom, xy.x + dx, xy.y + dy, 2, 'alternate_turn');
          }
        }
      }
    }

    // 2. Priority 0/1: Active corridor progression + 3D pitch lateral horizon buffer
    final maxLookaheadM = win.lookaheadKm * 1000.0;
    final sampleStepM = speedKmh >= 85.0 ? 450.0 : 250.0;
    var accumM = 0.0;
    var nextSampleM = 0.0;

    for (var i = startIdx; i < routePoints.length - 1; i++) {
      final p1 = routePoints[i];
      final p2 = routePoints[i + 1];
      final segM = haversineMeters(p1, p2);
      if (segM < 1.0) continue;

      final brg = initialBearingDeg(p1, p2);
      while (nextSampleM <= accumM + segM && nextSampleM <= maxLookaheadM) {
        final frac = (nextSampleM - accumM) / segM;
        final sLat = p1.lat + (p2.lat - p1.lat) * frac;
        final sLon = p1.lon + (p2.lon - p1.lon) * frac;
        final prio = nextSampleM <= 2500.0 ? 0 : 1;

        for (final z in win.zooms) {
          final xy = latLonToTileXY(sLat, sLon, z);
          consider(z, xy.x, xy.y, prio, 'corridor');
        }

        // Lateral horizon buffer (±900m) for 62-degree pitched 3D view
        final latZ = win.zooms.last;
        for (final offset in const <double>[-90.0, 90.0]) {
          final edge = _projectMeters(sLat, sLon, (brg + offset + 360.0) % 360.0, 900.0);
          final bxy = latLonToTileXY(edge.lat, edge.lon, latZ);
          consider(latZ, bxy.x, bxy.y, 1, 'horizon_buffer');
        }

        nextSampleM += sampleStepM;
      }

      // Detect upcoming bend/exit (>28 deg) and pre-warm ±60 deg probable exit fan-out
      if (i + 2 < routePoints.length && accumM <= 6000.0) {
        final nextBrg = initialBearingDeg(p2, routePoints[i + 2]);
        final delta = ((nextBrg - brg + 540.0) % 360.0 - 180.0).abs();
        if (delta >= 28.0) {
          final turnXY = latLonToTileXY(p2.lat, p2.lon, detailZoom);
          consider(detailZoom, turnXY.x, turnXY.y, 0, 'next_turn');
          for (final fan in const <double>[-60.0, 60.0]) {
            final fanPt = _projectMeters(p2.lat, p2.lon, (brg + fan + 360.0) % 360.0, 1200.0);
            final fxy = latLonToTileXY(fanPt.lat, fanPt.lon, detailZoom);
            consider(detailZoom, fxy.x, fxy.y, 2, 'alternate_turn');
          }
        }
      }

      accumM += segM;
      if (accumM > maxLookaheadM) break;
    }

    final sorted = candidates.values.toList()
      ..sort((a, b) {
        final p = a.priority.compareTo(b.priority);
        if (p != 0) return p;
        final z = a.z.compareTo(b.z);
        if (z != 0) return z;
        return a.x.compareTo(b.x);
      });

    final batch = sorted.take(maxBatchSize).toList(growable: false);
    final now = DateTime.now();
    for (final t in batch) {
      _warmedLru[t.key] = now;
      if (_warmedLru.length > maxLruEntries) {
        _warmedLru.remove(_warmedLru.keys.first);
      }
    }

    _totalWarmed += batch.length;
    _totalCacheHits += cacheHits;
    sw.stop();
    _lastPlanMs = sw.elapsedMicroseconds / 1000.0;
    _lastLookaheadKm = win.lookaheadKm;

    return PrefetchBatchPlan(
      tilesToFetch: batch,
      lookaheadKm: win.lookaheadKm,
      zoomLevels: win.zooms,
      cacheHitsSkipped: cacheHits,
      planningMs: _lastPlanMs,
    );
  }

  void clearCache() {
    _warmedLru.clear();
  }

  static Coordinate _projectMeters(double lat, double lon, double bearingDeg, double distMeters) {
    const earthR = 6371008.8;
    final ang = distMeters / earthR;
    final brg = bearingDeg * math.pi / 180.0;
    final lat1 = lat * math.pi / 180.0;
    final lon1 = lon * math.pi / 180.0;

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(ang) + math.cos(lat1) * math.sin(ang) * math.cos(brg),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(brg) * math.sin(ang) * math.cos(lat1),
          math.cos(ang) - math.sin(lat1) * math.sin(lat2),
        );
    return Coordinate(
      lat: lat2 * 180.0 / math.pi,
      lon: ((lon2 * 180.0 / math.pi + 540.0) % 360.0) - 180.0,
    );
  }
}
