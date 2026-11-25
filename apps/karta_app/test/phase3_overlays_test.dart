import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_app/features/navigation/active_navigation_hud.dart';
import 'package:karta_app/main.dart';
import 'package:karta_app/state/karta_app_state.dart';
import 'package:karta_app/state/phase3_providers.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

NavigationSnapshot _activeNavigationSnapshot() {
  const route = CandidateRoute(
    routeIndex: 0,
    profileUsed: 'drive_fastest',
    summaryLabel: 'Fastest • 3 hr 50 min',
    distanceKm: 356.0,
    durationSeconds: 13800,
    hasTollRoads: true,
    hasHighways: true,
    countriesCrossed: <String>['MY', 'SG'],
    tolls: TollSummary(hasTolls: true, displayTotal: 'RM 43.30'),
    legs: <RouteLeg>[
      RouteLeg(
        distanceKm: 356.0,
        durationSeconds: 13800,
        shapePolyline6: 'karta_shape',
        maneuvers: <RouteManeuver>[
          RouteManeuver(
            type: 18,
            instruction: 'Take Exit 161 toward Lebuhraya Utara-Selatan / E1',
            distanceKm: 1.2,
            timeSeconds: 50,
            beginShapeIndex: 0,
            endShapeIndex: 2,
            streetNames: <String>['Lebuhraya Utara-Selatan', 'E1'],
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
      instruction: 'Take Exit 161 toward Lebuhraya Utara-Selatan / E1',
      distanceKm: 1.2,
      timeSeconds: 50,
      beginShapeIndex: 0,
      endShapeIndex: 2,
      streetNames: <String>['Lebuhraya Utara-Selatan', 'E1'],
      toll: true,
      highway: true,
    ),
    distanceToManeuverMeters: 620,
    remainingDistanceMeters: 354800,
    remainingDurationSeconds: 13750,
    activeCountry: CountryContext(
      isoA2: 'MY',
      name: 'Malaysia',
      currencyCode: 'MYR',
      currencySymbol: 'RM',
      timezoneIana: 'Asia/Kuala_Lumpur',
    ),
    speedTelemetry: SpeedTelemetryState(
      currentSpeedKmh: 104,
      speedLimitKmh: 110,
      severity: SpeedAlertSeverity.normal,
    ),
  );
}

void main() {
  testWidgets('Floating 6-sector radial hazard reporting menu opens and selects category',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KartaApp()));
    await tester.pump(const Duration(milliseconds: 120));

    // Open Floating Radial Hazard Menu via single quick tap on FAB
    await tester.tap(find.byIcon(Icons.add_alert_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Police'), findsOneWidget);
    expect(find.text('Accident'), findsOneWidget);
    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('Stopped Car'), findsOneWidget);
    expect(find.text('Debris'), findsOneWidget);
    expect(find.text('Closure'), findsOneWidget);
    expect(find.text('SPEAK'), findsOneWidget);

    // Tap Police sector -> opens quick modifier & 3s auto-submit confirmation dock
    await tester.tap(find.text('Police'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Opposite Side'), findsOneWidget);
    expect(find.text('Report Now'), findsOneWidget);

    // Cancel cleanly so no timer remains active
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 120));
  });

  testWidgets('Tactile quick-flick tap-and-slide from FAB blooms arc and reports Crash on release',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KartaApp()));
    await tester.pump(const Duration(milliseconds: 120));
    final container = ProviderScope.containerOf(tester.element(find.byType(KartaApp)));

    final fabFinder = find.byKey(const ValueKey<String>('karta-quick-flick-fab'));
    expect(fabFinder, findsOneWidget);
    final fabCenter = tester.getCenter(fabFinder);

    // Press and slide straight left (-104dp) onto Crash sector
    final gesture = await tester.startGesture(fabCenter);
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveTo(fabCenter + const Offset(-104, 0));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.byKey(const ValueKey<String>('karta-quick-flick-arc-overlay')), findsOneWidget);
    expect(find.text('Release → Crash'), findsOneWidget);
    expect(find.text('Police'), findsOneWidget);
    expect(find.text('Hazard'), findsOneWidget);
    expect(find.text('Closure'), findsOneWidget);

    // Release submits quick_flick Accident report immediately
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 320));

    final hazards = container.read(realtimeCrowdsourcingProvider).hazards;
    expect(hazards.any((h) => h.category == HazardCategory.accident && h.source == 'quick_flick'),
        isTrue);

    // Dismiss toast timer cleanly
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
      'Non-blocking spatial hazard corner pill never covers TopManeuverHudBanner on Desktop or Mobile',
      (WidgetTester tester) async {
    for (final viewport in const <Size>[Size(1440, 900), Size(390, 844)]) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            navigationSnapshotProvider.overrideWith(
              (ref) => Stream<NavigationSnapshot>.value(_activeNavigationSnapshot()),
            ),
          ],
          child: const KartaApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
      final container = ProviderScope.containerOf(tester.element(find.byType(KartaApp)));

      // Push an active incoming hazard ahead on route
      final now = DateTime.now();
      container.read(realtimeCrowdsourcingProvider.notifier).upsertIncomingHazard(
            HazardRecord(
              id: 'haz-corner-${viewport.width.toInt()}',
              category: HazardCategory.police,
              severity: HazardSeverity.medium,
              coordinate: const Coordinate(lat: 3.160, lon: 101.712),
              roadRef: 'PLUS E1',
              distanceMeters: 420,
              onActiveRoute: true,
              confirmations: 4,
              createdAt: now,
              expiresAt: now.add(const Duration(minutes: 30)),
            ),
          );
      await tester.pump(const Duration(milliseconds: 350));

      final maneuverFinder = find.byType(TopManeuverHudBanner);
      final hazardPillFinder = find.byKey(const ValueKey<String>('karta-spatial-hazard-pill'));
      final stillThereFinder = find.byKey(const ValueKey<String>('hazard-vote-still-there'));
      final notThereFinder = find.byKey(const ValueKey<String>('hazard-vote-not-there'));

      expect(maneuverFinder, findsOneWidget);
      expect(hazardPillFinder, findsOneWidget);
      expect(stillThereFinder, findsOneWidget);
      expect(notThereFinder, findsOneWidget);

      // Verify zero spatial overlap with TopManeuverHudBanner
      final maneuverRect = tester.getRect(maneuverFinder);
      final hazardRect = tester.getRect(hazardPillFinder);
      expect(
        hazardRect.overlaps(maneuverRect),
        isFalse,
        reason: 'Hazard pill ($hazardRect) must never overlap Turn Maneuver card ($maneuverRect) on $viewport',
      );

      // Verify thumb-friendly >=48dp touch height for both vote buttons
      expect(tester.getSize(stillThereFinder).height, greaterThanOrEqualTo(48.0));
      expect(tester.getSize(notThereFinder).height, greaterThanOrEqualTo(48.0));

      // Tap Still There -> shows confirmation pulse then dismisses cleanly
      await tester.tap(stillThereFinder);
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.text('Confirmed · +1'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(seconds: 4));

      await tester.pumpWidget(const SizedBox.shrink());
    }
    tester.view.resetPhysicalSize();
  });

  testWidgets('Bottom voice waveform pill displays live Manglish transcription and cancels cleanly',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KartaApp()));
    await tester.pump(const Duration(milliseconds: 120));
    final container = ProviderScope.containerOf(tester.element(find.byType(KartaApp)));

    await container.read(handsFreeVoiceProvider.notifier).startListening();
    await tester.pump(const Duration(milliseconds: 120));

    final pillFinder = find.byKey(const ValueKey<String>('karta-voice-waveform-pill'));
    expect(pillFinder, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('karta-audio-waveform-bars')), findsOneWidget);
    // Pill is docked in the lower half of the viewport
    expect(tester.getRect(pillFinder).top, greaterThan(450));

    // Process Manglish voice transcript -> transitions cleanly to 3s auto-send countdown
    await container
        .read(handsFreeVoiceProvider.notifier)
        .processTranscript('Ada polis depan plaza tol');
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('POLICE'), findsOneWidget);
    expect(find.textContaining('Sending in'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('karta-voice-waveform-pill')), findsNothing);
  });

  testWidgets('Fuel station comparison overlay displays regional MY/SG grade pills',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KartaApp()));
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.text('FUEL'));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Fuel Finder Along Route'), findsOneWidget);
    expect(find.text('RON95'), findsOneWidget);
    expect(find.text('RON97'), findsOneWidget);
    expect(find.text('Map Badges ON'), findsOneWidget);
  });

  testWidgets(
      'Smart Commute Hub renders Calendar TTL & Privacy-First Carpool with privacy badges and 1-tap route insertion',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KartaApp()));
    await tester.pump(const Duration(milliseconds: 120));
    final container = ProviderScope.containerOf(tester.element(find.byType(KartaApp)));

    await tester.tap(find.text('Commute'));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Smart Commute Hub'), findsOneWidget);
    expect(find.text('Calendar & Events'), findsOneWidget);
    expect(find.text('Privacy Carpool'), findsOneWidget);

    // Seed real Smart Calendar TTL evaluation & Privacy Carpool match candidate
    final now = DateTime.now();
    final calEval = TimeToLeaveEvaluation(
      event: CalendarEventItem(
        id: 'ev-klcc-1',
        title: 'Product Sync @ KLCC',
        provider: 'facebook_ics',
        locationText: 'Petronas Twin Towers',
        destination: const Coordinate(lat: 3.1579, lon: 101.7116),
        countryCode: 'MY',
        startsAt: now.add(const Duration(minutes: 60)),
      ),
      baselineDurationSeconds: 1500,
      liveTrafficDurationSeconds: 1980,
      trafficDelaySeconds: 480,
      distanceKm: 18.4,
      estimatedTollDisplay: 'RM 3.20',
      recommendedDepartureAt: now.add(const Duration(minutes: 17)),
      minutesUntilDeparture: 17,
      urgencyLevel: 'leave_now',
      advisoryMessage: 'Leave by 18:10 (+8 min live traffic along AKLEH)',
    );

    final carpoolMatch = CarpoolMatchCandidate(
      offer: CarpoolOfferPublic(
        id: 'cp-subang-1',
        driverAlias: 'Farah (Subang → KLCC)',
        countryCode: 'MY',
        originZoneCenter: const Coordinate(lat: 3.0738, lon: 101.5883),
        originLandmarkName: 'LRT Subang Jaya Zone',
        destZoneCenter: const Coordinate(lat: 3.1579, lon: 101.7116),
        destLandmarkName: 'MRT KLCC Gate B Zone',
        privacyRadiusM: 500,
        routePolyline6: '',
        routeDistanceKm: 21.5,
        departureAt: now.add(const Duration(minutes: 25)),
        flexibilityMinutes: 15,
        seatsTotal: 3,
        seatsAvailable: 2,
        estimatedSplitMinor: 340,
        estimatedSplitFormatted: 'RM 3.40',
        currencyCode: 'MYR',
      ),
      pickupZoneCenter: const Coordinate(lat: 3.0738, lon: 101.5883),
      pickupLandmarkName: 'LRT Subang Jaya Zone',
      dropoffZoneCenter: const Coordinate(lat: 3.1579, lon: 101.7116),
      dropoffLandmarkName: 'MRT KLCC Gate B Zone',
      overlapPct: 78,
      detourMeters: 310,
      splitCostMinor: 340,
      splitCostFormatted: 'RM 3.40',
      currencyCode: 'MYR',
    );

    container.read(smartCommuterProvider.notifier).state = SmartCommuterState(
      evaluations: <TimeToLeaveEvaluation>[calEval],
      carpoolMatches: <CarpoolMatchCandidate>[carpoolMatch],
    );
    await tester.pump(const Duration(milliseconds: 160));

    // Verify Calendar TTL urgency badges and 1-tap direct single-destination navigation
    expect(find.text('Product Sync @ KLCC'), findsOneWidget);
    expect(find.text('+8m traffic'), findsOneWidget);
    expect(find.text('Navigate to Event'), findsOneWidget);
    expect(find.text('+ Add Stop'), findsNothing);

    final navEventBtn = find.byKey(const ValueKey<String>('ttl-insert-go-ev-klcc-1'));
    await tester.scrollUntilVisible(
      navEventBtn,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(navEventBtn);
    await tester.pump(const Duration(milliseconds: 160));
    final plannerAfterCal = container.read(routePlannerProvider);
    expect(plannerAfterCal.stops.length, equals(2));
    expect(plannerAfterCal.destination.label, contains('Product Sync @ KLCC'));

    // Return to Commute -> Privacy Carpool tab
    await tester.tap(find.text('Commute'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.tap(find.text('Privacy Carpool'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.textContaining('Privacy-First Shield'), findsOneWidget);
    expect(find.text('500m Privacy Zone'), findsWidgets);
    expect(find.text('Zero Home Address'), findsWidgets);
    expect(find.text('Mutual Opt-In'), findsWidgets);
    expect(find.text('Find Same-Direction Matches'), findsOneWidget);

    // 1-tap set Carpool pickup -> dropoff directly as Start & Destination (strictly 2 stops)
    final insertCarpoolBtn = find.byKey(const ValueKey<String>('carpool-insert-route-cp-subang-1'));
    await tester.scrollUntilVisible(
      insertCarpoolBtn,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(insertCarpoolBtn);
    await tester.pumpAndSettle();
    await tester.tap(insertCarpoolBtn);
    await tester.pump(const Duration(milliseconds: 160));

    final stopsAfterCarpool = container.read(routePlannerProvider).stops;
    expect(stopsAfterCarpool.length, equals(2));
    expect(stopsAfterCarpool.first.label, contains('LRT Subang Jaya Zone'));
    expect(stopsAfterCarpool.last.label, contains('MRT KLCC Gate B Zone'));

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Voice Pack Studio switches packs and creates a 12-cue custom user voice pack',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KartaApp()));
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.text('Vehicle'));
    await tester.pump(const Duration(milliseconds: 150));

    await tester.tap(find.text('Voice Packs'));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Karta Studio (EN)'), findsWidgets);
    expect(find.text('Kuala Lumpur Local (EN / BM)'), findsOneWidget);
    expect(find.text('Singapore Concise (EN-SG)'), findsOneWidget);

    // Create a custom user voice pack and verify 12-cue recorder slots appear
    await tester.tap(find.text('Create'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Recording Studio:'), findsOneWidget);
    expect(find.text('Turn Left'), findsOneWidget);
  });
}
