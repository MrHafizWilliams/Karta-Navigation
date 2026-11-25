import 'package:karta_api_client/karta_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('RealtimeFrame parses hazard.alert and route.reroute_proposal frames', () {
    final alertFrame = RealtimeFrame.parse(<String, dynamic>{
      'event_type': 'hazard.alert',
      'hazard': <String, dynamic>{
        'id': 'haz-101',
        'category': 'police',
        'severity': 'medium',
        'status': 'active',
        'coordinate': <String, dynamic>{'lat': 3.1579, 'lon': 101.7116},
        'road_ref': 'E1',
        'confirmations': 3,
        'distance_meters': 640.5,
        'on_active_route': true,
        'created_at': '2026-11-22T01:00:00Z',
        'expires_at': '2026-11-22T01:45:00Z',
      },
    });
    expect(alertFrame.eventType, 'hazard.alert');
    expect(alertFrame.hazard?.category, HazardCategory.police);
    expect(alertFrame.hazard?.onActiveRoute, isTrue);
    expect(alertFrame.hazard?.confirmations, 3);
  });

  test('FuelGrade resolves MY (RON95/97/Diesel), SG (92/95/98/Diesel), and BN grades', () {
    final myGrades = FuelGrade.gradesForCountry('MY');
    final sgGrades = FuelGrade.gradesForCountry('SG');
    final bnGrades = FuelGrade.gradesForCountry('BN');

    expect(myGrades, containsAll(<FuelGrade>[FuelGrade.ron95, FuelGrade.ron97, FuelGrade.dieselB10]));
    expect(sgGrades, containsAll(<FuelGrade>[FuelGrade.octane92, FuelGrade.octane95, FuelGrade.octane98]));
    expect(bnGrades, contains(FuelGrade.ron97Bn));
  });

  test('KartaRealtimeClient builds ws:// URI from http:// API base', () {
    final client = KartaRealtimeClient(
      httpBaseUrl: 'http://localhost:8000',
      sessionId: 'test-sess',
    );
    final url = client.buildWsUri(
      initialCoord: const Coordinate(lat: 3.1579, lon: 101.7116),
      country: 'MY',
    );
    expect(url, startsWith('ws://localhost:8000/v1/realtime/ws?'));
    expect(url, contains('session_id=test-sess'));
    expect(url, contains('country=MY'));
  });
}
