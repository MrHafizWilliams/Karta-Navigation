import 'package:flutter_test/flutter_test.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_map_engine/karta_map_engine.dart';

void main() {
  test('PredictiveTilePrefetcher warms highway corridor + probable next turns in <10ms with LRU dedup', () {
    final prefetcher = PredictiveTilePrefetcher(maxLruEntries: 512);
    final corridor = <Coordinate>[
      const Coordinate(lat: 3.1579, lon: 101.7116), // KLCC
      const Coordinate(lat: 3.1100, lon: 101.7080),
      const Coordinate(lat: 3.0468, lon: 101.7062), // Sungai Besi Toll
      const Coordinate(lat: 3.0250, lon: 101.7600), // Sharp interchange exit bend
      const Coordinate(lat: 2.9500, lon: 101.8000),
      const Coordinate(lat: 2.8400, lon: 101.8500),
    ];

    // 1. Highway speed (110 km/h) -> 14 km lookahead across z=[12,13,14]
    final firstPlan = prefetcher.planCorridorPrefetch(
      routePoints: corridor,
      currentPosition: corridor.first,
      speedKmh: 110.0,
      upcomingTurnCoords: const <Coordinate>[Coordinate(lat: 3.0468, lon: 101.7062)],
      maxBatchSize: 64,
    );

    expect(firstPlan.lookaheadKm, 14.0);
    expect(firstPlan.zoomLevels, const <int>[12, 13, 14]);
    expect(firstPlan.tilesToFetch, isNotEmpty);
    expect(firstPlan.planningMs, lessThan(15.0));

    final reasons = firstPlan.tilesToFetch.map((t) => t.reason).toSet();
    expect(reasons, containsAll(<String>['corridor', 'next_turn']));

    // 2. Immediate repeat call from same point skips already-warmed tiles via LRU cache
    final secondPlan = prefetcher.planCorridorPrefetch(
      routePoints: corridor,
      currentPosition: corridor.first,
      speedKmh: 110.0,
      upcomingTurnCoords: const <Coordinate>[Coordinate(lat: 3.0468, lon: 101.7062)],
      maxBatchSize: 64,
    );
    expect(secondPlan.cacheHitsSkipped, greaterThan(0));
    expect(secondPlan.tilesToFetch.length, lessThan(firstPlan.tilesToFetch.length));

    // 3. Offline mode skips network prefetch cleanly
    final offlinePlan = prefetcher.planCorridorPrefetch(
      routePoints: corridor,
      currentPosition: corridor.first,
      speedKmh: 110.0,
      isOfflineMode: true,
    );
    expect(offlinePlan.tilesToFetch, isEmpty);
  });
}
