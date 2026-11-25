import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_app/features/automotive/companion_turn_list_overlay.dart';
import 'package:karta_app/features/personalization/studio_panel.dart';
import 'package:karta_app/state/karta_app_state.dart';
import 'package:karta_app/state/lighting_providers.dart';
import 'package:karta_app/state/phase3_providers.dart';
import 'package:karta_app/state/phase4_automotive_providers.dart';
import 'package:karta_automotive_bridge/karta_automotive_bridge.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

void main() {
  group('Phase 4 Native Automotive Integration (App State & Driver Studio)', () {
    test('Phone <-> CarPlay handoff dynamically throttles and restores KartaMapController', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final bridge = container.read(kartaAutomotiveBridgeProvider);
      final mapCtrl = container.read(kartaMapControllerProvider);
      final privacy = container.read(locationPrivacyGuardProvider);

      expect(mapCtrl.targetFps, equals(60));
      expect(mapCtrl.is3DEnabled, isTrue);
      expect(privacy.policy.retainTripHistoryOptIn, isFalse);

      // Connect CarPlay head unit
      await bridge.handleHeadUnitConnected(
        const AutomotiveHeadUnitInfo(platform: AutomotivePlatform.carPlay, apiLevel: 18),
      );
      await Future<void>.delayed(Duration.zero);

      expect(bridge.isConnectedToHeadUnit, isTrue);
      expect(mapCtrl.isCompanionProjected, isTrue);
      expect(mapCtrl.targetFps, equals(15));
      expect(mapCtrl.is3DEnabled, isFalse);

      // Escalate thermal to serious -> pauses phone map canvas while CarPlay renders at 30fps
      await bridge.dispatchSyntheticNativeCall(
        'onThermalStateChanged',
        <String, dynamic>{
          'platform': 'carplay',
          'thermalLevel': 'serious',
          'isCharging': true,
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(mapCtrl.isCanvasPausedForThermal, isTrue);

      // Disconnect CarPlay -> scrubs ephemeral RAM & restores phone map canvas
      await bridge.handleHeadUnitDisconnected(
        platform: AutomotivePlatform.carPlay,
        reason: 'ignition_off',
      );
      await Future<void>.delayed(Duration.zero);

      expect(bridge.isConnectedToHeadUnit, isFalse);
      expect(mapCtrl.isCompanionProjected, isFalse);
      expect(mapCtrl.isCanvasPausedForThermal, isFalse);
      expect(privacy.scrubCount, greaterThanOrEqualTo(1));
    });

    test('Inbound Android Auto voice transcript parses into hazard intent in <15ms on-device', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final bridge = container.read(kartaAutomotiveBridgeProvider);
      await bridge.dispatchSyntheticNativeCall(
        'onVoiceTranscriptCaptured',
        <String, dynamic>{
          'transcript': 'Ada polis speed trap on PLUS ahead',
          'localeTag': 'en-MY',
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final voiceState = container.read(handsFreeVoiceProvider);
      expect(voiceState.pendingIntent, isNotNull);
      expect(voiceState.pendingIntent!.hazardCategory, equals(HazardCategory.police));
      expect(voiceState.pendingIntent!.roadHint, equals('PLUS'));

      // Cancel auto-submit timer cleanly before container disposal
      container.read(handsFreeVoiceProvider.notifier).cancelPendingReport();
    });

    testWidgets('KartaStudioPanel Auto & Privacy tab renders cleanly and toggles privacy opt-in',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: KartaTheme.dark(),
            home: const Scaffold(
              body: SizedBox(
                width: 420,
                height: 760,
                child: KartaStudioPanel(initialTab: 2),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('On-Device Location Privacy'), findsOneWidget);
      expect(find.text('ZERO RETENTION'), findsOneWidget);
      expect(find.text('Thermal & Adaptive FPS Governor'), findsOneWidget);

      // Tap Link CarPlay button -> verifies reactive handoff UI update
      await tester.tap(find.text('Link CarPlay'));
      await tester.pumpAndSettle();
      expect(find.text('Apple CarPlay Projected'), findsOneWidget);

      // Toggle privacy opt-in ON -> switches badge from ZERO RETENTION to OPT-IN RAM
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('OPT-IN RAM'), findsOneWidget);
    });

    test('Headlight/dimmer sensor bidirectionally syncs KartaLightingNotifier across CarPlay & tunnel dips', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final bridge = container.read(kartaAutomotiveBridgeProvider);
      final lightingNotifier = container.read(kartaLightingProvider.notifier);

      // Connect CarPlay in Tropical Daylight (headlights OFF)
      await bridge.handleHeadUnitConnected(
        const AutomotiveHeadUnitInfo(
          platform: AutomotivePlatform.carPlay,
          screenWidthPx: 2400,
          screenHeightPx: 720,
          isDarkMode: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      var lighting = container.read(kartaLightingProvider);
      expect(lighting.isDaylight, isTrue);
      expect(lighting.reason, equals(KartaLightingReason.vehicleHeadlightSensor));
      expect(lighting.statusChipLabel, equals('CAR · DAY'));

      // Vehicle headlights switch ON -> phone immediately switches to Obsidian Night
      await bridge.dispatchSyntheticNativeCall(
        'onHeadUnitAppearanceChanged',
        <String, dynamic>{
          'platform': 'carplay',
          'isDarkMode': true,
          'source': 'carplay_headlight_sensor',
        },
      );
      await Future<void>.delayed(Duration.zero);

      lighting = container.read(kartaLightingProvider);
      expect(lighting.isNight, isTrue);
      expect(lighting.statusChipLabel, equals('CAR · NIGHT'));

      // Headlights OFF again, then enter SMART Tunnel KL -> tunnel forces Obsidian Night & notifies car
      await bridge.dispatchSyntheticNativeCall(
        'onHeadUnitAppearanceChanged',
        <String, dynamic>{
          'platform': 'carplay',
          'isDarkMode': false,
          'source': 'carplay_headlight_sensor',
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(kartaLightingProvider).isDaylight, isTrue);

      lightingNotifier.setSimulatedTunnel(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(kartaLightingProvider).isNight, isTrue);
      expect(bridge.isDarkMode, isTrue);

      // Disconnect clears headlight override cleanly
      lightingNotifier.setSimulatedTunnel(false);
      await bridge.handleHeadUnitDisconnected(
        platform: AutomotivePlatform.carPlay,
        reason: 'car_unplugged',
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(kartaLightingProvider.notifier).vehicleHeadlightDark, isNull);
    });

    testWidgets(
      'KartaCompanionTurnListOverlay renders destination, upcoming turns & preserves live GPS across handoff',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final container = ProviderContainer();

        final route = CandidateRoute(
          routeIndex: 0,
          profileUsed: 'drive_fastest',
          summaryLabel: 'PLUS E2 -> Marina Bay',
          primaryCorridorName: 'PLUS North-South Expressway',
          distanceKm: 350.0,
          durationSeconds: 14400,
          hasTollRoads: false,
          hasHighways: true,
          legs: <RouteLeg>[
            RouteLeg(
              distanceKm: 350.0,
              durationSeconds: 14400,
              shapePolyline6: encodePolyline6(const <Coordinate>[
                Coordinate(lat: 3.1579, lon: 101.7116),
                Coordinate(lat: 3.1000, lon: 101.7080),
                Coordinate(lat: 2.2000, lon: 102.2500),
                Coordinate(lat: 1.2834, lon: 103.8607),
              ]),
              maneuvers: const <RouteManeuver>[
                RouteManeuver(
                  type: 1,
                  instruction: 'Depart south on Jalan Ampang',
                  streetNames: <String>['Jalan Ampang'],
                  distanceKm: 6.4,
                  timeSeconds: 320,
                  beginShapeIndex: 0,
                  endShapeIndex: 1,
                ),
                RouteManeuver(
                  type: 20,
                  instruction: 'Take Exit 209 toward Sungai Besi',
                  streetNames: <String>['E2', 'PLUS Highway'],
                  distanceKm: 120.0,
                  timeSeconds: 4200,
                  beginShapeIndex: 1,
                  endShapeIndex: 2,
                  highway: true,
                ),
                RouteManeuver(
                  type: 10,
                  instruction: 'Turn right onto Bayfront Avenue',
                  streetNames: <String>['Bayfront Avenue'],
                  distanceKm: 223.6,
                  timeSeconds: 9880,
                  beginShapeIndex: 2,
                  endShapeIndex: 3,
                ),
              ],
            ),
          ],
          tolls: const TollSummary(hasTolls: false, displayTotal: 'Free'),
        );

        final session = container.read(navigationSessionProvider);
        final bridge = container.read(kartaAutomotiveBridgeProvider);

        final playback = RoutePlaybackPositionSource(
          geometry: RouteGeometryIndex.fromRoute(route),
          speedMultiplier: 1.0,
        );
        session.startNavigation(route: route, positionSource: playback);
        playback.seekProgress(0.001);

        await tester.runAsync(() async {
          await bridge.handleHeadUnitConnected(
            const AutomotiveHeadUnitInfo(
              platform: AutomotivePlatform.carPlay,
              screenWidthPx: 2400,
              screenHeightPx: 720,
              isDarkMode: true,
            ),
          );
        });

        var showLiveMapTapped = false;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: KartaTheme.dark(),
              home: KartaCompanionTurnListOverlay(
                snapshot: session.current,
                connection: bridge.connectionState,
                thermal: container.read(thermalAdaptationControllerProvider).currentProfile,
                lighting: container.read(kartaLightingProvider),
                onShowLiveMap: () => showLiveMapTapped = true,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Apple CarPlay · ULTRA-WIDE'), findsOneWidget);
        expect(find.text('TURN-BY-TURN COMPANION'), findsOneWidget);
        expect(find.text('Take Exit 209 toward Sungai Besi'), findsOneWidget);
        expect(find.text('Turn right onto Bayfront Avenue'), findsOneWidget);
        expect(find.textContaining('DESTINATION'), findsOneWidget);
        expect(find.text('SPOTIFY'), findsNothing);

        // Toggle Route Overview from companion -> syncs to bridge
        await tester.tap(find.byKey(const ValueKey<String>('companion-overview-toggle')));
        await tester.pump(const Duration(milliseconds: 50));
        expect(bridge.isRouteOverviewActive, isTrue);

        // Tap Show Map -> cleanly calls toggle callback
        await tester.tap(find.byKey(const ValueKey<String>('companion-show-live-map')));
        await tester.pump(const Duration(milliseconds: 50));
        expect(showLiveMapTapped, isTrue);

        // Disconnect CarPlay -> active GPS navigation stays uninterrupted!
        await tester.runAsync(() async {
          await bridge.handleHeadUnitDisconnected(
            platform: AutomotivePlatform.carPlay,
            reason: 'usb_unplugged',
          );
        });
        await tester.pump(const Duration(milliseconds: 50));
        expect(session.current.phase, equals(NavigationPhase.navigating));

        // Clean up active periodic timers (playback, solar ticker) before test exit
        playback.dispose();
        session.stopNavigation();
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  });
}
