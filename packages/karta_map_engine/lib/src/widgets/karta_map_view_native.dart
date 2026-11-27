import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../cache/predictive_tile_prefetcher.dart';
import '../controller/karta_map_controller.dart';
import '../models/map_types.dart';

Widget buildPlatformKartaMapView({
  required KartaMapController controller,
  required String pmtilesUrl,
  required Coordinate initialCenter,
  required double initialZoom,
  required double initialPitch,
}) {
  final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
  final useNativeMobileWebView =
      !kIsWeb && !isFlutterTest && (Platform.isAndroid || Platform.isIOS);

  if (useNativeMobileWebView) {
    return _MobileWebViewKartaMap(
      controller: controller,
      pmtilesUrl: pmtilesUrl,
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      initialPitch: initialPitch,
    );
  }

  return _NativeKartaMapSurface(
    controller: controller,
    pmtilesUrl: pmtilesUrl,
    initialCenter: initialCenter,
    initialZoom: initialZoom,
    initialPitch: initialPitch,
  );
}

/// Real hardware-accelerated MapLibre GL JS v5 + PMTiles / OpenMapTiles vector
/// map host for Android and iOS smartphones & tablets.
///
/// Shares Karta's exact `karta_map_bridge.js` engine (3D buildings, authentic
/// 8-country ASEAN road shields, Google Maps-style POI pins, pulsing live GPS
/// indicator, curved 2D turn arrows, and Day/Night lighting).
class _MobileWebViewKartaMap extends StatefulWidget {
  const _MobileWebViewKartaMap({
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
  State<_MobileWebViewKartaMap> createState() => _MobileWebViewKartaMapState();
}

class _MobileWebViewKartaMapState extends State<_MobileWebViewKartaMap>
    implements KartaMapPlatformDriver {
  static const String _containerId = 'karta-maplibre-native';

  late final WebViewController _webController;
  final List<String> _pendingJsQueue = <String>[];
  bool _bridgeReady = false;
  bool _hostLoaded = false;
  bool _disposed = false;
  bool _pausedForProjection = false;

  @override
  void initState() {
    super.initState();
    final isInitialDay =
        widget.controller.lightingMode == KartaVisualMode.tropicalDaylight;

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(
        isInitialDay ? const Color(0xFFF5F2EB) : const Color(0xFF0D0F12),
      )
      ..addJavaScriptChannel(
        'KartaNativeChannel',
        onMessageReceived: _onNativeJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!_hostLoaded && !_disposed) {
              _hostLoaded = true;
              _initMapBridge();
            }
          },
        ),
      );

