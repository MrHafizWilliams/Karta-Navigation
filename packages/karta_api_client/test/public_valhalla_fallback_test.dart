import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:test/test.dart';

void main() {
  group('KartaApiClient automatic Public Valhalla & OSRM fallback', () {
    test('falls back to Public Valhalla when localhost backend is unreachable', () async {
      final mockClient = MockClient((http.Request req) async {
        if (req.url.host == 'localhost') {
          return http.Response('offline', 503);
        }
        if (req.url.host == 'valhalla1.openstreetmap.de' && req.url.path == '/route') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'trip': <String, dynamic>{
                'summary': <String, dynamic>{'length': 352.4, 'time': 12600},
                'legs': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'summary': <String, dynamic>{'length': 352.4, 'time': 12600},
                    'shape': 'gvrgIewuo~D_pR_pR',
                    'maneuvers': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'type': 1,
                        'instruction': 'Drive south on Lebuhraya Utara-Selatan (E1).',
                        'street_names': <String>['Lebuhraya Utara-Selatan', 'E1'],
                        'length': 340.0,
                        'time': 12000,
                        'begin_shape_index': 0,
                        'end_shape_index': 1,
                        'highway': true,
                      },
                    ],
                  },
                ],
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final client = KartaApiClient(
        baseUrl: 'http://localhost:8000',
        httpClient: mockClient,
      );

      final resp = await client.computeRoute(
        const RouteRequest(
          origin: Coordinate(lat: 5.3840, lon: 100.4128),
          destination: Coordinate(lat: 3.1579, lon: 101.7116),
        ),
      );

      expect(resp.routes, hasLength(1));
      expect(resp.routes.first.distanceKm, closeTo(352.4, 0.1));
      expect(resp.routes.first.primaryCorridorName, contains('Lebuhraya Utara-Selatan'));
      expect(resp.originCountry?.isoA2, equals('MY'));
      expect(resp.destinationCountry?.isoA2, equals('MY'));
    });

    test('falls back to Project OSRM when both localhost and Valhalla are unreachable', () async {
      final mockClient = MockClient((http.Request req) async {
        if (req.url.host == 'router.project-osrm.org') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'code': 'Ok',
              'routes': <Map<String, dynamic>>[
                <String, dynamic>{
                  'distance': 354200.0,
                  'duration': 13100.0,
                  'geometry': 'gvrgIewuo~D_pR_pR',
                  'legs': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'steps': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'distance': 354200.0,
                          'duration': 13100.0,
                          'name': 'PLUS North-South Expressway',
                          'ref': 'E1',
                          'maneuver': <String, dynamic>{
                            'type': 'depart',
                            'modifier': 'straight',
                          },
                        },
                      ],
                    },
                  ],
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response('unavailable', 503);
      });

      final client = KartaApiClient(
        baseUrl: 'http://localhost:8000',
        httpClient: mockClient,
      );

      final resp = await client.computeRoute(
        const RouteRequest(
          origin: Coordinate(lat: 5.3840, lon: 100.4128),
          destination: Coordinate(lat: 3.1579, lon: 101.7116),
        ),
      );

      expect(resp.routes, hasLength(1));
      expect(resp.routes.first.distanceKm, closeTo(354.2, 0.1));
      expect(resp.routes.first.primaryCorridorName, contains('PLUS North-South Expressway'));
    });
  });
}
