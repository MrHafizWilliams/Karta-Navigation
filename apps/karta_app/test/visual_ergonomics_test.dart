import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_app/features/navigation/active_navigation_hud.dart';
import 'package:karta_app/main.dart';
import 'package:karta_app/state/karta_app_state.dart';
import 'package:karta_app/state/lighting_providers.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

NavigationSnapshot _buildActiveExpresswaySnapshot() {
  const route = CandidateRoute(
    routeIndex: 0,
    profileUsed: 'drive_fastest',
    summaryLabel: 'Fastest • 4 hr 10 min',
    distanceKm: 356.0,
    durationSeconds: 15000,
    hasTollRoads: true,
    hasHighways: true,
    countriesCrossed: <String>['MY', 'SG'],
    tolls: TollSummary(hasTolls: true, displayTotal: 'RM 43.30 + \$2.00'),
    legs: <RouteLeg>[
      RouteLeg(
        distanceKm: 356.0,
        durationSeconds: 15000,
        shapePolyline6: 'karta_shape',
        maneuvers: <RouteManeuver>[
          RouteManeuver(
            type: 18,
            instruction: 'Take Exit 161 toward Jambatan Pulau Pinang / E1',
            distanceKm: 1.2,
            timeSeconds: 50,
            beginShapeIndex: 0,
            endShapeIndex: 2,
            streetNames: <String>['Lebuhraya Utara-Selatan', 'E1'],
            toll: true,
            highway: true,
          ),
          RouteManeuver(
            type: 10,
            instruction: 'Continue straight onto PLUS E1 Southbound',
            distanceKm: 140.0,
            timeSeconds: 4800,
            beginShapeIndex: 2,
            endShapeIndex: 8,
            streetNames: <String>['E1'],
            toll: true,
            highway: true,
          ),
        ],
      ),
    ],
  );

  return const NavigationSnapshot(
    phase: NavigationPhase.navigating,
    activeRoute: route,
    currentManeuver: RouteManeuver(
      type: 18,
      instruction: 'Take Exit 161 toward Jambatan Pulau Pinang / E1',
      distanceKm: 1.2,
      timeSeconds: 50,
      beginShapeIndex: 0,
      endShapeIndex: 2,
      streetNames: <String>['Lebuhraya Utara-Selatan', 'E1'],
      toll: true,
      highway: true,
    ),
    nextManeuver: RouteManeuver(
      type: 10,
      instruction: 'Continue straight onto PLUS E1 Southbound',
      distanceKm: 140.0,
      timeSeconds: 4800,
      beginShapeIndex: 2,
      endShapeIndex: 8,
      streetNames: <String>['E1'],
      toll: true,
      highway: true,
    ),
    distanceToManeuverMeters: 620,
    remainingDistanceMeters: 354800,
    remainingDurationSeconds: 14950,
    activeCountry: CountryContext(
      isoA2: 'MY',
      name: 'Malaysia',
      currencyCode: 'MYR',
      currencySymbol: 'RM',
      timezoneIana: 'Asia/Kuala_Lumpur',
    ),
    roadContext: RoadContextResponse(
      coordinate: Coordinate(lat: 5.3540, lon: 100.3450),
      roadName: 'Lebuhraya Utara-Selatan',
      roadRef: 'E1',
      highwayClass: 'motorway',
      speedLimitKmh: 110,
      isToll: true,
      isTunnel: false,
      turnLanes: <String>['through', 'through;right', 'right'],
    ),
    laneGuidance: LaneGuidanceBannerState(
      roadLanes: <RoadLaneDisplayItem>[
        RoadLaneDisplayItem(laneSpec: 'through', isRecommended: false),
        RoadLaneDisplayItem(laneSpec: 'through;right', isRecommended: true),
        RoadLaneDisplayItem(laneSpec: 'right', isRecommended: true),
      ],
    ),
    speedTelemetry: SpeedTelemetryState(
      currentSpeedKmh: 108,
      speedLimitKmh: 110,
      severity: SpeedAlertSeverity.normal,
    ),
  );
}

