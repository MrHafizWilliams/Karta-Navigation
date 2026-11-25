import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_app/features/hazards/radial_hazard_menu.dart';
import 'package:karta_app/features/navigation/active_navigation_hud.dart';
import 'package:karta_app/main.dart';
import 'package:karta_app/state/karta_app_state.dart';
import 'package:karta_app/state/lighting_providers.dart';
import 'package:karta_app/state/phase3_providers.dart';
import 'package:karta_design_system/karta_design_system.dart';
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

            await tester.pumpWidget(const ProviderScope(child: KartaApp()));
            await tester.pump(const Duration(milliseconds: 120));

            final container = ProviderScope.containerOf(tester.element(find.byType(KartaApp)));
            container.read(kartaLightingProvider.notifier).setPreference(mode);
            await tester.pump(const Duration(milliseconds: 180));

            final label = '${vp.name} [${mode.name}] Explore';
            expect(tester.takeException(), isNull, reason: '$label threw an exception');

            // Verify Navigation Chrome Architecture:
            // Medium (Tablet & Standard Auto) + Expanded (Desktop & Wide Auto) => persistent left rail
            // Compact (Smartphone < 640dp) => distinct compact bottom tab bar
            if (vp.expectLeftRail) {
              expect(find.text('KARTA'), findsOneWidget, reason: '$label must show persistent left nav rail');
              final toggleFinder = find.byKey(const ValueKey<String>('karta-sidebar-toggle'));
              expect(toggleFinder, findsOneWidget);
              final toggleSize = tester.getSize(toggleFinder);
              expect(toggleSize.width, greaterThanOrEqualTo(48.0), reason: '$label sidebar toggle >= 48dp');
              expect(toggleSize.height, greaterThanOrEqualTo(48.0), reason: '$label sidebar toggle >= 48dp');
            } else {
              expect(find.text('KARTA'), findsNothing, reason: '$label smartphone must NOT show desktop nav rail');
              expect(find.text('Navigate'), findsOneWidget);
              expect(find.text('Offline'), findsOneWidget);
              expect(find.text('Vehicle'), findsOneWidget);
            }

            // Core branding & feature removals verified
            expect(find.text('Karta Navigation'), findsOneWidget, reason: '$label title');
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
                child: const KartaApp(),
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

        await tester.pumpWidget(const ProviderScope(child: KartaApp()));
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

        await tester.pumpWidget(const ProviderScope(child: KartaApp()));
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
  });
}
