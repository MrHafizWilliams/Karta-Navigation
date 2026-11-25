import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import 'package:web/web.dart' as web;

import '../cache/predictive_tile_prefetcher.dart';
import '../controller/karta_map_controller.dart';
import '../models/map_types.dart';

@JS('KartaMapBridge')
extension type _KartaMapBridgeJs._(JSObject _) implements JSObject {
  external void init(
    String containerId,
    String pmtilesUrl,
    double lat,
    double lon,
    double zoom,
    double pitch,
    JSFunction onReady,
    JSFunction onMapTap,
    JSFunction onUserDrag,
  );
  external void easeCamera(String containerId, String optionsJson);
  external void fitBounds(String containerId, String optionsJson);
  external void setRoutes(String containerId, String payloadJson);
  external void setTurnArrows(String containerId, String payloadJson);
  external void setSavedPlaces(String containerId, String payloadJson);
  external void setPois(String containerId, String payloadJson);
  external void setTollGantries(String containerId, String payloadJson);
  external void setHazards(String containerId, String payloadJson);
  external void setTrafficSegments(String containerId, String payloadJson);
  external void setFuelPins(String containerId, String payloadJson);
  external void setCarpoolOverlay(String containerId, String payloadJson);
  external void setUserLocation(
    String containerId,
    double lat,
    double lon,
    double headingDeg,
    double accuracyMeters,
    bool visible,
  );
  external void setDroppedPin(
    String containerId,
    double lat,
    double lon,
    String label,
    bool visible,
  );
  external void setVehiclePose(
    String containerId,
    double lat,
    double lon,
    double bearingDeg,
    double speedKmh,
    bool visible,
  );
  external void setVehicleCustomization(String containerId, String payloadJson);
  external void set3DBuildings(String containerId, bool enabled);
  external void setPmtilesUrl(String containerId, String pmtilesUrl);
  external void setLightingMode(String containerId, String mode);
  external void setDrivingSpeed(
    String containerId,
    double speedKmh,
    bool declutterMinor,
  );
  external void setLookAroundOrbit(
    String containerId,
    double lat,
    double lon,
    double bearingDeg,
    bool active,
  );
  external void prefetchTiles(String containerId, String payloadJson);
  external void registerPinCallbacks(
    String containerId,
    JSFunction onFuelPinTap,
    JSFunction onHazardPinTap,
    JSFunction onPoiPinTap,
    JSFunction onViewportChanged,
    JSFunction onRouteCalloutTap,
  );
  external void destroy(String containerId);
}

@JS('KartaMapBridge')
external _KartaMapBridgeJs? get _kartaBridge;

Widget buildPlatformKartaMapView({
  required KartaMapController controller,
  required String pmtilesUrl,
  required Coordinate initialCenter,
  required double initialZoom,
  required double initialPitch,
}) {
  return _WebKartaMapView(
    controller: controller,
    pmtilesUrl: pmtilesUrl,
    initialCenter: initialCenter,
    initialZoom: initialZoom,
    initialPitch: initialPitch,
  );
}

class _WebKartaMapView extends StatefulWidget {
  const _WebKartaMapView({
    required this.controller,
    required this.pmtilesUrl,
    required this.initialCenter,
    required this.initialZoom,
    required this.initialPitch,
  });

  final KartaMapController controller;
  final String pmtilesUrl;
  final Coordinate initialCenter;
  final double initialZoom;
  final double initialPitch;

  @override
  State<_WebKartaMapView> createState() => _WebKartaMapViewState();
}

class _WebKartaMapViewState extends State<_WebKartaMapView> implements KartaMapPlatformDriver {
  static int _viewCounter = 0;
  late final String _viewType;
  late final String _containerId;

