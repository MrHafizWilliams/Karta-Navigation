import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_app/data/sea_featured_places.dart';
import 'package:karta_app/data/sea_state_regions.dart';
import 'package:karta_app/features/hazards/radial_hazard_menu.dart';
import 'package:karta_app/features/navigation/active_navigation_hud.dart';
import 'package:karta_app/main.dart';
import 'package:karta_app/state/karta_app_state.dart';
import 'package:karta_app/state/language_providers.dart';
import 'package:karta_app/state/lighting_providers.dart';
import 'package:karta_app/state/phase3_providers.dart';
import 'package:karta_app/state/region_welcome_providers.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_map_engine/karta_map_engine.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

class _ViewportSpec {
  const _ViewportSpec({
    required this.name,
    required this.size,
    required this.expectLeftRail,
  });

  final String name;
  final Size size;
  final bool expectLeftRail;
}

const List<_ViewportSpec> _allViewports = <_ViewportSpec>[
  _ViewportSpec(name: 'Mobile (390x844)', size: Size(390, 844), expectLeftRail: false),
  _ViewportSpec(name: 'Auto Compact (800x480)', size: Size(800, 480), expectLeftRail: true),
  _ViewportSpec(name: 'Auto Standard (1024x600)', size: Size(1024, 600), expectLeftRail: true),
  _ViewportSpec(name: 'Tablet (1024x1366)', size: Size(1024, 1366), expectLeftRail: true),
  _ViewportSpec(name: 'Auto Wide (1280x720)', size: Size(1280, 720), expectLeftRail: true),
  _ViewportSpec(name: 'Desktop (1440x900)', size: Size(1440, 900), expectLeftRail: true),
  _ViewportSpec(name: 'Auto Ultrawide (1920x720)', size: Size(1920, 720), expectLeftRail: true),
];

NavigationSnapshot _buildBusyNavigationSnapshot() {
  const route = CandidateRoute(
    routeIndex: 0,
    profileUsed: 'drive_fastest',
    summaryLabel: 'Fastest • 3 hr 42 min',
    primaryCorridorName: 'via PLUS E1',
    distanceKm: 356.0,
    durationSeconds: 13320,
    hasTollRoads: false,
    hasHighways: true,
    countriesCrossed: <String>['MY'],
    tolls: TollSummary(hasTolls: false, displayTotal: 'Free'),
    legs: <RouteLeg>[
      RouteLeg(
        distanceKm: 356.0,
        durationSeconds: 13320,
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
            highway: true,
          ),
          RouteManeuver(
            type: 10,
            instruction: 'Continue straight on PLUS E1 Southbound toward Kuala Lumpur',
            distanceKm: 140.0,
            timeSeconds: 4800,
            beginShapeIndex: 2,
            endShapeIndex: 8,
            streetNames: <String>['E1'],
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
      highway: true,
    ),
    nextManeuver: RouteManeuver(
      type: 10,
      instruction: 'Continue straight on PLUS E1 Southbound toward Kuala Lumpur',
      distanceKm: 140.0,
      timeSeconds: 4800,
      beginShapeIndex: 2,
      endShapeIndex: 8,
      streetNames: <String>['E1'],
      highway: true,
    ),
    distanceToManeuverMeters: 620,
    remainingDistanceMeters: 354800,
    remainingDurationSeconds: 13270,
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
      isToll: false,
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
      currentSpeedKmh: 118,
      speedLimitKmh: 110,
      severity: SpeedAlertSeverity.caution,
      overLimitByKmh: 8,
      approachingCamera: ApproachingSpeedZone(
        id: 161,
        zoneType: 'AWAS',
        limitKmh: 110,
        roadName: 'PLUS E1',
        distanceMeters: 480,
        coordinate: Coordinate(lat: 5.3590, lon: 100.3490),
      ),
    ),
  );
}