    _loadBundledMapSurface();
  }

  Future<void> _loadBundledMapSurface() async {
    try {
      final htmlTemplate = await rootBundle.loadString(
        'packages/karta_map_engine/assets/karta_mobile_map.html',
      );
      final bridgeJs = await rootBundle.loadString(
        'packages/karta_map_engine/assets/karta_map_bridge.js',
      );
      if (_disposed) return;

      final combinedHtml = htmlTemplate.replaceFirst(
        '/* __KARTA_MAP_BRIDGE_JS__ */',
        bridgeJs,
      );
      await _webController.loadHtmlString(
        combinedHtml,
        baseUrl: 'https://karta.local/',
      );
    } catch (e) {
      debugPrint('[KartaMobileMap] Failed to load bundled map assets: $e');
    }
  }

  void _initMapBridge() {
    final lightingStr =
        widget.controller.lightingMode == KartaVisualMode.tropicalDaylight
            ? 'day'
            : 'dark';
    final cfg = jsonEncode(<String, dynamic>{
      'containerId': _containerId,
      'pmtilesUrl': widget.pmtilesUrl,
      'lat': widget.initialCenter.lat,
      'lon': widget.initialCenter.lon,
      'zoom': widget.initialZoom,
      'pitch': widget.initialPitch,
      'lightingMode': lightingStr,
    });
    _webController.runJavaScript(
      'if (window.__kartaNativeInit) { window.__kartaNativeInit($cfg); }',
    );
  }

  void _onNativeJsMessage(JavaScriptMessage msg) {
    if (_disposed || !mounted) return;
    try {
      final decoded = jsonDecode(msg.message);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type'] as String? ?? '';
      final payload = (decoded['payload'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};

      switch (type) {
        case 'hostLoaded':
          if (!_hostLoaded) {
            _hostLoaded = true;
            _initMapBridge();
          }
          break;
        case 'ready':
          _bridgeReady = true;
          widget.controller.attachDriver(this);
          _flushPendingQueue();
          break;
        case 'mapTap':
          final lat = (payload['lat'] as num?)?.toDouble();
          final lon = (payload['lon'] as num?)?.toDouble();
          if (lat != null && lon != null) {
            widget.controller.notifyMapTapped(Coordinate(lat: lat, lon: lon));
          }
          break;
        case 'userDrag':
          widget.controller.notifyUserDragged();
          break;
        case 'fuelPinTap':
          final poiId = (payload['poiId'] as num?)?.toInt();
          if (poiId != null) widget.controller.notifyFuelPinTapped(poiId);
          break;
        case 'hazardPinTap':
          final hazardId = payload['hazardId'] as String?;
          if (hazardId != null) widget.controller.notifyHazardPinTapped(hazardId);
          break;
        case 'poiPinTap':
          final poiId = (payload['poiId'] as num?)?.toInt();
          if (poiId != null) widget.controller.notifyPoiPinTapped(poiId);
          break;
        case 'routeCalloutTap':
          final idx = (payload['routeIndex'] as num?)?.toInt();
          if (idx != null) widget.controller.notifyRouteCalloutTapped(idx);
          break;
        case 'featuredPlaceTap':
          final placeId = payload['placeId'] as String?;
          if (placeId != null && placeId.isNotEmpty) {
            widget.controller.notifyFeaturedPlaceTapped(placeId);
          }
          break;
        case 'vectorFeatureTap':
          final featureJson = payload['featureJson'] as String?;
          if (featureJson != null && featureJson.isNotEmpty) {
            final decodedFeat = jsonDecode(featureJson);
            if (decodedFeat is Map<String, dynamic>) {
              final lat = (decodedFeat['lat'] as num?)?.toDouble();
              final lon = (decodedFeat['lon'] as num?)?.toDouble();
              final name = (decodedFeat['name'] as String?)?.trim() ?? '';
              if (lat != null && lon != null && name.isNotEmpty) {
                widget.controller.notifyVectorFeatureTapped(
                  KartaVectorFeatureTap(
                    name: name,
                    featureClass: (decodedFeat['featureClass'] as String?) ?? '',
                    subclass: (decodedFeat['subclass'] as String?) ?? '',
                    religion: decodedFeat['religion'] as String?,
                    iata: decodedFeat['iata'] as String?,
                    coordinate: Coordinate(lat: lat, lon: lon),
                  ),
                );
              }
            }
          }
          break;
        case 'viewportChanged':
          final minLon = (payload['minLon'] as num?)?.toDouble();
          final minLat = (payload['minLat'] as num?)?.toDouble();
          final maxLon = (payload['maxLon'] as num?)?.toDouble();
          final maxLat = (payload['maxLat'] as num?)?.toDouble();
          final zoom = (payload['zoom'] as num?)?.toDouble();
          if (minLon != null &&
              minLat != null &&
              maxLon != null &&
              maxLat != null &&
              zoom != null) {
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
          break;
      }
    } catch (e) {
      debugPrint('[KartaMobileMap] Channel parse warning: $e');
    }
  }

  void _callBridge(String jsStatement) {
    if (_disposed) return;
    if (!_bridgeReady) {
      if (_pendingJsQueue.length > 40) {
        _pendingJsQueue.removeAt(0);
      }
      _pendingJsQueue.add(jsStatement);
      return;
    }
    _webController.runJavaScript(jsStatement);
  }

  void _flushPendingQueue() {
    if (_pendingJsQueue.isEmpty || _disposed) return;
    final batch = List<String>.from(_pendingJsQueue);
    _pendingJsQueue.clear();
    for (final stmt in batch) {
      _webController.runJavaScript(stmt);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.controller.detachDriver();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pausedForProjection) {
      return ColoredBox(
        color: context.kartaPalette.backgroundPrimary,
        child: const SizedBox.expand(),
      );
    }
    return WebViewWidget(controller: _webController);
  }

  String _jsStr(String raw) => jsonEncode(raw);

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
    final opts = jsonEncode(<String, dynamic>{
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
    });
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.easeCamera(${_jsStr(_containerId)}, ${_jsStr(opts)});',
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
    final opts = jsonEncode(<String, dynamic>{
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
    });
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.fitBounds(${_jsStr(_containerId)}, ${_jsStr(opts)});',
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
    final payload = jsonEncode(<String, dynamic>{
      'routes': routePolylines
          .map((line) => line.map((c) => <double>[c.lon, c.lat]).toList())
          .toList(),
      'selectedIndex': selectedIndex,
      'tollFreeIndex': tollFreeIndex,
      'stops': stops.map((s) => s.toJson()).toList(),
      'callouts': callouts.map((c) => c.toJson()).toList(),
      'turnArrows': turnArrows.map((a) => a.toJson()).toList(),
    });
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setRoutes(${_jsStr(_containerId)}, ${_jsStr(payload)});',
    );
  }

  @override
  void setTurnArrows(List<KartaMapTurnArrow> turnArrows) {
    final payload = jsonEncode(turnArrows.map((a) => a.toJson()).toList());
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setTurnArrows(${_jsStr(_containerId)}, ${_jsStr(payload)});',
    );
  }

  @override
  void setSavedPlaces(List<KartaMapSavedPlacePin> savedPlaces) {
    final payload = jsonEncode(savedPlaces.map((p) => p.toJson()).toList());
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setSavedPlaces(${_jsStr(_containerId)}, ${_jsStr(payload)});',
    );
  }

  @override
  void setPois(List<PoiItem> pois) {
    final payload = jsonEncode(
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
    );
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setPois(${_jsStr(_containerId)}, ${_jsStr(payload)});',
    );
  }

  @override
  void setTollGantries(List<GantryInfo> gantries) {
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setTollGantries(${_jsStr(_containerId)}, "[]");',
    );
  }

  @override
  void setHazards(List<HazardRecord> hazards) {
    final payload = jsonEncode(
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
    );
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setHazards(${_jsStr(_containerId)}, ${_jsStr(payload)});',
    );
  }

  @override
  void setTrafficSegments({
    required List<Coordinate> routePoints,
    required List<CongestionSegment> segments,
  }) {
    final payload = jsonEncode(<String, dynamic>{
      'route': routePoints.map((c) => <double>[c.lon, c.lat]).toList(),
      'segments': segments.map((s) => s.toJson()).toList(),
    });
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setTrafficSegments(${_jsStr(_containerId)}, ${_jsStr(payload)});',
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
    final payload = jsonEncode(
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
    );
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setFuelPins(${_jsStr(_containerId)}, ${_jsStr(payload)});',
    );
  }

  @override
  void setCarpoolOverlay(CarpoolMapOverlay? overlay) {
    final payload = jsonEncode(overlay?.toJson());
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setCarpoolOverlay(${_jsStr(_containerId)}, ${_jsStr(payload)});',
    );
  }

  @override
  void setUserLocation({
    required Coordinate? coordinate,
    double? headingDeg,
    double accuracyMeters = 15.0,
    bool visible = true,
  }) {
    final lat = coordinate?.lat ?? 0.0;
    final lon = coordinate?.lon ?? 0.0;
    final hdg = headingDeg ?? -1.0;
    final vis = visible && coordinate != null;
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setUserLocation(${_jsStr(_containerId)}, $lat, $lon, $hdg, $accuracyMeters, $vis);',
    );
  }

  @override
  void setDroppedPin({
    required Coordinate? coordinate,
    String? label,
  }) {
    final lat = coordinate?.lat ?? 0.0;
    final lon = coordinate?.lon ?? 0.0;
    final vis = coordinate != null;
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setDroppedPin(${_jsStr(_containerId)}, $lat, $lon, ${_jsStr(label ?? '')}, $vis);',
    );
  }

  @override
  void setVehiclePose({
    required Coordinate coordinate,
    required double bearingDeg,
    required double speedKmh,
    required bool visible,
  }) {
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setVehiclePose(${_jsStr(_containerId)}, ${coordinate.lat}, ${coordinate.lon}, $bearingDeg, $speedKmh, $visible);',
    );
  }

  @override
  void setVehicleCustomization(KartaVehicleCustomization customization) {
    final payload = jsonEncode(customization.toJson());
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setVehicleCustomization(${_jsStr(_containerId)}, ${_jsStr(payload)});',
    );
  }

  @override
  void set3DBuildingsEnabled(bool enabled) {
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.set3DBuildings(${_jsStr(_containerId)}, $enabled);',
    );
  }

  @override
  void setPmtilesUrl(String url) {
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setPmtilesUrl(${_jsStr(_containerId)}, ${_jsStr(url)});',
    );
  }

  @override
  void setLightingMode(KartaVisualMode mode) {
    final m = mode == KartaVisualMode.tropicalDaylight ? 'day' : 'dark';
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setLightingMode(${_jsStr(_containerId)}, ${_jsStr(m)});',
    );
  }

  @override
  void setDrivingSpeed({
    required double speedKmh,
    required bool declutterMinorLabels,
  }) {
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setDrivingSpeed(${_jsStr(_containerId)}, $speedKmh, $declutterMinorLabels);',
    );
  }

  @override
  void setLookAroundOrbit({
    required Coordinate center,
    required double bearingDeg,
    required bool active,
  }) {
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setLookAroundOrbit(${_jsStr(_containerId)}, ${center.lat}, ${center.lon}, $bearingDeg, $active);',
    );
  }

  @override
  void setThermalRenderProfile({
    required int targetFps,
    required bool enable3DBuildings,
    required bool pausedForProjection,
  }) {
    if (_pausedForProjection != pausedForProjection && mounted) {
      setState(() => _pausedForProjection = pausedForProjection);
    }
    set3DBuildingsEnabled(enable3DBuildings && !pausedForProjection);
  }

  @override
  void prefetchVectorTiles(List<VectorTileCoord> tiles) {
    if (tiles.isEmpty) return;
    final payload = jsonEncode(tiles.map((t) => t.toJson()).toList());
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.prefetchTiles(${_jsStr(_containerId)}, ${_jsStr(payload)});',
    );
  }

  @override
  void setFeaturedPlaces(List<KartaMapFeaturedPin> places) {
    final payload = jsonEncode(places.map((p) => p.toJson()).toList());
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setFeaturedPlaces(${_jsStr(_containerId)}, ${_jsStr(payload)});',
    );
  }

  @override
  void setMapLanguage(String languageCode) {
    _callBridge(
      'window.KartaMapBridge && window.KartaMapBridge.setMapLanguage(${_jsStr(_containerId)}, ${_jsStr(languageCode)});',
    );
  }
}

