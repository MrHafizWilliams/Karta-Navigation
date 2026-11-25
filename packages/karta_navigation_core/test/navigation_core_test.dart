import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import 'package:test/test.dart';

void main() {
  group('Polyline6 & Geometry', () {
    test('round-trips Penang -> KL -> Singapore coordinates accurately', () {
      const coords = <Coordinate>[
        Coordinate(lat: 5.4145, lon: 100.3298), // Penang
        Coordinate(lat: 3.1579, lon: 101.7116), // KLCC
        Coordinate(lat: 1.2834, lon: 103.8607), // Marina Bay
      ];
      final encoded = encodePolyline6(coords);
      final decoded = decodePolyline6(encoded);

      expect(decoded.length, equals(3));
      for (var i = 0; i < coords.length; i++) {
        expect(decoded[i].lat, closeTo(coords[i].lat, 1e-5));
        expect(decoded[i].lon, closeTo(coords[i].lon, 1e-5));
      }
    });

    test('shortest-arc bearing slerp wraps across 355 -> 10 deg cleanly', () {
      final mid = lerpBearingDeg(355.0, 10.0, 0.5);
      expect(mid, closeTo(2.5, 0.01));
    });
  });

  group('Regional Currency Formatter', () {
    test('formats MYR, SGD, and BND according to GEMINI.md rules', () {
      expect(RegionalCurrencyFormatter.formatMinor('MYR', 1480), equals('RM 14.80'));
      expect(RegionalCurrencyFormatter.formatMinor('SGD', 200), equals('\$2.00'));
      expect(RegionalCurrencyFormatter.formatMinor('BND', 300), equals('B\$3.00'));
    });
  });

  group('SpeedLimitMonitor', () {
    test('escalates normal -> caution -> alert correctly', () {
      final normal = SpeedLimitMonitor.evaluate(currentSpeedKmh: 108, roadSpeedLimitKmh: 110);
      expect(normal.severity, equals(SpeedAlertSeverity.normal));

      final caution = SpeedLimitMonitor.evaluate(currentSpeedKmh: 116, roadSpeedLimitKmh: 110);
      expect(caution.severity, equals(SpeedAlertSeverity.caution));
      expect(caution.overLimitByKmh, equals(6));

      final alert = SpeedLimitMonitor.evaluate(currentSpeedKmh: 124, roadSpeedLimitKmh: 110);
      expect(alert.severity, equals(SpeedAlertSeverity.alert));
      expect(alert.overLimitByKmh, equals(14));
    });
  });
}
