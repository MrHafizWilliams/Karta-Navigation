import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import 'package:test/test.dart';

void main() {
  group('SolarTunnelLightingEngine', () {
    const penangBridge = Coordinate(lat: 5.3540, lon: 100.3465);

    test('resolves High-Glare Tropical Daylight on Penang Bridge at midday noon (12:30 MYT / 04:30 UTC)', () {
      final engine = SolarTunnelLightingEngine();
      final state = engine.resolve(
        preference: KartaLightingPreference.auto,
        coordinate: penangBridge,
        nowUtc: DateTime.utc(2026, 11, 22, 4, 30),
        isInTunnel: false,
      );
      expect(state.solarElevationDeg, greaterThan(45.0));
      expect(state.resolvedMode, equals(KartaVisualMode.tropicalDaylight));
      expect(state.reason, equals(KartaLightingReason.solarDaytime));
    });

    test('resolves Obsidian Night on Penang Bridge at midnight (00:30 MYT / 16:30 UTC)', () {
      final engine = SolarTunnelLightingEngine();
      final state = engine.resolve(
        preference: KartaLightingPreference.auto,
        coordinate: penangBridge,
        nowUtc: DateTime.utc(2026, 11, 22, 16, 30),
        isInTunnel: false,
      );
      expect(state.solarElevationDeg, lessThan(-40.0));
      expect(state.resolvedMode, equals(KartaVisualMode.obsidianNight));
      expect(state.reason, equals(KartaLightingReason.solarNighttime));
    });

    test('dips to Obsidian Night inside tunnels during noon and holds 4s anti-flicker hysteresis on exit', () {
      final engine = SolarTunnelLightingEngine(tunnelExitHysteresis: const Duration(seconds: 4));
      final noon = DateTime.utc(2026, 11, 22, 4, 30);

      final inTunnel = engine.resolve(
        preference: KartaLightingPreference.auto,
        coordinate: penangBridge,
        nowUtc: noon,
        isInTunnel: true,
      );
      expect(inTunnel.resolvedMode, equals(KartaVisualMode.obsidianNight));
      expect(inTunnel.reason, equals(KartaLightingReason.tunnelOverride));

      final justExited = engine.resolve(
        preference: KartaLightingPreference.auto,
        coordinate: penangBridge,
        nowUtc: noon.add(const Duration(seconds: 2)),
        isInTunnel: false,
      );
      expect(justExited.resolvedMode, equals(KartaVisualMode.obsidianNight));
      expect(justExited.tunnelHoldActive, isTrue);

      final fullyExited = engine.resolve(
        preference: KartaLightingPreference.auto,
        coordinate: penangBridge,
        nowUtc: noon.add(const Duration(seconds: 5)),
        isInTunnel: false,
      );
      expect(fullyExited.resolvedMode, equals(KartaVisualMode.tropicalDaylight));
      expect(fullyExited.tunnelHoldActive, isFalse);
    });
  });

  group('CameraPhysicsModel', () {
    test('tilts pitch steeper and zooms out smoothly from 30 km/h city to 110 km/h NSE highway', () {
      final city = CameraPhysicsModel.computeTarget(speedKmh: 30, is3DEnabled: true);
      final mid = CameraPhysicsModel.computeTarget(speedKmh: 70, is3DEnabled: true);
      final highway = CameraPhysicsModel.computeTarget(speedKmh: 110, is3DEnabled: true);

      expect(city.zoom, closeTo(17.6, 0.01));
      expect(city.pitchDeg, closeTo(48.0, 0.01));
      expect(city.declutterMinorLabels, isFalse);

      expect(mid.zoom, lessThan(city.zoom));
      expect(mid.pitchDeg, greaterThan(city.pitchDeg));
      expect(mid.declutterMinorLabels, isTrue);

      expect(highway.zoom, closeTo(15.0, 0.01));
      expect(highway.pitchDeg, closeTo(66.0, 0.01));
      expect(highway.declutterMinorLabels, isTrue);
    });

    test('eases zoom inward when approaching a turn maneuver within 350 m', () {
      final cruise = CameraPhysicsModel.computeTarget(speedKmh: 100, is3DEnabled: true);
      final approachingTurn = CameraPhysicsModel.computeTarget(
        speedKmh: 100,
        is3DEnabled: true,
        distanceToManeuverMeters: 100,
      );
      expect(approachingTurn.zoom, greaterThan(cruise.zoom));
      expect(approachingTurn.pitchDeg, lessThan(cruise.pitchDeg));
    });
  });
}