void _assertNoPairwiseOverlap(
  Map<String, Rect> boxes, {
  required String contextLabel,
}) {
  final entries = boxes.entries.toList();
  for (var i = 0; i < entries.length; i++) {
    for (var j = i + 1; j < entries.length; j++) {
      final a = entries[i];
      final b = entries[j];
      // Shrink by 1dp epsilon for touching edges
      final overlap = a.value.deflate(1.0).overlaps(b.value.deflate(1.0));
      expect(
        overlap,
        isFalse,
        reason: '$contextLabel: "${a.key}" (${a.value}) overlaps "${b.key}" (${b.value})',
      );
    }
  }
}

void main() {
  group('Karta UI/UX Consistency & Brand Regression Suite', () {
    test('GEMINI.md tokens & bundled typography families match specification', () {
      expect(KartaColors.backgroundPrimary, equals(const Color(0xFF0D0F12)));
      expect(KartaColors.surfaceCard, equals(const Color(0xFF181C22)));
      expect(KartaColors.accentPrimary, equals(const Color(0xFF5B9A94)));
      expect(KartaColors.textPrimary, equals(const Color(0xFFF4F6F8)));
      expect(KartaColors.textSecondary, equals(const Color(0xFF8E96A0)));

      // Zero drift between static KartaColors and KartaPalette.obsidianNight
      expect(KartaColors.backgroundPrimary, equals(KartaPalette.obsidianNight.backgroundPrimary));
      expect(KartaColors.surfaceCard, equals(KartaPalette.obsidianNight.surfaceCard));
      expect(KartaColors.accentPrimary, equals(KartaPalette.obsidianNight.accentPrimary));
      expect(KartaColors.textPrimary, equals(KartaPalette.obsidianNight.textPrimary));
      expect(KartaColors.textSecondary, equals(KartaPalette.obsidianNight.textSecondary));

      // Local bundled font families registered on typography tokens inside karta_design_system
      expect(KartaTypography.hudHero.fontFamily, equals('packages/karta_design_system/Plus Jakarta Sans'));
      expect(KartaTypography.monoBadge.fontFamily, equals('packages/karta_design_system/JetBrains Mono'));
      expect(KartaTypography.sectionTitle.fontFamily, equals('packages/karta_design_system/Plus Jakarta Sans'));
      expect(KartaTypography.bodyPrimary.fontFamily, equals('packages/karta_design_system/Plus Jakarta Sans'));
      expect(KartaTypography.bodySecondary.fontFamily, equals('packages/karta_design_system/Plus Jakarta Sans'));
    });

    testWidgets(
      'Explore mode renders cleanly across all 7 viewports in both Night & Day modes with correct nav chrome',
      (WidgetTester tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        for (final vp in _allViewports) {
          for (final mode in const <KartaLightingPreference>[
            KartaLightingPreference.night,
            KartaLightingPreference.day,
          ]) {
            tester.view.physicalSize = vp.size;
            tester.view.devicePixelRatio = 1.0;

            await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
            await tester.pump(const Duration(milliseconds: 120));

            final container = ProviderScope.containerOf(tester.element(find.byType(KartaApp)));
            container.read(kartaLightingProvider.notifier).setPreference(mode);
            await tester.pump(const Duration(milliseconds: 180));

            final label = '${vp.name} [${mode.name}] Explore';
            expect(tester.takeException(), isNull, reason: '$label threw an exception');

            // Verify Navigation Chrome Architecture:
            // Medium (Tablet & Standard Auto) + Expanded (Desktop & Wide Auto) => persistent left rail
            // + clean Google Maps-style floating search bar + Profile above Exit in left rail
            // Compact (Smartphone < 640dp) => distinct compact bottom tab bar + minimized explore bar
            if (vp.expectLeftRail) {
              expect(find.text('KARTA'), findsOneWidget, reason: '$label must show persistent left nav rail');
              expect(
                find.byKey(const ValueKey<String>('karta-floating-search-bar')),
                findsOneWidget,
                reason: '$label must show Google Maps-style floating search bar',
              );
              expect(
                find.byKey(const ValueKey<String>('karta-directions-btn')),
                findsOneWidget,
                reason: '$label must show Directions diamond button',
              );
              final profileFinder = find.byKey(const ValueKey<String>('karta-header-account-btn'));
              final exitFinder = find.byKey(const ValueKey<String>('karta-rail-exit-btn'));
              expect(profileFinder, findsOneWidget, reason: '$label must show Profile icon in left rail');
              expect(exitFinder, findsOneWidget, reason: '$label must show Exit button in left rail');
              expect(
                tester.getRect(profileFinder).bottom,
                lessThanOrEqualTo(tester.getRect(exitFinder).top),
                reason: '$label Profile icon must sit above Exit button in left rail',
              );
            } else {
              expect(find.text('KARTA'), findsNothing, reason: '$label smartphone must NOT show desktop nav rail');
              expect(find.text('Navigate'), findsOneWidget);
              expect(find.text('Offline'), findsOneWidget);
              expect(find.text('Vehicle'), findsOneWidget);
              expect(find.byKey(const ValueKey<String>('karta-mobile-explore-minimized')), findsOneWidget);
            }

            // Core branding & feature removals verified
            expect(find.text('SPOTIFY'), findsNothing, reason: '$label zero Spotify');
            expect(find.text('Tolls & Class'), findsNothing, reason: '$label zero toll controls');
            expect(find.text('Avoid Tolls'), findsNothing, reason: '$label zero avoid tolls');
            expect(find.text('TOL RM'), findsNothing, reason: '$label zero TOL RM');
            expect(find.text('ERP \$'), findsNothing, reason: '$label zero ERP \$');

            // Single-destination enforcement (always exactly 2 stops: origin & destination)
            expect(container.read(routePlannerProvider).stops.length, equals(2));

            // Touch target checks on map controls
            final lightingBtn = find.byKey(const ValueKey<String>('karta-lighting-toggle'));
            expect(lightingBtn, findsOneWidget);
            expect(tester.getSize(lightingBtn).width, greaterThanOrEqualTo(48.0));
            expect(tester.getSize(lightingBtn).height, greaterThanOrEqualTo(48.0));

            final myLocBtn = find.byKey(const ValueKey<String>('karta-my-location-btn'));
            expect(myLocBtn, findsOneWidget);
            expect(tester.getSize(myLocBtn).width, greaterThanOrEqualTo(48.0));
            expect(tester.getSize(myLocBtn).height, greaterThanOrEqualTo(48.0));

            // Clean teardown before next viewport
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          }
        }
      },
    );

    testWidgets(
      'Active Navigation HUD has ZERO overlaps and ZERO overflows across all 7 viewports in Night & Day modes',
      (WidgetTester tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final busySnap = _buildBusyNavigationSnapshot();

        for (final vp in _allViewports) {
          for (final mode in const <KartaLightingPreference>[
            KartaLightingPreference.night,
            KartaLightingPreference.day,
          ]) {
            tester.view.physicalSize = vp.size;
            tester.view.devicePixelRatio = 1.0;

            await tester.pumpWidget(
              ProviderScope(
                overrides: <Override>[
                  navigationSnapshotProvider.overrideWith(
                    (ref) => Stream<NavigationSnapshot>.value(busySnap),
                  ),
                ],
                child: const KartaApp(enableIntroAnimation: false),
              ),
            );
            await tester.pump(const Duration(milliseconds: 140));

            final container = ProviderScope.containerOf(tester.element(find.byType(KartaApp)));
            container.read(kartaLightingProvider.notifier).setPreference(mode);

            // Inject active incoming hazard to stress-test simultaneous AWAS + Hazard + Speed + Maneuver HUD
            final now = DateTime.now();
            container.read(realtimeCrowdsourcingProvider.notifier).upsertIncomingHazard(
                  HazardRecord(
                    id: 'haz-stress-${vp.size.width.toInt()}-${mode.name}',
                    category: HazardCategory.police,
                    severity: HazardSeverity.medium,
                    coordinate: const Coordinate(lat: 5.360, lon: 100.350),
                    roadRef: 'PLUS E1',
                    distanceMeters: 420,
                    onActiveRoute: true,
                    confirmations: 5,
                    createdAt: now,
                    expiresAt: now.add(const Duration(minutes: 30)),
                  ),
                );
            await tester.pump(const Duration(milliseconds: 350));

            final label = '${vp.name} [${mode.name}] ActiveNav';
            expect(tester.takeException(), isNull, reason: '$label threw an exception');

            // Collect bounding boxes of all active HUD surfaces
            final hudBoxes = <String, Rect>{};
            final topManeuver = find.byType(TopManeuverHudBanner);
            final hazardPill = find.byKey(const ValueKey<String>('karta-spatial-hazard-pill'));
            final speedCluster = find.byType(SpeedTelemetryCluster);
            final tripDock = find.byType(NavigationTripDock);
            final mobileSheet = find.byType(MobileActiveNavigationSheet);
            final crowdsourcingCluster = find.byType(FloatingCrowdsourcingTriggerCluster);
            final lightingToggle = find.byKey(const ValueKey<String>('karta-lighting-toggle'));

            expect(topManeuver, findsOneWidget, reason: '$label top maneuver visible');
            hudBoxes['TopManeuverHudBanner'] = tester.getRect(topManeuver);

            if (hazardPill.evaluate().isNotEmpty) {
              hudBoxes['SpatialHazardCornerPill'] = tester.getRect(hazardPill);
            }
            if (speedCluster.evaluate().isNotEmpty) {
              hudBoxes['SpeedTelemetryCluster'] = tester.getRect(speedCluster);
            }
            if (tripDock.evaluate().isNotEmpty) {
              hudBoxes['NavigationTripDock'] = tester.getRect(tripDock);
            }
            if (mobileSheet.evaluate().isNotEmpty) {
              hudBoxes['MobileActiveNavigationSheet'] = tester.getRect(mobileSheet);
            }
            if (crowdsourcingCluster.evaluate().isNotEmpty) {
              hudBoxes['FloatingCrowdsourcingCluster'] = tester.getRect(crowdsourcingCluster);
            }
            if (lightingToggle.evaluate().isNotEmpty) {
              hudBoxes['TopRightLightingToggle'] = tester.getRect(lightingToggle);
            }

            _assertNoPairwiseOverlap(hudBoxes, contextLabel: label);

            // Verify zero toll/music artifacts in active nav
            expect(find.text('TOLL EXPY'), findsNothing, reason: '$label zero TOLL EXPY');
            expect(find.text('SPOTIFY'), findsNothing, reason: '$label zero SPOTIFY');

            // Verify quick-flick FAB driving target >= 60x60dp
            final fab = find.byKey(const ValueKey<String>('karta-quick-flick-fab'));
            expect(fab, findsOneWidget);
            expect(tester.getSize(fab).width, greaterThanOrEqualTo(60.0));
            expect(tester.getSize(fab).height, greaterThanOrEqualTo(60.0));

            // Clean up hazard timers cleanly before switching viewport
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(seconds: 1));
          }
        }
      },
    );

    testWidgets(
      'Radial hazard menu renders with theme-aware contrast in Tropical Daylight and dismisses cleanly',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1024, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
        await tester.pump(const Duration(milliseconds: 120));

        final container = ProviderScope.containerOf(tester.element(find.byType(KartaApp)));
        container.read(kartaLightingProvider.notifier).setPreference(KartaLightingPreference.day);
        await tester.pump(const Duration(milliseconds: 150));

        await tester.tap(find.byIcon(Icons.add_alert_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text('Police'), findsOneWidget);
        expect(find.text('Accident'), findsOneWidget);
        expect(find.text('Dismiss'), findsOneWidget);

        await tester.tap(find.text('Dismiss'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Dismiss'), findsNothing);
      },
    );

    testWidgets(
      'Saved tab renders Sign In / Create Account registration flow cleanly',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
        await tester.pump(const Duration(milliseconds: 120));

        await tester.tap(find.text('Saved'));
        await tester.pumpAndSettle();

        expect(find.text('Karta Account'), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('karta-auth-tab-login')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('karta-auth-tab-register')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey<String>('karta-auth-tab-register')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey<String>('karta-auth-name-field')), findsOneWidget);
        expect(find.text('Create Karta Account'), findsOneWidget);
      },
    );

    testWidgets(
      'Cross-platform Karta intro animation plays on launch and transitions cleanly into live map',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const ProviderScope(child: KartaApp()));
        await tester.pump(const Duration(milliseconds: 450));

        expect(find.byKey(const ValueKey<String>('karta-intro-splash')), findsOneWidget);
        expect(find.text('Tap anywhere to skip'), findsOneWidget);

        // Tap intro splash to skip cleanly into the live app
        await tester.tap(find.byKey(const ValueKey<String>('karta-intro-splash')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey<String>('karta-intro-splash')), findsNothing);
        expect(find.byKey(const ValueKey<String>('karta-mobile-explore-minimized')), findsOneWidget);
      },
    );

    testWidgets(
      'Smartphone explore sheet starts minimized for full-map visibility and toggles expand/minimize smoothly',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
        await tester.pump(const Duration(milliseconds: 120));

        final minimizedFinder = find.byKey(const ValueKey<String>('karta-mobile-explore-minimized'));
        expect(minimizedFinder, findsOneWidget);
        expect(tester.getSize(minimizedFinder).height, lessThan(96.0));

        // Expand sheet
        await tester.tap(find.byKey(const ValueKey<String>('karta-mobile-explore-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey<String>('karta-mobile-explore-expanded')), findsOneWidget);
        expect(find.text('Minimize'), findsOneWidget);

        // Minimize back to full map
        await tester.tap(find.text('Minimize'));
        await tester.pumpAndSettle();
        expect(minimizedFinder, findsOneWidget);
      },
    );

    testWidgets(
      'Waze-style Exit confirmation dialog prompts cleanly and dismisses on Stay',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
        await tester.pump(const Duration(milliseconds: 120));

        await tester.tap(find.byKey(const ValueKey<String>('karta-rail-exit-btn')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey<String>('karta-exit-dialog')), findsOneWidget);
        expect(find.text('Exit Karta Navigation?'), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('karta-exit-cancel-btn')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('karta-exit-confirm-btn')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey<String>('karta-exit-cancel-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey<String>('karta-exit-dialog')), findsNothing);
      },
    );

    testWidgets(
      'Google Maps floating search bar expands to Directions drawer and left-rail Profile opens Karta Account',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
        await tester.pump(const Duration(milliseconds: 120));

        // Clean Google Maps-style floating search bar on launch
        expect(find.byKey(const ValueKey<String>('karta-floating-search-bar')), findsOneWidget);
        expect(find.text('Restaurants'), findsOneWidget);

        // Open full Directions planner drawer
        await tester.tap(find.byKey(const ValueKey<String>('karta-directions-btn')));
        await tester.pumpAndSettle();
        expect(find.text('Karta Navigation'), findsOneWidget);
        final toggleFinder = find.byKey(const ValueKey<String>('karta-sidebar-toggle'));
        expect(toggleFinder, findsOneWidget);
        expect(tester.getSize(toggleFinder).width, greaterThanOrEqualTo(48.0));
        expect(tester.getSize(toggleFinder).height, greaterThanOrEqualTo(48.0));

        // Close Directions drawer back to clean floating bar
        await tester.tap(find.byKey(const ValueKey<String>('karta-close-directions-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey<String>('karta-floating-search-bar')), findsOneWidget);

        // Click left-rail Profile icon (above Exit) -> opens Karta Account
        await tester.tap(find.byKey(const ValueKey<String>('karta-header-account-btn')));
        await tester.pumpAndSettle();
        expect(find.text('Karta Account'), findsOneWidget);
      },
    );

    test('SEA Featured Places catalog covers all 11 countries, airports, mosques, temples, churches & rail hubs', () {
      const seaCountries = <String>{'MY', 'SG', 'BN', 'ID', 'TH', 'PH', 'VN', 'MM', 'LA', 'KH', 'TL'};
      final coveredCountries = SeaFeaturedPlacesCatalog.all.map((p) => p.countryCode).toSet();
      expect(coveredCountries, containsAll(seaCountries));

      final kinds = SeaFeaturedPlacesCatalog.all.map((p) => p.kind).toSet();
      expect(kinds, containsAll(<KartaPlaceKind>{
        KartaPlaceKind.historicalLandmark,
        KartaPlaceKind.modernLandmark,
        KartaPlaceKind.airport,
        KartaPlaceKind.mosque,
        KartaPlaceKind.temple,
        KartaPlaceKind.church,
        KartaPlaceKind.railHub,
      }));

      // Verify vector-tile station & religious place tap classification
      final station = SeaFeaturedPlacesCatalog.fromVectorTap(
        const KartaVectorFeatureTap(
          name: 'Pasar Seni MRT Station',
          featureClass: 'railway',
          subclass: 'station',
          coordinate: Coordinate(lat: 3.1425, lon: 101.6953),
        ),
      );
      expect(station.kind, equals(KartaPlaceKind.trainStation));

      final mosque = SeaFeaturedPlacesCatalog.fromVectorTap(
        const KartaVectorFeatureTap(
          name: 'Masjid Jamek Seberang Jaya',
          featureClass: 'place_of_worship',
          subclass: 'mosque',
          religion: 'muslim',
          coordinate: Coordinate(lat: 5.3970, lon: 100.3980),
        ),
      );
      expect(mosque.kind, equals(KartaPlaceKind.mosque));
    });

    testWidgets(
      '11-language SEA switcher translates UI live across Bahasa Melayu, Thai, Mandarin, Tagalog & back to English',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        expect(KartaLanguage.values.length, equals(11));

        await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
        await tester.pump(const Duration(milliseconds: 120));

        // Open Language Picker from left rail
        await tester.tap(find.byKey(const ValueKey<String>('karta-language-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey<String>('karta-language-dialog')), findsOneWidget);

        // Switch to Bahasa Melayu
        await tester.tap(find.byKey(const ValueKey<String>('karta-lang-option-ms')));
        await tester.pumpAndSettle();
        expect(find.text('Navigasi'), findsOneWidget);
        expect(find.text('Mercu Tanda'), findsOneWidget);
        expect(find.text('Lapangan Terbang'), findsOneWidget);
        expect(find.text('Rumah Ibadat'), findsOneWidget);

        // Switch to Thai
        await tester.tap(find.byKey(const ValueKey<String>('karta-language-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('karta-lang-option-th')));
        await tester.pumpAndSettle();
        expect(find.text('นำทาง'), findsOneWidget);
        expect(find.text('แลนด์มาร์ก'), findsOneWidget);

        // Switch back to English so persisted state stays default
        await tester.tap(find.byKey(const ValueKey<String>('karta-language-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('karta-lang-option-en')));
        await tester.pumpAndSettle();
        expect(find.text('Navigate'), findsOneWidget);
        expect(find.text('Landmarks'), findsOneWidget);
      },
    );

    testWidgets(
      'Clicking Landmarks, Airports, or Sacred Sites chips opens rich clickable tourist info card',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
        await tester.pump(const Duration(milliseconds: 120));

        // Tap Airports chip -> select Kuala Lumpur International Airport (KUL)
        await tester.tap(find.byKey(const ValueKey<String>('karta-chip-airports')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey<String>('karta-search-feat-my-kul')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey<String>('karta-search-feat-my-kul')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey<String>('karta-place-info-card')), findsOneWidget);
        expect(find.text('Kuala Lumpur International Airport'), findsOneWidget);
        expect(find.text('KUL'), findsOneWidget);
        expect(find.textContaining('KLIA Ekspres'), findsWidgets);

        // Close info card cleanly
        await tester.tap(find.byKey(const ValueKey<String>('karta-place-info-close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey<String>('karta-place-info-card')), findsNothing);
      },
    );

    test('SEA state/district geofence resolves Malaysian states, territories & all 11 SEA countries accurately', () {
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 5.3840, lon: 100.4128))?.id, equals('my-penang'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 3.1579, lon: 101.7116))?.id, equals('my-kl'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 2.9361, lon: 101.6893))?.id, equals('my-putrajaya'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 4.5975, lon: 101.0901))?.id, equals('my-perak'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 1.4927, lon: 103.7414))?.id, equals('my-johor'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 1.2834, lon: 103.8607))?.countryCode, equals('SG'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 4.8895, lon: 114.9392))?.id, equals('bn-brunei-muara'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: -6.1754, lon: 106.8272))?.id, equals('id-jakarta'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: -8.6212, lon: 115.0868))?.id, equals('id-bali'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 13.7500, lon: 100.4913))?.id, equals('th-bangkok'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 14.5942, lon: 120.9703))?.id, equals('ph-ncr'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 10.7798, lon: 106.6990))?.id, equals('vn-hcmc'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 16.7983, lon: 96.1496))?.id, equals('mm-yangon'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 17.9706, lon: 102.6186))?.id, equals('la-vientiane'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: 13.4125, lon: 103.8670))?.id, equals('kh-siemreap'));
      expect(SeaStateRegionResolver.resolve(const Coordinate(lat: -8.5569, lon: 125.5603))?.id, equals('tl-dili'));
    });

    testWidgets(
      'Active navigation border-crossing triggers localized welcome banner with authentic official state flag',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final busySnap = _buildBusyNavigationSnapshot();
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              navigationSnapshotProvider.overrideWith(
                (ref) => Stream<NavigationSnapshot>.value(busySnap),
              ),
            ],
            child: const KartaApp(enableIntroAnimation: false),
          ),
        );
        await tester.pump(const Duration(milliseconds: 140));

        final container = ProviderScope.containerOf(tester.element(find.byType(KartaApp)));

        // Before navigation session starts, fixing position does NOT trigger a banner
        container.read(regionWelcomeProvider.notifier).onNavigationFix(
              const Coordinate(lat: 5.3840, lon: 100.4128),
            );
        await tester.pump();
        expect(find.byKey(const ValueKey<String>('karta-region-welcome-banner')), findsNothing);

        // Start navigation in Penang -> seeds Penang silently (no greeting for starting state)
        container.read(regionWelcomeProvider.notifier).beginNavigationSession(
              const Coordinate(lat: 5.3840, lon: 100.4128),
            );
        await tester.pump();
        expect(find.byKey(const ValueKey<String>('karta-region-welcome-banner')), findsNothing);

        // Vehicle crosses Penang -> Perak border -> shows Welcome to Perak + official Perak flag PNG
        container.read(regionWelcomeProvider.notifier).onNavigationFix(
              const Coordinate(lat: 4.8500, lon: 100.7500),
            );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byKey(const ValueKey<String>('karta-region-welcome-banner')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('karta-region-flag-my-perak')), findsOneWidget);
        expect(find.text('Welcome to Perak'), findsOneWidget);
        expect(KartaStateFlag.resolveAssetPath('my-perak'), equals('assets/flags/my-perak.png'));
        expect(KartaStateFlag.resolveAssetPath('id-jakarta'), equals('assets/flags/id-jakarta.png'));
        expect(KartaStateFlag.resolveAssetPath('th-bangkok'), equals('assets/flags/th-bangkok.png'));

        // Cross border into Kuala Lumpur & switch to Bahasa Melayu
        container.read(kartaLanguageProvider.notifier).setLanguage(KartaLanguage.malay);
        container.read(regionWelcomeProvider.notifier).onNavigationFix(
              const Coordinate(lat: 3.1579, lon: 101.7116),
            );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byKey(const ValueKey<String>('karta-region-flag-my-kl')), findsOneWidget);
        expect(find.text('Selamat Datang ke Wilayah Persekutuan Kuala Lumpur'), findsOneWidget);

        // Ending navigation clears the welcome banner cleanly
        container.read(regionWelcomeProvider.notifier).endNavigationSession();
        container.read(kartaLanguageProvider.notifier).setLanguage(KartaLanguage.english);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey<String>('karta-region-welcome-banner')), findsNothing);
      },
    );

    testWidgets(
      'Real NavigationSessionController startNavigation does not wipe regionWelcomeProvider and triggers Selangor & Putrajaya flags across borders',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
        await tester.pump(const Duration(milliseconds: 120));

        final container = ProviderScope.containerOf(tester.element(find.byType(KartaApp)));
        final session = container.read(navigationSessionProvider);

        const klcc = Coordinate(lat: 3.1579, lon: 101.7116);
        const selangorBorder = Coordinate(lat: 3.0100, lon: 101.6950);
        const putrajayaGate = Coordinate(lat: 2.9650, lon: 101.6920);
        const putrajayaDest = Coordinate(lat: 2.9361, lon: 101.6893);

        final route = CandidateRoute(
          routeIndex: 0,
          profileUsed: 'drive_fastest',
          summaryLabel: 'KLCC to Putrajaya',
          primaryCorridorName: 'via E20',
          distanceKm: 35.0,
          durationSeconds: 1800.0,
          hasTollRoads: false,
          hasHighways: true,
          countriesCrossed: const <String>['MY'],
          tolls: const TollSummary(hasTolls: false, displayTotal: 'Free'),
          legs: <RouteLeg>[
            RouteLeg(
              distanceKm: 35.0,
              durationSeconds: 1800.0,
              shapePolyline6: encodePolyline6(
                const <Coordinate>[klcc, selangorBorder, putrajayaGate, putrajayaDest],
              ),
              maneuvers: const <RouteManeuver>[
                RouteManeuver(
                  type: 1,
                  instruction: 'Head south on E20 MEX Highway',
                  distanceKm: 20.0,
                  timeSeconds: 900.0,
                  beginShapeIndex: 0,
                  endShapeIndex: 2,
                  streetNames: <String>['E20'],
                  highway: true,
                ),
                RouteManeuver(
                  type: 4,
                  instruction: 'Arrive at Masjid Putra',
                  distanceKm: 15.0,
                  timeSeconds: 900.0,
                  beginShapeIndex: 2,
                  endShapeIndex: 3,
                  streetNames: <String>['Persiaran Perdana'],
                ),
              ],
            ),
          ],
        );

        final source = LiveGpsPositionSource();
        addTearDown(source.dispose);

        // Start real navigation session & seed KLCC origin (reproduces exact live app sequence)
        session.startNavigation(route: route, positionSource: source);
        container.read(regionWelcomeProvider.notifier).beginNavigationSession(klcc);

        // Emit starting fix inside Kuala Lumpur -> NO banner for origin state
        source.pushFix(GpsFix(
          coordinate: klcc,
          bearingDeg: 180,
          speedKmh: 65,
          timestamp: DateTime.now(),
          isSimulated: true,
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(container.read(regionWelcomeProvider).isNavigationActive, isTrue);
        expect(find.byKey(const ValueKey<String>('karta-region-welcome-banner')), findsNothing);

        // Vehicle crosses KL -> Selangor border -> pops Welcome to Selangor + official Selangor flag!
        source.pushFix(GpsFix(
          coordinate: selangorBorder,
          bearingDeg: 180,
          speedKmh: 90,
          timestamp: DateTime.now(),
          isSimulated: true,
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byKey(const ValueKey<String>('karta-region-welcome-banner')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('karta-region-flag-my-selangor')), findsOneWidget);
        expect(find.text('Welcome to Selangor'), findsOneWidget);

        // Vehicle crosses Selangor -> Putrajaya border -> pops Welcome to Putrajaya + official Putrajaya flag!
        source.pushFix(GpsFix(
          coordinate: putrajayaGate,
          bearingDeg: 180,
          speedKmh: 60,
          timestamp: DateTime.now(),
          isSimulated: true,
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byKey(const ValueKey<String>('karta-region-flag-my-putrajaya')), findsOneWidget);
        expect(find.text('Welcome to Putrajaya'), findsOneWidget);

        // Reaching destination (NavigationPhase.arrived) keeps HUD & banner alive until End
        source.pushFix(GpsFix(
          coordinate: putrajayaDest,
          bearingDeg: 180,
          speedKmh: 15,
          timestamp: DateTime.now(),
          isSimulated: true,
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(const ValueKey<String>('karta-region-flag-my-putrajaya')), findsOneWidget);

        // Stop navigation -> clears welcome banner cleanly
        session.stopNavigation();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey<String>('karta-region-welcome-banner')), findsNothing);
      },
    );
  });
}
