import 'package:flutter_test/flutter_test.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_map_engine/karta_map_engine.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

void main() {
  group('KartaMapStyleBuilder & Speed-Adaptive Camera Physics', () {
    test('builds distinct Obsidian Night & High-Glare Tropical Daylight styles with split labels', () {
      final night = KartaMapStyleBuilder.build(
        pmtilesUrl: 'http://localhost:8081/my-sg-bn-full.json',
        mode: KartaVisualMode.obsidianNight,
      );
      final day = KartaMapStyleBuilder.build(
        pmtilesUrl: 'http://localhost:8081/my-sg-bn-full.json',
        mode: KartaVisualMode.tropicalDaylight,
      );

      final nightLayers = (night['layers'] as List<dynamic>).cast<Map<String, dynamic>>();
      final dayLayers = (day['layers'] as List<dynamic>).cast<Map<String, dynamic>>();

      expect(
        (nightLayers.first['paint'] as Map<String, dynamic>)['background-color'],
        equals('#0D0F12'),
      );
      expect(
        (dayLayers.first['paint'] as Map<String, dynamic>)['background-color'],
        equals('#F5F2EB'),
      );

      final dayLayerIds = dayLayers.map((l) => l['id'] as String).toSet();
      expect(dayLayerIds, containsAll(<String>[
        'landcover_highland',
        'water_name',
        'aeroway_runway',
        'aerodrome_label',
        'roads_minor_casing',
        'roads_primary_casing',
        'roads_motorway_casing',
        'buildings_3d',
        'building_housenumber',
        'mountain_peaks_label',
        'roads_label_minor',
        'roads_label_major',
        'roads_shield_expressway',
        'roads_shield_federal',
        'poi_landmarks',
        'place_suburb_neighbourhood',
        'places_label',
      ]));

      final nightLayerIds = nightLayers.map((l) => l['id'] as String).toSet();
      expect(nightLayerIds, containsAll(<String>[
        'landcover_highland',
        'water_name',
        'aerodrome_label',
        'buildings_3d',
        'building_housenumber',
        'mountain_peaks_label',
        'roads_label_minor',
        'roads_label_major',
        'roads_shield_expressway',
        'roads_shield_federal',
        'poi_landmarks',
        'place_suburb_neighbourhood',
        'places_label',
      ]));
    });

    test('KartaMapController adapts zoom/pitch continuously from 30->110 km/h and declutters >60 km/h', () {
      final ctrl = KartaMapController();
      addTearDown(ctrl.dispose);

      ctrl.setCameraLocked(true);

      // 30 km/h city cruising in KLCC -> close zoom, moderate pitch, minor labels visible
      ctrl.followNavigationFix(
        GpsFix(
          coordinate: const Coordinate(lat: 3.1579, lon: 101.7116),
          bearingDeg: 45,
          speedKmh: 30,
          timestamp: DateTime.utc(2026, 11, 22, 4, 0),
        ),
        forceLock: true,
      );
      final cityZoom = ctrl.zoom;
      final cityPitch = ctrl.pitch;
      expect(cityZoom, greaterThan(17.2));
      expect(cityPitch, lessThan(52.0));
      expect(ctrl.minorLabelsDecluttered, isFalse);

      // 110 km/h North-South Expressway (several ticks for critically-damped camera convergence)
      for (var i = 0; i < 10; i++) {
        ctrl.followNavigationFix(
          GpsFix(
            coordinate: Coordinate(lat: 4.5800 - i * 0.001, lon: 101.0900),
            bearingDeg: 170,
            speedKmh: 110,
            timestamp: DateTime.utc(2026, 11, 22, 4, 5, i),
          ),
          forceLock: true,
        );
      }
      expect(ctrl.zoom, lessThan(cityZoom - 2.0));
      expect(ctrl.pitch, greaterThan(cityPitch + 12.0));
      expect(ctrl.minorLabelsDecluttered, isTrue);

      // Lighting mode switches cleanly
      ctrl.setLightingMode(KartaVisualMode.tropicalDaylight);
      expect(ctrl.lightingMode, equals(KartaVisualMode.tropicalDaylight));
    });
  });
}