/// Deterministic vector projection canvas used strictly for headless desktop
/// widget tests and non-Web/non-mobile fallback targets.
class _NativeKartaMapSurface extends StatefulWidget {
  const _NativeKartaMapSurface({
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
  State<_NativeKartaMapSurface> createState() => _NativeKartaMapSurfaceState();
}

class _NativeKartaMapSurfaceState extends State<_NativeKartaMapSurface>
    implements KartaMapPlatformDriver {
  late Coordinate _center;
  late double _zoom;
  late double _pitch;
  double _bearing = 0;
  KartaVisualMode _lightingMode = KartaVisualMode.obsidianNight;
  List<List<Coordinate>> _routes = const <List<Coordinate>>[];
  int _selectedIdx = 0;
  List<KartaMapStopPin> _stops = const <KartaMapStopPin>[];
  List<HazardRecord> _hazards = const <HazardRecord>[];
  List<FuelStationComparison> _fuelPins = const <FuelStationComparison>[];
  CarpoolMapOverlay? _carpoolOverlay;
  Coordinate? _userLocation;
  bool _userLocationVisible = false;
  Coordinate? _droppedPin;
  Coordinate? _vehicleCoord;
  double _vehicleBearing = 0;
  bool _vehicleVisible = false;
  KartaVehicleCustomization _vehicleStyle = const KartaVehicleCustomization();
  bool _pausedForProjection = false;

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter;
    _zoom = widget.initialZoom;
    _pitch = widget.initialPitch;
    _lightingMode = widget.controller.lightingMode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.attachDriver(this);
    });
  }

  @override
  void dispose() {
    widget.controller.detachDriver();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDay = _lightingMode == KartaVisualMode.tropicalDaylight;
    final palette = isDay ? KartaPalette.tropicalDaylight : KartaPalette.obsidianNight;

    if (_pausedForProjection) {
      return ColoredBox(
        color: palette.backgroundPrimary,
        child: const SizedBox.expand(),
      );
    }
    return GestureDetector(
      onPanStart: (_) => widget.controller.notifyUserDragged(),
      child: ColoredBox(
        color: palette.backgroundPrimary,
        child: CustomPaint(
          painter: _VectorProjectionFallbackPainter(
            palette: palette,
            center: _center,
            zoom: _zoom,
            pitch: _pitch,
            bearing: _bearing,
            routes: _routes,
            selectedIdx: _selectedIdx,
            stops: _stops,
            hazards: _hazards,
            fuelPins: _fuelPins,
            carpoolOverlay: _carpoolOverlay,
            userLocation: _userLocationVisible ? _userLocation : null,
            droppedPin: _droppedPin,
            vehicleCoord: _vehicleCoord,
            vehicleBearing: _vehicleBearing,
            vehicleVisible: _vehicleVisible,
            vehicleStyle: _vehicleStyle,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
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
    if (!mounted) return;
    setState(() {
      _center = center;
      if (zoom != null) _zoom = zoom;
      if (pitch != null) _pitch = pitch;
      if (bearing != null) _bearing = bearing;
    });
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
    if (!mounted) return;
    setState(() {
      _center = Coordinate(lat: (minLat + maxLat) / 2, lon: (minLon + maxLon) / 2);
      final span = math.max(maxLat - minLat, maxLon - minLon).clamp(0.01, 10.0);
      _zoom = (math.log(360 / span) / math.ln2).clamp(5.5, 16.0);
    });
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
    if (!mounted) return;
    setState(() {
      _routes = routePolylines;
      _selectedIdx = selectedIndex;
      _stops = stops;
    });
  }

  @override
  void setTurnArrows(List<KartaMapTurnArrow> turnArrows) {}

  @override
  void setSavedPlaces(List<KartaMapSavedPlacePin> savedPlaces) {}

  @override
  void setPois(List<PoiItem> pois) {}

  @override
  void setTollGantries(List<GantryInfo> gantries) {}

  @override
  void setHazards(List<HazardRecord> hazards) {
    if (!mounted) return;
    setState(() => _hazards = hazards);
  }

  @override
  void setTrafficSegments({
    required List<Coordinate> routePoints,
    required List<CongestionSegment> segments,
  }) {}

  @override
  void setFuelPins(List<FuelStationComparison> stations) {
    if (!mounted) return;
    setState(() => _fuelPins = stations);
  }

  @override
  void setCarpoolOverlay(CarpoolMapOverlay? overlay) {
    if (!mounted) return;
    setState(() => _carpoolOverlay = overlay);
  }

  @override
  void setUserLocation({
    required Coordinate? coordinate,
    double? headingDeg,
    double accuracyMeters = 15.0,
    bool visible = true,
  }) {
    if (!mounted) return;
    setState(() {
      _userLocation = coordinate;
      _userLocationVisible = visible && coordinate != null;
    });
  }

  @override
  void setDroppedPin({
    required Coordinate? coordinate,
    String? label,
  }) {
    if (!mounted) return;
    setState(() => _droppedPin = coordinate);
  }

  @override
  void setVehiclePose({
    required Coordinate coordinate,
    required double bearingDeg,
    required double speedKmh,
    required bool visible,
  }) {
    if (!mounted) return;
    setState(() {
      _vehicleCoord = coordinate;
      _vehicleBearing = bearingDeg;
      _vehicleVisible = visible;
    });
  }

  @override
  void setVehicleCustomization(KartaVehicleCustomization customization) {
    if (!mounted) return;
    setState(() => _vehicleStyle = customization);
  }

  @override
  void set3DBuildingsEnabled(bool enabled) {}

  @override
  void setPmtilesUrl(String url) {}

  @override
  void setLightingMode(KartaVisualMode mode) {
    if (!mounted || _lightingMode == mode) return;
    setState(() => _lightingMode = mode);
  }

  @override
  void setDrivingSpeed({
    required double speedKmh,
    required bool declutterMinorLabels,
  }) {}

  @override
  void setLookAroundOrbit({
    required Coordinate center,
    required double bearingDeg,
    required bool active,
  }) {
    if (!mounted) return;
    setState(() {
      _center = center;
      _bearing = bearingDeg;
      _pitch = active ? 76.0 : 52.0;
    });
  }

  @override
  void setThermalRenderProfile({
    required int targetFps,
    required bool enable3DBuildings,
    required bool pausedForProjection,
  }) {
    if (!mounted) return;
    if (_pausedForProjection != pausedForProjection) {
      setState(() => _pausedForProjection = pausedForProjection);
    }
  }

  @override
  void prefetchVectorTiles(List<VectorTileCoord> tiles) {}

  @override
  void setFeaturedPlaces(List<KartaMapFeaturedPin> places) {}

  @override
  void setMapLanguage(String languageCode) {}
}

class _VectorProjectionFallbackPainter extends CustomPainter {
  const _VectorProjectionFallbackPainter({
    required this.palette,
    required this.center,
    required this.zoom,
    required this.pitch,
    required this.bearing,
    required this.routes,
    required this.selectedIdx,
    required this.stops,
    required this.hazards,
    required this.fuelPins,
    required this.carpoolOverlay,
    required this.userLocation,
    required this.droppedPin,
    required this.vehicleCoord,
    required this.vehicleBearing,
    required this.vehicleVisible,
    required this.vehicleStyle,
  });

  final KartaPalette palette;
  final Coordinate center;
  final double zoom;
  final double pitch;
  final double bearing;
  final List<List<Coordinate>> routes;
  final int selectedIdx;
  final List<KartaMapStopPin> stops;
  final List<HazardRecord> hazards;
  final List<FuelStationComparison> fuelPins;
  final CarpoolMapOverlay? carpoolOverlay;
  final Coordinate? userLocation;
  final Coordinate? droppedPin;
  final Coordinate? vehicleCoord;
  final double vehicleBearing;
  final bool vehicleVisible;
  final KartaVehicleCustomization vehicleStyle;

  Offset _project(Coordinate c, Size size) {
    final scale = math.pow(2, zoom) * 0.45;
    final dx = (c.lon - center.lon) * scale;
    final dy = -(c.lat - center.lat) * scale;
    return Offset(size.width * 0.5 + dx, size.height * 0.5 + dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = palette.borderSubtle.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var i = 0; i < routes.length; i++) {
      final line = routes[i];
      if (line.length < 2) continue;
      final isSelected = i == selectedIdx;
      final p = Path();
      final first = _project(line.first, size);
      p.moveTo(first.dx, first.dy);
      for (var k = 1; k < line.length; k++) {
        final pt = _project(line[k], size);
        p.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = isSelected ? palette.accentPrimary : palette.borderStrong
          ..strokeWidth = isSelected ? 5.5 : 3.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (final stop in stops) {
      final pt = _project(stop.coordinate, size);
      canvas.drawCircle(pt, 7, Paint()..color = palette.accentPrimary);
      canvas.drawCircle(pt, 3, Paint()..color = palette.textPrimary);
    }

    for (final haz in hazards) {
      final pt = _project(haz.coordinate, size);
      final color = _colorForHazardRank(_hazardSeverityRank(haz.category));
      canvas.drawCircle(pt, 12, Paint()..color = color.withValues(alpha: 0.26));
      canvas.drawCircle(pt, 6, Paint()..color = color);
    }

    for (final fuel in fuelPins) {
      final pt = _project(fuel.coordinate, size);
      final c = fuel.isCheapest ? palette.statusClear : palette.accentPrimary;
      canvas.drawCircle(pt, fuel.isCheapest ? 7 : 5.5, Paint()..color = c);
    }

    if (carpoolOverlay != null) {
      final o = _project(carpoolOverlay!.originZoneCenter, size);
      final d = _project(carpoolOverlay!.destZoneCenter, size);
      final ringPaint = Paint()
        ..color = palette.accentPrimary.withValues(alpha: 0.24)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(o, 22, ringPaint);
      canvas.drawCircle(d, 22, ringPaint);
    }

    if (userLocation != null) {
      final pt = _project(userLocation!, size);
      canvas.drawCircle(pt, 16, Paint()..color = const Color(0x382D7FF9));
      canvas.drawCircle(pt, 8, Paint()..color = Colors.white);
      canvas.drawCircle(pt, 5.5, Paint()..color = const Color(0xFF2D7FF9));
    }

    if (droppedPin != null) {
      final pt = _project(droppedPin!, size);
      canvas.drawCircle(pt, 8, Paint()..color = palette.statusAlert);
      canvas.drawCircle(pt, 3.2, Paint()..color = Colors.white);
    }

    if (vehicleVisible && vehicleCoord != null) {
      final pt = _project(vehicleCoord!, size);
      canvas.drawCircle(pt, 14, Paint()..color = palette.accentGlow);
      canvas.drawCircle(pt, 6, Paint()..color = palette.accentBright);
    }
  }

  int _hazardSeverityRank(HazardCategory cat) => switch (cat) {
        HazardCategory.roadClosure || HazardCategory.accident => 3,
        HazardCategory.police => 2,
        _ => 1,
      };

  Color _colorForHazardRank(int rank) => switch (rank) {
        3 => palette.statusAlert,
        2 => palette.statusInfo,
        _ => palette.statusCaution,
      };

  @override
  bool shouldRepaint(covariant _VectorProjectionFallbackPainter oldDelegate) => true;
}
