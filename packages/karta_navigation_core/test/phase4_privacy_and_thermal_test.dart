import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import 'package:test/test.dart';

void main() {
  group('LocationPrivacyGuard (Strict Zero-Retention Default)', () {
    test('retains zero raw GPS history by default across live navigation fixes', () {
      var now = DateTime(2026, 11, 22, 13, 0, 0);
      final guard = LocationPrivacyGuard(clock: () => now);

      expect(guard.policy.retainTripHistoryOptIn, isFalse);
      expect(guard.auditSnapshot.mapLibreTelemetryDisabled, isTrue);

      for (var i = 0; i < 25; i++) {
        now = now.add(const Duration(seconds: 1));
        guard.processLiveFix(
          GpsFix(
            coordinate: Coordinate(lat: 3.1579 + i * 0.0002, lon: 101.7116 + i * 0.0002),
            bearingDeg: 145.0,
            speedKmh: 88.0,
            timestamp: now,
          ),
        );
      }

      // Single volatile fix exists for live navigation, but zero history is stored.
      expect(guard.liveVolatileFix, isNotNull);
      expect(guard.retainedHistory, isEmpty);
      expect(guard.auditSnapshot.retainedHistoryCount, equals(0));
    });

    test('scrubEphemeralState clears volatile fix and rotates anonymous session token', () {
      var now = DateTime(2026, 11, 22, 13, 10, 0);
      final guard = LocationPrivacyGuard(clock: () => now);
      final initialToken = guard.ephemeralSessionToken;

      guard.processLiveFix(
        GpsFix(
          coordinate: const Coordinate(lat: 1.2834, lon: 103.8607),
          bearingDeg: 90.0,
          speedKmh: 62.0,
          timestamp: now,
        ),
      );
      expect(guard.auditSnapshot.hasLiveVolatileFix, isTrue);

      now = now.add(const Duration(minutes: 2));
      guard.scrubEphemeralState();

      expect(guard.liveVolatileFix, isNull);
      expect(guard.auditSnapshot.hasLiveVolatileFix, isFalse);
      expect(guard.scrubCount, equals(1));
      expect(guard.ephemeralSessionToken, isNot(equals(initialToken)));
    });

    test('opt-in trip history buffers bounded samples and revoking immediately purges RAM', () {
      final now = DateTime(2026, 11, 22, 14, 0, 0);
      final guard = LocationPrivacyGuard(
        policy: const LocationPrivacyPolicy.strictDefault().copyWith(
          maxOptInHistorySamples: 5,
        ),
        clock: () => now,
      );

      guard.setTripHistoryOptIn(true);
      for (var i = 0; i < 8; i++) {
        guard.processLiveFix(
          GpsFix(
            coordinate: Coordinate(lat: 4.8895 + i * 0.001, lon: 114.9392),
            bearingDeg: 0,
            speedKmh: 70,
            timestamp: now.add(Duration(seconds: i)),
          ),
        );
      }
      expect(guard.retainedHistory.length, equals(5));

      // Turning off opt-in immediately scrubs every retained breadcrumb
      guard.setTripHistoryOptIn(false);
      expect(guard.retainedHistory, isEmpty);
      expect(guard.auditSnapshot.retainedHistoryCount, equals(0));
    });

    test('quantizes coarse non-navigation coordinates and redacts logs', () {
      final guard = LocationPrivacyGuard();
      const raw = Coordinate(lat: 3.1579432, lon: 101.7116891);
      final coarse = guard.sanitizeForCoarseQuery(raw);

      expect(coarse, isNot(equals(raw)));
      expect(haversineMeters(raw, coarse), lessThan(450.0));

      final redacted = guard.redactDiagnosticMessage('Fix at 3.15794, 101.71168 snapped');
      expect(redacted, equals('Fix at <redacted-coord> snapped'));
    });

    test('NavigationSessionController automatically scrubs privacy guard on stopNavigation', () {
      final guard = LocationPrivacyGuard();
      final session = NavigationSessionController(
        apiClient: KartaApiClient(baseUrl: 'http://localhost:8000'),
        privacyGuard: guard,
      );

      final route = CandidateRoute(
        routeIndex: 0,
        profileUsed: 'drive_fastest',
        summaryLabel: 'PLUS E2',
        distanceKm: 12.0,
        durationSeconds: 600,
        hasTollRoads: true,
        hasHighways: true,
        legs: <RouteLeg>[
          RouteLeg(
            distanceKm: 12.0,
            durationSeconds: 600,
            shapePolyline6: encodePolyline6(const <Coordinate>[
              Coordinate(lat: 3.1579, lon: 101.7116),
              Coordinate(lat: 3.0500, lon: 101.7000),
            ]),
            maneuvers: const <RouteManeuver>[
              RouteManeuver(
                type: 8,
                instruction: 'Head south on PLUS E2',
                distanceKm: 12.0,
                timeSeconds: 600,
                beginShapeIndex: 0,
                endShapeIndex: 1,
              ),
            ],
          ),
        ],
        tolls: const TollSummary(hasTolls: true, displayTotal: 'RM 4.20'),
      );

      final playback = RoutePlaybackPositionSource(
        geometry: RouteGeometryIndex.fromRoute(route),
        speedMultiplier: 1.0,
      );

      session.startNavigation(route: route, positionSource: playback);
      playback.seekProgress(0.2);

      expect(guard.retainedHistory, isEmpty);
      expect(guard.scrubCount, equals(0));

      session.stopNavigation();
      expect(guard.liveVolatileFix, isNull);
      expect(guard.scrubCount, equals(1));

      playback.dispose();
      session.dispose();
      guard.dispose();
    });
  });

  group('ThermalAdaptationController (Adaptive FPS & Hysteresis)', () {
    test('throttles phone companion GPU on vehicle projection while keeping head unit at 60fps', () {
      final now = DateTime(2026, 11, 22, 13, 30, 0);
      final ctrl = ThermalAdaptationController(clock: () => now);

      expect(ctrl.currentProfile.phoneTargetFps, equals(60));
      expect(ctrl.currentProfile.enablePhone3DBuildings, isTrue);

      final projected = ctrl.setProjectedToHeadUnit(true, platform: 'carplay');
      expect(projected.headUnitTargetFps, equals(60));
      expect(projected.enableHeadUnit3DBuildings, isTrue);
      expect(projected.phoneTargetFps, equals(15));
      expect(projected.enablePhone3DBuildings, isFalse);
      expect(projected.pausePhoneMapCanvas, isFalse);

      // Disconnect restores phone 3D HUD & 60fps
      final restored = ctrl.setProjectedToHeadUnit(false);
      expect(restored.phoneTargetFps, equals(60));
      expect(restored.enablePhone3DBuildings, isTrue);

      ctrl.dispose();
    });

    test('escalates immediately across nominal -> fair -> serious -> critical and uses hysteresis on recovery', () {
      var now = DateTime(2026, 11, 22, 14, 0, 0);
      final ctrl = ThermalAdaptationController(
        clock: () => now,
        recoveryCooldown: const Duration(seconds: 20),
      );
      ctrl.setProjectedToHeadUnit(true, platform: 'android_auto');

      // Escalate to serious: immediate 30fps, 3D shed, phone canvas paused
      final serious = ctrl.updateTelemetry(
        ThermalTelemetryInput(
          deviceThermalLevel: DeviceThermalLevel.serious,
          isProjectedToHeadUnit: true,
          headUnitPlatform: 'android_auto',
          timestamp: now,
        ),
      );
      expect(serious.effectiveTier, equals(DeviceThermalLevel.serious));
      expect(serious.headUnitTargetFps, equals(30));
      expect(serious.enableHeadUnit3DBuildings, isFalse);
      expect(serious.pausePhoneMapCanvas, isTrue);
      expect(serious.roadContextPollIntervalMs, equals(5000));

      // Escalate to critical: immediate 20fps, flat 0° pitch, 8s poll
      final critical = ctrl.updateTelemetry(
        ThermalTelemetryInput(
          deviceThermalLevel: DeviceThermalLevel.critical,
          isProjectedToHeadUnit: true,
          headUnitPlatform: 'android_auto',
          timestamp: now.add(const Duration(seconds: 2)),
        ),
      );
      expect(critical.headUnitTargetFps, equals(20));
      expect(critical.headUnitCameraPitchDeg, equals(0.0));
      expect(critical.roadContextPollIntervalMs, equals(8000));

      // Cool back to nominal at +5s: must stay at critical due to 20s recovery cooldown
      now = now.add(const Duration(seconds: 5));
      final cooling1 = ctrl.updateTelemetry(
        ThermalTelemetryInput(
          deviceThermalLevel: DeviceThermalLevel.nominal,
          isProjectedToHeadUnit: true,
          headUnitPlatform: 'android_auto',
          timestamp: now,
        ),
      );
      expect(cooling1.effectiveTier, equals(DeviceThermalLevel.critical));

      // Sustained nominal after 21s cooldown: cleanly recovers to nominal 60fps
      now = now.add(const Duration(seconds: 21));
      final recovered = ctrl.updateTelemetry(
        ThermalTelemetryInput(
          deviceThermalLevel: DeviceThermalLevel.nominal,
          isProjectedToHeadUnit: true,
          headUnitPlatform: 'android_auto',
          timestamp: now,
        ),
      );
      expect(recovered.effectiveTier, equals(DeviceThermalLevel.nominal));
      expect(recovered.headUnitTargetFps, equals(60));
      expect(recovered.enableHeadUnit3DBuildings, isTrue);
      expect(recovered.pausePhoneMapCanvas, isFalse);

      ctrl.dispose();
    });

    test('proactively steps up thermal tier when charging with hot dashboard battery', () {
      final ctrl = ThermalAdaptationController();
      final p = ctrl.updateTelemetry(
        const ThermalTelemetryInput(
          deviceThermalLevel: DeviceThermalLevel.nominal,
          isCharging: true,
          batteryTempCelsius: 42.2,
          isProjectedToHeadUnit: true,
          headUnitPlatform: 'android_auto',
        ),
      );
      expect(p.effectiveTier, equals(DeviceThermalLevel.serious));
      expect(p.headUnitTargetFps, equals(30));
      expect(p.enableHeadUnit3DBuildings, isFalse);
      ctrl.dispose();
    });
  });

  group('SolarTunnelLightingEngine (Vehicle Headlight/Dimmer Sensor Sync)', () {
    test('follows vehicle headlight sensor in auto mode while keeping tunnel & manual priority', () {
      final engine = SolarTunnelLightingEngine();
      const klcc = Coordinate(lat: 3.1579, lon: 101.7116);
      // 12:30 PM MYT (04:30 UTC) — midday sun high above Kuala Lumpur
      final middayUtc = DateTime.utc(2026, 11, 22, 4, 30);

      // 1. Headlights ON at midday (e.g. heavy monsoon rain / multi-storey ramp) -> Obsidian Night
      final carNight = engine.resolve(
        preference: KartaLightingPreference.auto,
        coordinate: klcc,
        nowUtc: middayUtc,
        isInTunnel: false,
        vehicleHeadlightDark: true,
      );
      expect(carNight.resolvedMode, equals(KartaVisualMode.obsidianNight));
      expect(carNight.reason, equals(KartaLightingReason.vehicleHeadlightSensor));
      expect(carNight.vehicleHeadlightSynced, isTrue);
      expect(carNight.statusChipLabel, equals('CAR · NIGHT'));

      // 2. Headlights OFF -> Tropical Daylight
      final carDay = engine.resolve(
        preference: KartaLightingPreference.auto,
        coordinate: klcc,
        nowUtc: middayUtc,
        isInTunnel: false,
        vehicleHeadlightDark: false,
      );
      expect(carDay.resolvedMode, equals(KartaVisualMode.tropicalDaylight));
      expect(carDay.reason, equals(KartaLightingReason.vehicleHeadlightSensor));
      expect(carDay.statusChipLabel, equals('CAR · DAY'));

      // 3. Tunnel entry (SMART Tunnel KL) ALWAYS overrides daytime headlight sensor -> Obsidian Night
      final tunnelDip = engine.resolve(
        preference: KartaLightingPreference.auto,
        coordinate: klcc,
        nowUtc: middayUtc,
        isInTunnel: true,
        vehicleHeadlightDark: false,
      );
      expect(tunnelDip.resolvedMode, equals(KartaVisualMode.obsidianNight));
      expect(tunnelDip.reason, equals(KartaLightingReason.tunnelOverride));

      // 4. Manual override always takes top precedence
      final manualDay = engine.resolve(
        preference: KartaLightingPreference.day,
        coordinate: klcc,
        nowUtc: middayUtc,
        isInTunnel: false,
        vehicleHeadlightDark: true,
      );
      expect(manualDay.resolvedMode, equals(KartaVisualMode.tropicalDaylight));
      expect(manualDay.reason, equals(KartaLightingReason.manualDay));
    });
  });
}