void main() {
  testWidgets('Desktop shell toggles Obsidian Night <-> Tropical Daylight and collapses glassmorphic sidebar',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KartaApp()));
    await tester.pump(const Duration(milliseconds: 120));

    final container = ProviderScope.containerOf(tester.element(find.byType(KartaApp)));

    // Explicitly switch to High-Glare Tropical Daylight and verify MaterialApp & MapController sync
    container.read(kartaLightingProvider.notifier).setPreference(KartaLightingPreference.day);
    await tester.pumpAndSettle();
    expect(container.read(kartaLightingProvider).isDaylight, isTrue);
    expect(container.read(kartaMapControllerProvider).lightingMode, equals(KartaVisualMode.tropicalDaylight));

    // Switch to Obsidian Night and verify sync
    container.read(kartaLightingProvider.notifier).setPreference(KartaLightingPreference.night);
    await tester.pumpAndSettle();
    expect(container.read(kartaLightingProvider).isNight, isTrue);
    expect(container.read(kartaMapControllerProvider).lightingMode, equals(KartaVisualMode.obsidianNight));

    // Tap lighting toggle pill -> transitions cleanly
    await tester.tap(find.byKey(const ValueKey<String>('karta-lighting-toggle')));
    await tester.pumpAndSettle();
    expect(container.read(kartaLightingProvider).isDaylight, isTrue);

    // Collapse glassmorphic desktop sidebar for full-bleed panorama
    expect(find.byKey(const ValueKey<String>('karta-sidebar-toggle')), findsOneWidget);
    expect(tester.getTopLeft(find.text('Karta Navigation')).dx, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey<String>('karta-sidebar-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Karta Navigation')).dx, lessThan(0));
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    // Re-expand sidebar
    await tester.tap(find.byKey(const ValueKey<String>('karta-sidebar-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Karta Navigation')).dx, greaterThan(0));
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
  });

  testWidgets('Active navigation HUD enforces >=60x60dp Fitts Law targets and renders MY Expressway Green signboard',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final snap = _buildActiveExpresswaySnapshot();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: KartaTheme.tropicalDaylight(),
          home: Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TopManeuverHudBanner(snapshot: snap),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: NavigationTripDock(snapshot: snap),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    // Expressway signboard & shield verification
    expect(find.byType(KartaHighwaySignboard), findsOneWidget);
    expect(find.byType(KartaAnimatedLaneGuidanceStrip), findsOneWidget);
    expect(find.text('E1'), findsOneWidget);
    expect(find.text('EXIT 161'), findsOneWidget);

    // Strictly verify >= 60x60dp touch targets on every lower driving button
    for (final keyId in const <String>[
      'nav-action-mute',
      'nav-action-voice',
      'nav-action-fuel',
      'nav-action-lookaround',
      'nav-action-end',
    ]) {
      final size = tester.getSize(find.byKey(ValueKey<String>(keyId)));
      expect(size.width, greaterThanOrEqualTo(60.0), reason: '$keyId width must be >= 60dp');
      expect(size.height, greaterThanOrEqualTo(60.0), reason: '$keyId height must be >= 60dp');
    }
  });

  testWidgets('MobileActiveNavigationSheet cycles 3-state spring detents cleanly on 390x844 viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final snap = _buildActiveExpresswaySnapshot();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: KartaTheme.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MobileActiveNavigationSheet(snapshot: snap),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    // Collapsed state shows ETA pill & 60x60dp End target
    final endSize = tester.getSize(find.byKey(const ValueKey<String>('mobile-nav-end')));
    expect(endSize.width, greaterThanOrEqualTo(60.0));
    expect(endSize.height, greaterThanOrEqualTo(60.0));
    expect(find.text('SPOTIFY'), findsNothing);

    // Tap handle -> Half state reveals 60x60dp driving actions (zero Spotify/media bar)
    await tester.tap(find.byKey(const ValueKey<String>('karta-sheet-handle')));
    await tester.pumpAndSettle();
    expect(find.text('SPOTIFY'), findsNothing);
    final fuelSize = tester.getSize(find.byKey(const ValueKey<String>('mobile-action-fuel')));
    expect(fuelSize.width, greaterThanOrEqualTo(60.0));
    expect(fuelSize.height, greaterThanOrEqualTo(60.0));

    // Tap handle -> Expanded state reveals Turn-by-Turn Steps
    await tester.tap(find.byKey(const ValueKey<String>('karta-sheet-handle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('TURN-BY-TURN STEPS'), findsOneWidget);
    expect(find.textContaining('Jambatan Pulau Pinang'), findsOneWidget);
  });
}
