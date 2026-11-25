import 'package:karta_api_client/karta_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('RouteResponse parses real Penang -> KL -> Singapore multi-currency toll JSON', () {
    final sample = <String, dynamic>{
      'origin_country': <String, dynamic>{
        'iso_a2': 'MY',
        'name': 'Malaysia',
        'currency_code': 'MYR',
        'currency_symbol': 'RM',
        'driving_side': 'left',
        'speed_unit': 'kmh',
        'timezone_iana': 'Asia/Kuala_Lumpur',
      },
      'destination_country': <String, dynamic>{
        'iso_a2': 'SG',
        'name': 'Singapore',
        'currency_code': 'SGD',
        'currency_symbol': '\$',
        'driving_side': 'left',
        'speed_unit': 'kmh',
        'timezone_iana': 'Asia/Singapore',
      },
      'departure_time': '2026-11-23T07:45:00+08:00',
      'cached': false,
      'routes': <Map<String, dynamic>>[
        <String, dynamic>{
          'route_index': 0,
          'profile_used': 'drive_fastest',
          'summary_label': 'drive_fastest (710.2 km, 470 min)',
          'distance_km': 710.2,
          'duration_seconds': 28200.0,
          'has_toll_roads': true,
          'has_highways': true,
          'countries_crossed': <String>['MY', 'SG'],
          'legs': <Map<String, dynamic>>[],
          'tolls': <String, dynamic>{
            'has_tolls': true,
            'display_total': 'RM 69.95 + \$2.00',
            'totals_by_currency': <Map<String, dynamic>>[
              <String, dynamic>{'currency_code': 'MYR', 'amount_minor': 6995, 'formatted': 'RM 69.95'},
              <String, dynamic>{'currency_code': 'SGD', 'amount_minor': 200, 'formatted': '\$2.00'},
            ],
            'items': <Map<String, dynamic>>[],
            'warnings': <String>[],
          },
        },
      ],
      'toll_free_comparison': <String, dynamic>{
        'toll_free_route_index': 1,
        'extra_duration_seconds': 3600.0,
        'extra_distance_km': 42.5,
        'savings_by_currency': <Map<String, dynamic>>[
          <String, dynamic>{'currency_code': 'MYR', 'amount_minor': 6995, 'formatted': 'RM 69.95'},
        ],
        'summary_text': 'Save RM 69.95 (+60 min)',
      },
    };

    final parsed = RouteResponse.fromJson(sample);
    expect(parsed.originCountry?.isoA2, equals('MY'));
    expect(parsed.destinationCountry?.isoA2, equals('SG'));
    expect(parsed.routes.single.tolls.displayTotal, equals('RM 69.95 + \$2.00'));
    expect(parsed.tollFreeComparison?.summaryText, equals('Save RM 69.95 (+60 min)'));
  });
}
