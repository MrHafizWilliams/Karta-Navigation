import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_offline_routing/karta_offline_routing.dart';
import 'package:test/test.dart';

void main() {
  test('OfflineRegionManager groups MY/SG/BN regional packs into 3 Country Bundles', () async {
    final mockHttp = MockClient((req) async {
      if (req.url.path == '/v1/regions') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'count': 6,
            'regions': <Map<String, dynamic>>[
              _packJson('my-peninsular-north', 'Malaysia — North', <String>['MY'], 120000000),
              _packJson('my-peninsular-central', 'Malaysia — Central', <String>['MY'], 95000000),
              _packJson('my-peninsular-south', 'Malaysia — South', <String>['MY', 'SG'], 70000000),
              _packJson('my-borneo', 'Malaysia — Borneo', <String>['MY', 'BN'], 85000000),
              _packJson('sg', 'Singapore', <String>['SG', 'MY'], 42000000),
              _packJson('bn', 'Brunei Darussalam', <String>['BN', 'MY'], 18000000),
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('Not Found', 404);
    });

    final api = KartaApiClient(baseUrl: 'http://localhost:8000', httpClient: mockHttp);
    final mgr = OfflineRegionManager(apiClient: api, httpClient: mockHttp);

    await mgr.refreshCatalog();
    final countries = mgr.groupedByCountry();

    expect(countries.length, equals(3));
    expect(countries[0].countryCode, equals('MY'));
    expect(countries[0].regions.length, equals(4));
    expect(countries[1].countryCode, equals('SG'));
    expect(countries[1].regions.length, equals(1));
    expect(countries[2].countryCode, equals('BN'));
    expect(countries[2].regions.length, equals(1));

    mgr.dispose();
    api.close();
  });
}

Map<String, dynamic> _packJson(String id, String name, List<String> codes, int bytes) =>
    <String, dynamic>{
      'region_id': id,
      'display_name': name,
      'country_codes': codes,
      'bbox': <String, double>{
        'min_lon': 100.0,
        'min_lat': 1.0,
        'max_lon': 104.0,
        'max_lat': 6.0,
      },
      'data_version': '2026-11-21',
      'pmtiles_url': 'http://localhost:8081/$id.pmtiles',
      'pmtiles_sha256': '0' * 64,
      'pmtiles_bytes': bytes,
      'valhalla_tar_url': 'http://localhost:8000/v1/regions/downloads/$id/valhalla_tiles.tar',
      'valhalla_tar_sha256': '0' * 64,
      'valhalla_tar_bytes': 1024,
      'tolls_sqlite_url': 'http://localhost:8000/v1/regions/downloads/$id/tolls_$id.sqlite',
      'tolls_sqlite_sha256': '0' * 64,
      'tolls_sqlite_bytes': 512,
      'updated_at': '2026-11-21T12:00:00Z',
    };
