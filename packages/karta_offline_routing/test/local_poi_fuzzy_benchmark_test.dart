import 'package:flutter_test/flutter_test.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_offline_routing/karta_offline_routing.dart';

List<PoiItem> _buildRegionalDataset(int count) {
  final anchors = <PoiItem>[
    const PoiItem(
      id: 1,
      name: 'Petronas Twin Towers (KLCC)',
      category: 'tourism',
      brand: 'Petronas',
      countryCode: 'MY',
      coordinate: Coordinate(lat: 3.1579, lon: 101.7116),
    ),
    const PoiItem(
      id: 2,
      name: 'Petronas R&R Seremban Southbound',
      category: 'rest_area',
      brand: 'Petronas',
      countryCode: 'MY',
      coordinate: Coordinate(lat: 2.7532, lon: 101.8691),
    ),
    const PoiItem(
      id: 3,
      name: 'Gentari DC Fast Charger — Mid Valley',
      category: 'ev_charging',
      brand: 'Gentari',
      countryCode: 'MY',
      coordinate: Coordinate(lat: 3.1177, lon: 101.6774),
    ),
    const PoiItem(
      id: 4,
      name: 'Marina Bay Sands',
      category: 'tourism',
      brand: 'Marina Bay',
      countryCode: 'SG',
      coordinate: Coordinate(lat: 1.2834, lon: 103.8607),
    ),
    const PoiItem(
      id: 5,
      name: 'Changi Airport Terminal 3',
      category: 'airport',
      brand: 'Changi',
      countryCode: 'SG',
      coordinate: Coordinate(lat: 1.3562, lon: 103.9866),
    ),
    const PoiItem(
      id: 6,
      name: 'Omar Ali Saifuddien Mosque, Bandar Seri Begawan',
      category: 'worship',
      brand: 'Brunei Heritage',
      countryCode: 'BN',
      coordinate: Coordinate(lat: 4.8895, lon: 114.9392),
    ),
    const PoiItem(
      id: 7,
      name: 'Komtar George Town Penang',
      category: 'shopping',
      brand: 'Komtar',
      countryCode: 'MY',
      coordinate: Coordinate(lat: 5.4145, lon: 100.3298),
    ),
  ];

  const brands = <String>['Shell', 'Petron', 'BHPetrol', 'Caltex', 'SP Mobility', 'ChargEV', 'AEON', 'MRT'];
  const cats = <String>['fuel', 'ev_charging', 'food', 'shopping', 'transit', 'parking', 'healthcare'];
  const ccs = <String>['MY', 'SG', 'BN'];

  final out = List<PoiItem>.from(anchors);
  for (var i = anchors.length + 1; i <= count; i++) {
    final brand = brands[i % brands.length];
    final cat = cats[i % cats.length];
    final cc = ccs[i % ccs.length];
    final baseLat = cc == 'SG' ? 1.30 : (cc == 'BN' ? 4.88 : 3.10);
    final baseLon = cc == 'SG' ? 103.82 : (cc == 'BN' ? 114.92 : 101.65);
    out.add(
      PoiItem(
        id: i,
        name: '$brand Station Plaza #$i ${cc == 'MY' ? 'Selangor' : (cc == 'SG' ? 'Singapore' : 'Brunei')}',
        category: cat,
        brand: brand,
        countryCode: cc,
        coordinate: Coordinate(
          lat: baseLat + ((i % 97) - 48) * 0.004,
          lon: baseLon + ((i % 89) - 44) * 0.004,
        ),
      ),
    );
  }
  return out;
}

void main() {
  test('LocalPoiFuzzyIndex searches 5,000 MY/SG/BN POIs in strictly under 50ms with typo tolerance', () {
    final index = LocalPoiFuzzyIndex();
    final dataset = _buildRegionalDataset(5000);
    index.upsertAll(dataset, regionId: 'my-sg-bn-full');
    expect(index.count, 5000);

    // Typo-tolerant queries across Malaysia, Singapore, and Brunei
    final typoPetronas = index.search(query: 'petrnas', nearLat: 3.1579, nearLon: 101.7116);
    expect(typoPetronas.items, isNotEmpty);
    expect(typoPetronas.items.first.name.toLowerCase(), contains('petronas'));

    final typoMarina = index.search(query: 'marna bay', nearLat: 1.29, nearLon: 103.85);
    expect(typoMarina.items, isNotEmpty);
    expect(typoMarina.items.first.name, 'Marina Bay Sands');

    final klccPrefix = index.search(query: 'klc', nearLat: 3.15, nearLon: 101.71);
    expect(klccPrefix.items, isNotEmpty);
    expect(klccPrefix.items.first.name, contains('KLCC'));

    final bruneiFilter = index.search(query: 'mosque', countryCode: 'BN');
    expect(bruneiFilter.items, isNotEmpty);
    expect(bruneiFilter.items.first.countryCode, 'BN');

    // Warm benchmark across 20 realistic keystroke queries
    const queries = <String>[
      'pet', 'petr', 'petrnas', 'klcc', 'r&r seremban',
      'gentari', 'marina', 'marna bay', 'changi', 'komtar',
      'bandar seri', 'shell', 'chargev', 'sp mobility', 'mrt',
      'aeon', 'petron', 'caltex', 'bhpetrol', 'station 42',
    ];
    final latenciesMs = <double>[];
    for (final q in queries) {
      final res = index.search(query: q, nearLat: 3.1579, nearLon: 101.7116, limit: 18);
      latenciesMs.add(res.queryMs);
    }
    latenciesMs.sort();
    final p95 = latenciesMs[(latenciesMs.length * 0.95).floor().clamp(0, latenciesMs.length - 1)];
    final maxMs = latenciesMs.last;

    // Strict UX guarantee: < 50ms per keystroke across 5,000 POIs
    expect(p95, lessThan(50.0), reason: 'p95=${p95.toStringAsFixed(2)}ms, max=${maxMs.toStringAsFixed(2)}ms');
    expect(maxMs, lessThan(50.0), reason: 'max=${maxMs.toStringAsFixed(2)}ms');
  });

  test('LocalPoiFuzzyIndex removes region POIs cleanly on offline pack deletion', () {
    final index = LocalPoiFuzzyIndex();
    index.upsertAll(_buildRegionalDataset(50).take(10), regionId: 'sg');
    expect(index.count, 10);
    index.removeRegion('sg');
    expect(index.count, 0);
  });
}
