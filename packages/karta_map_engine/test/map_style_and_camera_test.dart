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

    test('KartaMapController replays buffered startup GPS location & camera move on attachDriver', () {
      final ctrl = KartaMapController();
      addTearDown(ctrl.dispose);

      const penangGps = Coordinate(lat: 5.3840, lon: 100.4128);
      // Simulate real-time GPS lock arriving BEFORE MapLibre finishes initializing
      ctrl.setUserLocation(
        coordinate: penangGps,
        headingDeg: 90.0,
        accuracyMeters: 12.0,
        visible: true,
      );
      ctrl.easeTo(
        center: penangGps,
        zoom: 15.6,
        pitch: 48.0,
        durationMs: 750,
      );

      final fakeDriver = _RecordingMapDriver();
      ctrl.attachDriver(fakeDriver);

      expect(fakeDriver.lastUserLocation, equals(penangGps));
      expect(fakeDriver.lastUserLocationVisible, isTrue);
      expect(fakeDriver.lastEasedCenter, equals(penangGps));
      expect(fakeDriver.lastEasedZoom, equals(15.6));
    });
  });
}

class _RecordingMapDriver implements KartaMapPlatformDriver {
  Coordinate? lastUserLocation;
  bool lastUserLocationVisible = false;
  Coordinate? lastEasedCenter;
  double? lastEasedZoom;

  @override
  void easeCamera({
    required Coordinate center,
    double? zoom,
    double? pitch,
    double? bearing,
    int durationMs = 600,
    double paddingTop = 0,
    double paddingBottom = 0,
    double paddingLeft = 0,
  }) {
    lastEasedCenter = center;
    lastEasedZoom = zoom;
  }

  @override
  void setUserLocation({
    required Coordinate? coordinate,
    double? headingDeg,
    double accuracyMeters = 15.0,
    bool visible = true,
  }) {
    lastUserLocation = coordinate;
    lastUserLocationVisible = visible;
  }

  @override
  void fitBounds({
    required double minLon,
    required double minLat,
    required double maxLon,
    required double maxLat,
    double paddingLeft = 420,
    double paddingTop = 80,
    double paddingRight = 80,
    double paddingBottom = 100,
  }) {}

  @override
  void prefetchVectorTiles(List<VectorTileCoord> tiles) {}

  @override
  void set3DBuildingsEnabled(bool enabled) {}

  @override
  void setCarpoolOverlay(CarpoolMapOverlay? overlay) {}

  @override
  void setDrivingSpeed({required double speedKmh, required bool declutterMinorLabels}) {}

  @override
  void setDroppedPin({required Coordinate? coordinate, String? label}) {}

  @override
  void setFuelPins(List<FuelStationComparison> stations) {}

  @override
  void setHazards(List<HazardRecord> hazards) {}

  @override
  void setLightingMode(KartaVisualMode mode) {}

  @override
  void setLookAroundOrbit({
    required Coordinate center,
    required double bearingDeg,
    required bool active,
  }) {}

  @override
  void setPmtilesUrl(String url) {}

  @override
  void setPois(List<PoiItem> pois) {}

  @override
  void setRoutes({
    required List<List<Coordinate>> routePolylines,
    required int selectedIndex,
    int? tollFreeIndex,
    required List<KartaMapStopPin> stops,
    List<KartaMapRouteCallout> callouts = const <KartaMapRouteCallout>[],
    List<KartaMapTurnArrow> turnArrows = const <KartaMapTurnArrow>[],
  }) {}

  @override
  void setSavedPlaces(List<KartaMapSavedPlacePin> savedPlaces) {}

  @override
  void setFeaturedPlaces(List<KartaMapFeaturedPin> places) {}

  @override
  void setMapLanguage(String languageCode) {}

  @override
  void setThermalRenderProfile({
    required int targetFps,
    required bool enable3DBuildings,
    required bool pausedForProjection,
  }) {}

  @override
  void setTollGantries(List<GantryInfo> gantries) {}

  @override
  void setTrafficSegments({
    required List<Coordinate> routePoints,
    required List<CongestionSegment> segments,
  }) {}

  @override
  void setTurnArrows(List<KartaMapTurnArrow> turnArrows) {}

  @override
  void setVehicleCustomization(KartaVehicleCustomization customization) {}

  @override
  void setVehiclePose({
    required Coordinate coordinate,
    required double bearingDeg,
    required double speedKmh,
    required bool visible,
  }) {}
}
