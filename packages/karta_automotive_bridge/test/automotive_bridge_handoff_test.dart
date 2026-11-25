import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_automotive_bridge/karta_automotive_bridge.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(KartaAutomotiveBridge.channelName);

  group('KartaAutomotiveBridge Bidirectional Handoff, Privacy & Thermal', () {
    late List<MethodCall> outboundCalls;

    setUp(() {
      outboundCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        outboundCalls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('performs seamless Phone -> CarPlay -> Phone handoff with full route/toll/lane sync & RAM scrub', () async {
      var now = DateTime(2026, 11, 22, 15, 0, 0);
      final privacy = LocationPrivacyGuard(clock: () => now);
      final thermal = ThermalAdaptationController(clock: () => now);
      final session = NavigationSessionController(
        apiClient: KartaApiClient(baseUrl: 'http://localhost:8000'),
        privacyGuard: privacy,
        thermalController: thermal,
      );
      final bridge = KartaAutomotiveBridge(
        channel: channel,
        privacyGuard: privacy,
        thermalController: thermal,
        enablePlatformChannel: true,
        clock: () => now,
      )..attachSession(session);

      // Prepare an active MY -> SG route before vehicle connects
      final route = CandidateRoute(
        routeIndex: 0,
        profileUsed: 'drive_fastest',
        summaryLabel: 'PLUS E2 -> CTE',
        distanceKm: 350.0,
        durationSeconds: 14400,
        hasTollRoads: true,
        hasHighways: true,
        legs: <RouteLeg>[
          RouteLeg(
            distanceKm: 350.0,
            durationSeconds: 14400,
            shapePolyline6: encodePolyline6(const <Coordinate>[
              Coordinate(lat: 3.1579, lon: 101.7116),
              Coordinate(lat: 1.2834, lon: 103.8607),
            ]),
            maneuvers: const <RouteManeuver>[
              RouteManeuver(
                type: 20,
                instruction: 'Take exit toward Sg Besi Toll Plaza',
                distanceKm: 1.2,
                timeSeconds: 60,
                beginShapeIndex: 0,
                endShapeIndex: 1,
                toll: true,
                highway: true,
              ),
            ],
          ),
        ],
        tolls: const TollSummary(hasTolls: true, displayTotal: 'RM 49.70 + \$2.00'),
      );

      final playback = RoutePlaybackPositionSource(
        geometry: RouteGeometryIndex.fromRoute(route),
        speedMultiplier: 1.0,
      );

      await bridge.updateActiveRoute(
        route: route,
        originName: 'KLCC',
        destinationName: 'Marina Bay Sands',
        destinationCoordinate: const Coordinate(lat: 1.2834, lon: 103.8607),
      );
      await bridge.updateOfflineMapConfig(
        const AutomotiveOfflineMapConfig(
          offlineModeEnabled: true,
          activePmtilesUrl: 'http://localhost:8081/my-sg-bn-full.pmtiles',
          downloadedRegions: <Map<String, dynamic>>[
            <String, dynamic>{
              'regionId': 'sg',
              'localPmtilesPath': '/offline/sg/sg.pmtiles',
              'verifiedSha256': true,
            },
          ],
        ),
      );

      session.startNavigation(route: route, positionSource: playback);
      playback.seekProgress(0.1);
      outboundCalls.clear();

      // 1. CarPlay connects mid-trip
      await bridge.dispatchSyntheticNativeCall(
        'onHeadUnitConnected',
        <String, dynamic>{
          'platform': 'carplay',
          'screenWidthPx': 1280,
          'screenHeightPx': 720,
          'densityScale': 2.0,
          'apiLevel': 18,
        },
      );

      expect(bridge.isConnectedToHeadUnit, isTrue);
      expect(bridge.connectionState.phase, equals(AutomotiveHandoffPhase.projectedActive));
      expect(bridge.connectionState.platform, equals(AutomotivePlatform.carPlay));
      expect(thermal.currentProfile.phoneTargetFps, equals(15));
      expect(thermal.currentProfile.headUnitTargetFps, equals(60));

      final syncCall = outboundCalls.firstWhere((c) => c.method == 'syncFullState');
      final env = syncCall.arguments as Map<Object?, Object?>;
      expect(env['retainTripHistoryOptIn'], isFalse);
      expect(env['disableMapTelemetry'], isTrue);
      final routeMap = env['routeGeometry'] as Map<Object?, Object?>;
      expect(routeMap['destinationName'], equals('Marina Bay Sands'));
      expect(routeMap['tollDisplayTotal'], equals('RM 49.70 + \$2.00'));
      final offlineMap = env['offlineConfig'] as Map<Object?, Object?>;
      expect(offlineMap['offlineModeEnabled'], isTrue);

      // 2. CarPlay disconnects mid-trip -> seamless Car -> Phone handoff
      outboundCalls.clear();
      await bridge.dispatchSyntheticNativeCall(
        'onHeadUnitDisconnected',
        <String, dynamic>{
          'platform': 'carplay',
          'reason': 'usb_unplugged',
          'lastSequenceId': bridge.lastSequenceId,
        },
      );

      expect(bridge.isConnectedToHeadUnit, isFalse);
      expect(bridge.connectionState.phase, equals(AutomotiveHandoffPhase.phoneOnly));
      expect(outboundCalls.any((c) => c.method == 'scrubEphemeralLocationState'), isTrue);
      // Phone GPU restored to 60fps & active navigation trip remains alive!
      expect(thermal.currentProfile.phoneTargetFps, equals(60));
      expect(session.current.phase, equals(NavigationPhase.navigating));

      playback.dispose();
      bridge.dispose();
      session.dispose();
      thermal.dispose();
      privacy.dispose();
    });

    test('dispatches inbound Android Auto quick hazard, voice transcript, reroute & thermal callbacks', () async {
      final now = DateTime(2026, 11, 22, 16, 0, 0);
      final thermal = ThermalAdaptationController(clock: () => now);
      final bridge = KartaAutomotiveBridge(
        channel: channel,
        thermalController: thermal,
        enablePlatformChannel: true,
        clock: () => now,
      );

      final received = <AutomotiveInboundEvent>[];
      final sub = bridge.inboundEvents.listen(received.add);

      await bridge.handleHeadUnitConnected(
        const AutomotiveHeadUnitInfo(platform: AutomotivePlatform.androidAuto, apiLevel: 7),
      );
      await bridge.dispatchSyntheticNativeCall(
        'onQuickReportHazard',
        <String, dynamic>{
          'category': 'pothole',
          'severity': 'medium',
          'oppositeSide': false,
          'source': 'android_auto',
        },
      );
      await bridge.dispatchSyntheticNativeCall(
        'onVoiceTranscriptCaptured',
        <String, dynamic>{
          'transcript': 'Banjir kilat depan on LDP',
          'localeTag': 'ms-MY',
        },
      );
      await bridge.dispatchSyntheticNativeCall(
        'onRerouteDecision',
        <String, dynamic>{
          'proposalId': 'reroute-42',
          'accepted': true,
        },
      );
      await bridge.dispatchSyntheticNativeCall(
        'onThermalStateChanged',
        <String, dynamic>{
          'platform': 'android_auto',
          'thermalLevel': 'serious',
          'batteryLevelPercent': 68,
          'isCharging': true,
          'batteryTempCelsius': 42.5,
          'isLowPowerMode': false,
        },
      );

      await Future<void>.delayed(Duration.zero);

      expect(received.whereType<QuickReportHazardEvent>().single.category, equals(HazardCategory.pothole));
      expect(
        received.whereType<VoiceReportTriggerEvent>().single.transcript,
        equals('Banjir kilat depan on LDP'),
      );
      expect(received.whereType<RerouteDecisionEvent>().single.accepted, isTrue);

      // Thermal state escalated immediately and pushed updated render profile back to native host
      expect(thermal.currentProfile.effectiveTier, equals(DeviceThermalLevel.serious));
      expect(thermal.currentProfile.headUnitTargetFps, equals(30));
      expect(outboundCalls.any((c) => c.method == 'applyThermalRenderProfile'), isTrue);

      await sub.cancel();
      bridge.dispose();
      thermal.dispose();
    });

    test('syncs vehicle headlight appearance, ultra-wide viewport class, and 3-action route overview', () async {
      final now = DateTime(2026, 11, 22, 17, 0, 0);
      final bridge = KartaAutomotiveBridge(
        channel: channel,
        enablePlatformChannel: true,
        clock: () => now,
      );

      final received = <AutomotiveInboundEvent>[];
      final sub = bridge.inboundEvents.listen(received.add);

      // Connect ultra-wide 2400x720 panoramic head unit in Tropical Daylight (headlights OFF)
      await bridge.dispatchSyntheticNativeCall(
        'onHeadUnitConnected',
        <String, dynamic>{
          'platform': 'android_auto',
          'screenWidthPx': 2400,
          'screenHeightPx': 720,
          'densityScale': 2.0,
          'apiLevel': 7,
          'isDarkMode': false,
        },
      );

      expect(bridge.connectionState.headUnitInfo?.viewportClass, equals(AutomotiveViewportClass.ultraWide));
      expect(bridge.isDarkMode, isFalse);

      // Headlights switch ON at dusk -> bridge receives HeadUnitAppearanceChangedEvent
      await bridge.dispatchSyntheticNativeCall(
        'onHeadUnitAppearanceChanged',
        <String, dynamic>{
          'platform': 'android_auto',
          'isDarkMode': true,
          'source': 'android_auto_headlight_sensor',
        },
      );
      await Future<void>.delayed(Duration.zero);

      expect(bridge.isDarkMode, isTrue);
      final appearanceEvent = received.whereType<HeadUnitAppearanceChangedEvent>().single;
      expect(appearanceEvent.isDarkMode, isTrue);
      expect(appearanceEvent.source, equals('android_auto_headlight_sensor'));

      // Phone tunnel dip or manual override pushes setVehicleAppearance back to head unit
      outboundCalls.clear();
      await bridge.setVehicleAppearance(false);
      expect(bridge.isDarkMode, isFalse);
      final setAppCall = outboundCalls.firstWhere((c) => c.method == 'setVehicleAppearance');
      expect((setAppCall.arguments as Map<Object?, Object?>)['isDarkMode'], isFalse);

      // Streamlined 3-action control flow: toggle_overview -> true, recenter -> false
      await bridge.dispatchSyntheticNativeCall(
        'onNavigationControlAction',
        <String, dynamic>{'action': 'toggle_overview'},
      );
      expect(bridge.isRouteOverviewActive, isTrue);

      await bridge.dispatchSyntheticNativeCall(
        'onNavigationControlAction',
        <String, dynamic>{'action': 'recenter'},
      );
      expect(bridge.isRouteOverviewActive, isFalse);

      await sub.cancel();
      bridge.dispose();
    });
  });
}