  @override
  void initState() {
    super.initState();
    _viewCounter += 1;
    _containerId = 'karta-maplibre-$_viewCounter';
    _viewType = 'karta-maplibre-view-$_viewCounter';

    final isInitialDay = widget.controller.lightingMode == KartaVisualMode.tropicalDaylight;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final div = web.document.createElement('div') as web.HTMLDivElement
        ..id = _containerId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = isInitialDay ? '#F5F2EB' : '#0D0F12'
        ..style.position = 'relative';

      // Initialize MapLibre GL JS after DOM mount
      Future<void>.delayed(const Duration(milliseconds: 50), _mountBridge);
      return div;
    });
  }

  void _mountBridge() {
    final bridge = _kartaBridge;
    if (bridge == null || !mounted) return;
    bridge.init(
      _containerId,
      widget.pmtilesUrl,
      widget.initialCenter.lat,
      widget.initialCenter.lon,
      widget.initialZoom,
      widget.initialPitch,
      (() {
        if (mounted) {
          bridge.registerPinCallbacks(
            _containerId,
            ((int poiId) {
              if (mounted) widget.controller.notifyFuelPinTapped(poiId);
            }).toJS,
            ((String hazardId) {
              if (mounted) widget.controller.notifyHazardPinTapped(hazardId);
            }).toJS,
            ((int poiId) {
              if (mounted) widget.controller.notifyPoiPinTapped(poiId);
            }).toJS,
            ((double minLon, double minLat, double maxLon, double maxLat, double zoom) {
              if (mounted) {
                widget.controller.notifyViewportChanged(
                  KartaViewportBounds(
                    minLon: minLon,
                    minLat: minLat,
                    maxLon: maxLon,
                    maxLat: maxLat,
                    zoom: zoom,
                  ),
                );
              }
            }).toJS,
            ((int routeIndex) {
              if (mounted) widget.controller.notifyRouteCalloutTapped(routeIndex);
            }).toJS,
          );
          widget.controller.attachDriver(this);
        }
      }).toJS,
      ((double lat, double lon) {
        if (mounted) widget.controller.notifyMapTapped(Coordinate(lat: lat, lon: lon));
      }).toJS,
      (() {
        if (mounted) widget.controller.notifyUserDragged();
      }).toJS,
    );
  }

  @override
  void dispose() {
    widget.controller.detachDriver();
    _kartaBridge?.destroy(_containerId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }

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
    _kartaBridge?.easeCamera(
      _containerId,
      jsonEncode(<String, dynamic>{
        'lat': center.lat,
        'lon': center.lon,
        if (zoom != null) 'zoom': zoom,
        if (pitch != null) 'pitch': pitch,
        if (bearing != null) 'bearing': bearing,
        'durationMs': durationMs,
        'padding': <String, double>{
          'top': paddingTop,
          'bottom': paddingBottom,
          'left': paddingLeft,
          'right': 0,
        },
      }),
    );
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
  }) {
    _kartaBridge?.fitBounds(
      _containerId,
      jsonEncode(<String, dynamic>{
        'minLon': minLon,
        'minLat': minLat,
        'maxLon': maxLon,
        'maxLat': maxLat,
        'padding': <String, double>{
          'left': paddingLeft,
          'top': paddingTop,
          'right': paddingRight,
          'bottom': paddingBottom,
        },
      }),
    );
  }

  @override
  void setRoutes({
    required List<List<Coordinate>> routePolylines,
    required int selectedIndex,
    int? tollFreeIndex,
    required List<KartaMapStopPin> stops,
    List<KartaMapRouteCallout> callouts = const <KartaMapRouteCallout>[],
    List<KartaMapTurnArrow> turnArrows = const <KartaMapTurnArrow>[],
  }) {
    _kartaBridge?.setRoutes(
      _containerId,
      jsonEncode(<String, dynamic>{
        'routes': routePolylines
            .map((line) => line.map((c) => <double>[c.lon, c.lat]).toList())
            .toList(),
        'selectedIndex': selectedIndex,
        'tollFreeIndex': tollFreeIndex,
        'stops': stops.map((s) => s.toJson()).toList(),
        'callouts': callouts.map((c) => c.toJson()).toList(),
        'turnArrows': turnArrows.map((a) => a.toJson()).toList(),
      }),
    );
  }

  @override
  void setTurnArrows(List<KartaMapTurnArrow> turnArrows) {
    _kartaBridge?.setTurnArrows(
      _containerId,
      jsonEncode(turnArrows.map((a) => a.toJson()).toList()),
    );
  }

  @override
  void setSavedPlaces(List<KartaMapSavedPlacePin> savedPlaces) {
    _kartaBridge?.setSavedPlaces(
      _containerId,
      jsonEncode(savedPlaces.map((p) => p.toJson()).toList()),
    );
  }

  @override
  void setPois(List<PoiItem> pois) {
    _kartaBridge?.setPois(
      _containerId,
      jsonEncode(
        pois
            .map(
              (p) => <String, dynamic>{
                'id': p.id,
                'name': p.name,
                'category': p.category,
                'brand': p.brand,
                'lat': p.coordinate.lat,
                'lon': p.coordinate.lon,
              },
            )
            .toList(),
      ),
    );
  }

  @override
  void setTollGantries(List<GantryInfo> gantries) {
    // Toll gantry map symbols disabled
    _kartaBridge?.setTollGantries(_containerId, '[]');
  }

  @override
  void setHazards(List<HazardRecord> hazards) {
    _kartaBridge?.setHazards(
      _containerId,
      jsonEncode(
        hazards
            .map(
              (h) => <String, dynamic>{
                'id': h.id,
                'category': h.category.wireValue,
                'label': h.category.label,
                'severity': h.severity.wireValue,
                'severityRank': switch (h.category) {
                  HazardCategory.roadClosure || HazardCategory.accident => 3,
                  HazardCategory.police => 2,
                  _ => 1,
                },
                'lat': h.coordinate.lat,
                'lon': h.coordinate.lon,
                'confirmations': h.confirmations,
                'roadRef': h.roadRef,
                'onRoute': h.onActiveRoute,
              },
            )
            .toList(),
      ),
    );
  }

  @override
  void setTrafficSegments({
    required List<Coordinate> routePoints,
    required List<CongestionSegment> segments,
  }) {
    _kartaBridge?.setTrafficSegments(
      _containerId,
      jsonEncode(<String, dynamic>{
        'route': routePoints.map((c) => <double>[c.lon, c.lat]).toList(),
        'segments': segments.map((s) => s.toJson()).toList(),
      }),
    );
  }

  @override
  void setFuelPins(List<FuelStationComparison> stations) {
    int? cheapestMinor;
    for (final s in stations) {
      if (cheapestMinor == null || s.selectedPriceMinor < cheapestMinor) {
        cheapestMinor = s.selectedPriceMinor;
      }
    }

    _kartaBridge?.setFuelPins(
      _containerId,
      jsonEncode(
        stations.map((s) {
          final deltaMinor =
              cheapestMinor != null ? (s.selectedPriceMinor - cheapestMinor) : 0;
          String? deltaFormatted;
          if (!s.isCheapest && deltaMinor > 0) {
            deltaFormatted = '+${(deltaMinor / 100.0).toStringAsFixed(2)}';
          }
          return <String, dynamic>{
            'id': s.poiId,
            'name': s.name,
            'brand': s.brand ?? s.name,
            'price': s.selectedFormattedPrice,
            'priceMinor': s.selectedPriceMinor,
            'deltaFormatted': deltaFormatted,
            'grade': s.selectedGrade.shortLabel,
            'cheapest': s.isCheapest,
            'detourMeters': s.detourMeters,
            'distanceAlongRouteKm': s.distanceAlongRouteKm,
            'lat': s.coordinate.lat,
            'lon': s.coordinate.lon,
          };
        }).toList(),
      ),
    );
  }

  @override
  void setCarpoolOverlay(CarpoolMapOverlay? overlay) {
    _kartaBridge?.setCarpoolOverlay(
      _containerId,
      jsonEncode(overlay?.toJson()),
    );
  }

  @override
  void setUserLocation({
    required Coordinate? coordinate,
    double? headingDeg,
    double accuracyMeters = 15.0,
    bool visible = true,
  }) {
    _kartaBridge?.setUserLocation(
      _containerId,
      coordinate?.lat ?? 0.0,
      coordinate?.lon ?? 0.0,
      headingDeg ?? -1.0,
      accuracyMeters,
      visible && coordinate != null,
    );
  }

  @override
  void setDroppedPin({
    required Coordinate? coordinate,
    String? label,
  }) {
    _kartaBridge?.setDroppedPin(
      _containerId,
      coordinate?.lat ?? 0.0,
      coordinate?.lon ?? 0.0,
      label ?? '',
      coordinate != null,
    );
  }

  @override
  void setVehiclePose({
    required Coordinate coordinate,
    required double bearingDeg,
    required double speedKmh,
    required bool visible,
  }) {
    _kartaBridge?.setVehiclePose(
      _containerId,
      coordinate.lat,
      coordinate.lon,
      bearingDeg,
      speedKmh,
      visible,
    );
  }

  @override
  void setVehicleCustomization(KartaVehicleCustomization customization) {
    _kartaBridge?.setVehicleCustomization(_containerId, jsonEncode(customization.toJson()));
  }

  @override
  void set3DBuildingsEnabled(bool enabled) {
    _kartaBridge?.set3DBuildings(_containerId, enabled);
  }

  @override
  void setPmtilesUrl(String url) {
    _kartaBridge?.setPmtilesUrl(_containerId, url);
  }

  @override
  void setLightingMode(KartaVisualMode mode) {
    _kartaBridge?.setLightingMode(
      _containerId,
      mode == KartaVisualMode.tropicalDaylight ? 'day' : 'dark',
    );
  }

  @override
  void setDrivingSpeed({
    required double speedKmh,
    required bool declutterMinorLabels,
  }) {
    _kartaBridge?.setDrivingSpeed(_containerId, speedKmh, declutterMinorLabels);
  }

  @override
  void setLookAroundOrbit({
    required Coordinate center,
    required double bearingDeg,
    required bool active,
  }) {
    _kartaBridge?.setLookAroundOrbit(_containerId, center.lat, center.lon, bearingDeg, active);
  }

  @override
  void setThermalRenderProfile({
    required int targetFps,
    required bool enable3DBuildings,
    required bool pausedForProjection,
  }) {
    _kartaBridge?.set3DBuildings(_containerId, enable3DBuildings && !pausedForProjection);
  }

  @override
  void prefetchVectorTiles(List<VectorTileCoord> tiles) {
    if (tiles.isEmpty) return;
    _kartaBridge?.prefetchTiles(
      _containerId,
      jsonEncode(tiles.map((t) => t.toJson()).toList()),
    );
  }
}
