import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import 'package:test/test.dart';

void main() {
  group('RegionalVoiceIntentParser (EN / BM / Manglish / Singlish)', () {
    test('parses Malaysian Bahasa Melayu accident with lane and highway ref', () {
      final res = RegionalVoiceIntentParser.parse(
        'Hey Karta, ada kemalangan teruk lorong kanan on PLUS',
        locale: 'en-MY',
      );
      expect(res.intent, 'report_hazard');
      expect(res.hazardCategory, HazardCategory.accident);
      expect(res.severity, HazardSeverity.high);
      expect(res.laneHint, 'right_lane');
      expect(res.roadHint, 'PLUS');
      expect(res.direction, 'ahead');
      expect(res.confidence, greaterThanOrEqualTo(0.9));
    });

    test('parses opposite-side police roadblock and flash flood closure', () {
      final police = RegionalVoiceIntentParser.parse(
        'Lapor Karta sekatan jalan JPJ arah bertentangan',
      );
      expect(police.intent, 'report_hazard');
      expect(police.hazardCategory, HazardCategory.police);
      expect(police.direction, 'opposite');

      final flood = RegionalVoiceIntentParser.parse('Banjir kilat jalan tutup depan');
      expect(flood.intent, 'report_hazard');
      expect(flood.hazardCategory, HazardCategory.roadClosure);
      expect(flood.severity, HazardSeverity.high);
    });

    test('parses pothole, stalled vehicle, road debris, and voice control actions', () {
      expect(
        RegionalVoiceIntentParser.parse('Big pothole left lane').hazardCategory,
        HazardCategory.pothole,
      );
      expect(
        RegionalVoiceIntentParser.parse('Kereta rosak di lorong kecemasan').hazardCategory,
        HazardCategory.hiddenVehicle,
      );
      expect(
        RegionalVoiceIntentParser.parse('Pokok tumbang road debris on CTE').hazardCategory,
        HazardCategory.roadDebris,
      );
      expect(RegionalVoiceIntentParser.parse('Still there').intent, 'confirm_hazard');
      expect(RegionalVoiceIntentParser.parse('Dah clear').intent, 'clear_hazard');
      expect(RegionalVoiceIntentParser.parse('Accept reroute').intent, 'accept_reroute');
      expect(RegionalVoiceIntentParser.parse('Batal').intent, 'cancel');
    });
  });

  group('KartaVoicePackCatalog & NavigationSessionController live reroute', () {
    test('maps Valhalla maneuver types and hazard categories to the 12 custom cue slots', () {
      expect(KartaVoicePackCatalog.customCueSlots.length, 12);
      expect(KartaVoicePackCatalog.cueKeyForValhallaManeuver(15), 'turn_left');
      expect(KartaVoicePackCatalog.cueKeyForValhallaManeuver(10), 'turn_right');
      expect(KartaVoicePackCatalog.cueKeyForValhallaManeuver(26), 'roundabout');
      expect(KartaVoicePackCatalog.cueKeyForHazard(HazardCategory.police), 'hazard_police');
      expect(KartaVoicePackCatalog.cueKeyForHazard(HazardCategory.roadClosure), 'hazard_accident');

      final myPack = KartaVoicePackCatalog.builtInPacks.firstWhere((p) => p.id == 'karta_my_local');
      final formatted = KartaVoicePackCatalog.formatPromptForPack(
        myPack,
        'Toll plaza ahead',
        cueKey: 'toll_ahead',
      );
      expect(formatted, contains('RFID'));
    });

    test('applyLiveReroute swaps active route seamlessly without ending navigation', () {
      final api = KartaApiClient(baseUrl: 'http://localhost:8000');
      final session = NavigationSessionController(apiClient: api);
      final route1 = CandidateRoute(
        routeIndex: 0,
        profileUsed: 'drive_fastest',
        summaryLabel: 'Original',
        distanceKm: 12.0,
        durationSeconds: 900,
        hasTollRoads: false,
        hasHighways: true,
        legs: <RouteLeg>[
          RouteLeg(
            distanceKm: 12.0,
            durationSeconds: 900,
            shapePolyline6: encodePolyline6(const <Coordinate>[
              Coordinate(lat: 3.1579, lon: 101.7116),
              Coordinate(lat: 3.1200, lon: 101.7116),
            ]),
            maneuvers: const <RouteManeuver>[
              RouteManeuver(
                type: 8,
                instruction: 'Head south on AKLEH',
                distanceKm: 12.0,
                timeSeconds: 900,
                beginShapeIndex: 0,
                endShapeIndex: 1,
              ),
            ],
          ),
        ],
        tolls: const TollSummary(hasTolls: false, displayTotal: 'Free'),
      );

      final detour = CandidateRoute(
        routeIndex: 0,
        profileUsed: 'drive_fastest',
        summaryLabel: 'Detour via DUKE',
        distanceKm: 13.4,
        durationSeconds: 660,
        hasTollRoads: true,
        hasHighways: true,
        legs: <RouteLeg>[
          RouteLeg(
            distanceKm: 13.4,
            durationSeconds: 660,
            shapePolyline6: encodePolyline6(const <Coordinate>[
              Coordinate(lat: 3.1579, lon: 101.7116),
              Coordinate(lat: 3.1350, lon: 101.7250),
              Coordinate(lat: 3.1200, lon: 101.7116),
            ]),
            maneuvers: const <RouteManeuver>[
              RouteManeuver(
                type: 10,
                instruction: 'Turn right onto DUKE Highway',
                distanceKm: 13.4,
                timeSeconds: 660,
                beginShapeIndex: 0,
                endShapeIndex: 2,
              ),
            ],
          ),
        ],
        tolls: const TollSummary(hasTolls: true, displayTotal: 'RM 2.50'),
      );

      final playback = RoutePlaybackPositionSource(
        geometry: RouteGeometryIndex.fromRoute(route1),
      );
      session.startNavigation(route: route1, positionSource: playback);
      expect(session.current.phase, NavigationPhase.navigating);
      expect(session.current.activeRoute?.summaryLabel, 'Original');

      session.applyLiveReroute(detour);
      expect(session.current.phase, NavigationPhase.navigating);
      expect(session.current.activeRoute?.summaryLabel, 'Detour via DUKE');
      expect(session.current.currentManeuver?.instruction, 'Turn right onto DUKE Highway');

      playback.dispose();
      session.dispose();
      api.close();
    });
  });
}
