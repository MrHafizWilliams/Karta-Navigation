import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import '../cache/predictive_tile_prefetcher.dart';
import '../models/map_types.dart';

/// Platform driver contract implemented by Web (MapLibre GL JS + PMTiles) and
/// Native (MapLibre Native iOS/Android/Desktop).
abstract class KartaMapPlatformDriver {
  void easeCamera({
    required Coordinate center,
    double? zoom,
    double? pitch,
    double? bearing,
    int durationMs = 600,
    double paddingTop = 0,
    double paddingBottom = 0,
    double paddingLeft = 0,
  });

  void fitBounds({
    required double minLon,
    required double minLat,
    required double maxLon,
    required double maxLat,
    double paddingLeft = 420,
    double paddingTop = 80,
    double paddingRight = 80,
    double paddingBottom = 100,
  });

  void setRoutes({
    required List<List<Coordinate>> routePolylines,
    required int selectedIndex,
    int? tollFreeIndex,
    required List<KartaMapStopPin> stops,
    List<KartaMapRouteCallout> callouts = const <KartaMapRouteCallout>[],
    List<KartaMapTurnArrow> turnArrows = const <KartaMapTurnArrow>[],
  });

  void setTurnArrows(List<KartaMapTurnArrow> turnArrows);
  void setSavedPlaces(List<KartaMapSavedPlacePin> savedPlaces);

  void setPois(List<PoiItem> pois);
  void setTollGantries(List<GantryInfo> gantries);
  void setHazards(List<HazardRecord> hazards);
  void setTrafficSegments({
    required List<Coordinate> routePoints,
    required List<CongestionSegment> segments,
  });
  void setFuelPins(List<FuelStationComparison> stations);
  void setCarpoolOverlay(CarpoolMapOverlay? overlay);
  void setUserLocation({
    required Coordinate? coordinate,
    double? headingDeg,
    double accuracyMeters = 15.0,
    bool visible = true,
  });
  void setDroppedPin({
    required Coordinate? coordinate,
    String? label,
  });
  void setVehiclePose({
    required Coordinate coordinate,
    required double bearingDeg,
    required double speedKmh,
    required bool visible,
  });

  void setVehicleCustomization(KartaVehicleCustomization customization);
  void set3DBuildingsEnabled(bool enabled);
  void setPmtilesUrl(String url);
  void setLightingMode(KartaVisualMode mode);
  void setDrivingSpeed({
    required double speedKmh,
    required bool declutterMinorLabels,
  });
  void setLookAroundOrbit({
    required Coordinate center,
    required double bearingDeg,
    required bool active,
  });

  /// Applies adaptive FPS, 3D building shedding, and dual-screen companion
  /// GPU throttling from [ThermalAdaptationController].
  void setThermalRenderProfile({
    required int targetFps,
    required bool enable3DBuildings,
    required bool pausedForProjection,
  });

  /// Warms vector tiles ahead of the active route corridor and probable next turns
  /// so pitched 3D views never encounter late tile pop-in at highway speeds.
  void prefetchVectorTiles(List<VectorTileCoord> tiles);
}

/// Platform-agnostic Map Controller keeping all Flutter UI decoupled from
/// MapLibre JS / MapLibre Native internals.
class KartaMapController extends ChangeNotifier {
  KartaMapPlatformDriver? _driver;
  final PredictiveTilePrefetcher tilePrefetcher = PredictiveTilePrefetcher();
  final CameraPhysicsModel cameraPhysics = CameraPhysicsModel(smoothingAlpha: 0.35);
  Coordinate? _lastPrefetchPoint;
  List<Coordinate> _activeTurnCoords = const <Coordinate>[];
  bool _offlinePrefetchMuted = false;

  bool _isReady = false;
  bool _is3DEnabled = true;
  bool _userPreferred3D = true;
  bool _isCameraLocked = false;
  KartaVisualMode _lightingMode = KartaVisualMode.obsidianNight;
  double _currentSpeedKmh = 0.0;
  bool _minorLabelsDecluttered = false;
  int _targetFps = 60;
  bool _isCompanionProjected = false;
  bool _isCanvasPausedForThermal = false;
  DateTime? _lastFollowFrameAt;
  double _pitch = 52.0;
  double _bearing = 0.0;
  double _zoom = 6.2;
  Coordinate _center = const Coordinate(lat: 3.1579, lon: 101.7116);
  KartaVehicleCustomization _vehicleCustomization = const KartaVehicleCustomization();

  // Buffered state applied once map finishes initializing
  List<List<Coordinate>> _lastPolylines = const <List<Coordinate>>[];
  int _lastSelectedIdx = 0;
  int? _lastTollFreeIdx;
  List<KartaMapStopPin> _lastStops = const <KartaMapStopPin>[];
  List<KartaMapRouteCallout> _lastRouteCallouts = const <KartaMapRouteCallout>[];
  List<KartaMapTurnArrow> _lastTurnArrows = const <KartaMapTurnArrow>[];
  List<KartaMapSavedPlacePin> _lastSavedPlaces = const <KartaMapSavedPlacePin>[];
  List<PoiItem> _lastPois = const <PoiItem>[];
  List<HazardRecord> _lastHazards = const <HazardRecord>[];
  List<FuelStationComparison> _lastFuelPins = const <FuelStationComparison>[];
  CarpoolMapOverlay? _lastCarpoolOverlay;
  Coordinate? _userLocation;
  double? _userHeadingDeg;
  double _userAccuracyMeters = 15.0;
  bool _userLocationVisible = false;
  Coordinate? _droppedPinCoord;
  String? _droppedPinLabel;

  final StreamController<Coordinate> _mapTapController = StreamController<Coordinate>.broadcast();
  final StreamController<void> _userDragController = StreamController<void>.broadcast();
  final StreamController<int> _fuelPinTapController = StreamController<int>.broadcast();
  final StreamController<String> _hazardPinTapController = StreamController<String>.broadcast();
  final StreamController<int> _poiPinTapController = StreamController<int>.broadcast();
  final StreamController<int> _routeCalloutTapController = StreamController<int>.broadcast();
  final StreamController<KartaViewportBounds> _viewportChangedController =
      StreamController<KartaViewportBounds>.broadcast();

  bool get isReady => _isReady;
  bool get is3DEnabled => _is3DEnabled;
  bool get isCameraLocked => _isCameraLocked;
  KartaVisualMode get lightingMode => _lightingMode;
  double get currentSpeedKmh => _currentSpeedKmh;
  bool get minorLabelsDecluttered => _minorLabelsDecluttered;
  int get targetFps => _targetFps;
  bool get isCompanionProjected => _isCompanionProjected;
  bool get isCanvasPausedForThermal => _isCanvasPausedForThermal;
  double get pitch => _pitch;
  double get bearing => _bearing;
  double get zoom => _zoom;
  Coordinate get center => _center;
  Coordinate? get userLocation => _userLocation;
  KartaVehicleCustomization get vehicleCustomization => _vehicleCustomization;
  List<PoiItem> get pois => List<PoiItem>.unmodifiable(_lastPois);
  List<HazardRecord> get hazards => List<HazardRecord>.unmodifiable(_lastHazards);
  List<FuelStationComparison> get fuelPins => List<FuelStationComparison>.unmodifiable(_lastFuelPins);

  Stream<Coordinate> get onMapTap => _mapTapController.stream;
  Stream<void> get onUserDragStart => _userDragController.stream;
  Stream<int> get onFuelPinTap => _fuelPinTapController.stream;
  Stream<String> get onHazardPinTap => _hazardPinTapController.stream;
  Stream<int> get onPoiPinTap => _poiPinTapController.stream;
  Stream<int> get onRouteCalloutTap => _routeCalloutTapController.stream;
  Stream<KartaViewportBounds> get onViewportChanged => _viewportChangedController.stream;

  void attachDriver(KartaMapPlatformDriver driver) {
    _driver = driver;
    _isReady = true;
    driver.setLightingMode(_lightingMode);
    driver.set3DBuildingsEnabled(_is3DEnabled);
    driver.setDrivingSpeed(
      speedKmh: _currentSpeedKmh,
      declutterMinorLabels: _minorLabelsDecluttered,
    );
    driver.setThermalRenderProfile(
      targetFps: _targetFps,
      enable3DBuildings: _is3DEnabled,
      pausedForProjection: _isCanvasPausedForThermal,
    );
    driver.setVehicleCustomization(_vehicleCustomization);
    if (_lastPolylines.isNotEmpty) {
      driver.setRoutes(
        routePolylines: _lastPolylines,
        selectedIndex: _lastSelectedIdx,
        tollFreeIndex: _lastTollFreeIdx,
        stops: _lastStops,
        callouts: _lastRouteCallouts,
        turnArrows: _lastTurnArrows,
      );
    }
    if (_lastSavedPlaces.isNotEmpty) driver.setSavedPlaces(_lastSavedPlaces);
    if (_lastPois.isNotEmpty) driver.setPois(_lastPois);
    if (_lastHazards.isNotEmpty) driver.setHazards(_lastHazards);
    if (_lastFuelPins.isNotEmpty) driver.setFuelPins(_lastFuelPins);
    if (_lastCarpoolOverlay != null) driver.setCarpoolOverlay(_lastCarpoolOverlay);
    if (_userLocation != null) {
      driver.setUserLocation(
        coordinate: _userLocation,
        headingDeg: _userHeadingDeg,
        accuracyMeters: _userAccuracyMeters,
        visible: _userLocationVisible,
      );
    }
    if (_droppedPinCoord != null) {
      driver.setDroppedPin(coordinate: _droppedPinCoord, label: _droppedPinLabel);
    }
    notifyListeners();
  }

  void detachDriver() {
    _driver = null;
    _isReady = false;
  }

  void notifyMapTapped(Coordinate coord) {
    if (!_mapTapController.isClosed) _mapTapController.add(coord);
  }

  void notifyFuelPinTapped(int poiId) {
    if (!_fuelPinTapController.isClosed) _fuelPinTapController.add(poiId);
  }

  void notifyHazardPinTapped(String hazardId) {
    if (!_hazardPinTapController.isClosed) _hazardPinTapController.add(hazardId);
  }

  void notifyPoiPinTapped(int poiId) {
    if (!_poiPinTapController.isClosed) _poiPinTapController.add(poiId);
  }

  void notifyRouteCalloutTapped(int routeIndex) {
    if (!_routeCalloutTapController.isClosed) _routeCalloutTapController.add(routeIndex);
  }

  void notifyViewportChanged(KartaViewportBounds bounds) {
    if (!_viewportChangedController.isClosed) {
      _viewportChangedController.add(bounds);
    }
  }

  void notifyUserDragged() {
    if (_isCameraLocked) {
      _isCameraLocked = false;
      notifyListeners();
    }
    if (!_userDragController.isClosed) _userDragController.add(null);
  }

  /// Switches the live MapLibre style between Obsidian Night and High-Glare
  /// Tropical Daylight without losing active route polylines, hazards, or 3D avatar.
  void setLightingMode(KartaVisualMode mode) {
    if (_lightingMode == mode) return;
    _lightingMode = mode;
    _driver?.setLightingMode(mode);
    notifyListeners();
  }

  /// Feeds live driving speed into the map engine to smoothly declutter minor
  /// street labels above 60 km/h (with 55 km/h hysteresis).
  void setDrivingSpeed(double speedKmh) {
    final target = CameraPhysicsModel.computeTarget(
      speedKmh: speedKmh,
      is3DEnabled: _is3DEnabled,
      previousDeclutterActive: _minorLabelsDecluttered,
    );
    final nextDeclutter = target.declutterMinorLabels;
    final changed = (speedKmh - _currentSpeedKmh).abs() >= 1.0 ||
        nextDeclutter != _minorLabelsDecluttered;
    _currentSpeedKmh = speedKmh;
    _minorLabelsDecluttered = nextDeclutter;
    if (changed) {
      _driver?.setDrivingSpeed(
        speedKmh: speedKmh,
        declutterMinorLabels: nextDeclutter,
      );
      notifyListeners();
    }
  }

  void easeTo({
    required Coordinate center,
    double? zoom,
    double? pitch,
    double? bearing,
    int durationMs = 650,
    double paddingTop = 0,
    double paddingBottom = 0,
    double paddingLeft = 0,
  }) {
    _center = center;
    if (zoom != null) _zoom = zoom;
    if (pitch != null) _pitch = pitch;
    if (bearing != null) _bearing = bearing;
    _driver?.easeCamera(
      center: center,
      zoom: zoom,
      pitch: pitch,
      bearing: bearing,
      durationMs: durationMs,
      paddingTop: paddingTop,
      paddingBottom: paddingBottom,
      paddingLeft: paddingLeft,
    );
    notifyListeners();
  }

  /// Continuous speed-adaptive pitched camera tracking during active turn-by-turn
  /// navigation. Smoothly interpolates zoom (17.6 city → 15.0 highway) and pitch
  /// (48° city → 66° North-South Expressway) via [CameraPhysicsModel] while
  /// decluttering minor street labels above 60 km/h.
  void followNavigationFix(
    GpsFix fix, {
    bool forceLock = false,
    double? distanceToManeuverMeters,
  }) {
    if (forceLock && !_isCameraLocked) {
      _isCameraLocked = true;
      notifyListeners();
    }
    _center = fix.coordinate;
    _bearing = fix.bearingDeg;

    setDrivingSpeed(fix.speedKmh);

    if (_isCanvasPausedForThermal) {
      // Head unit owns MapLibre rendering while phone GPU is paused for thermal cooling.
      return;
    }

    if (_targetFps > 0 && _targetFps < 60 && !forceLock) {
      final minDeltaMs = (1000 / _targetFps).round();
      final now = DateTime.now();
      if (_lastFollowFrameAt != null &&
          now.difference(_lastFollowFrameAt!).inMilliseconds < minDeltaMs) {
        return;
      }
      _lastFollowFrameAt = now;
    }

    _driver?.setVehiclePose(
      coordinate: fix.coordinate,
      bearingDeg: fix.bearingDeg,
      speedKmh: fix.speedKmh,
      visible: true,
    );

    if (!_isCameraLocked) return;

    final pose = cameraPhysics.step(
      speedKmh: fix.speedKmh,
      is3DEnabled: _is3DEnabled,
      distanceToManeuverMeters: distanceToManeuverMeters,
    );

    _zoom = pose.zoom;
    _pitch = pose.pitchDeg;

    _driver?.easeCamera(
      center: fix.coordinate,
      zoom: pose.zoom,
      pitch: pose.pitchDeg,
      bearing: fix.bearingDeg,
      durationMs: _isCompanionProjected ? 420 : 280,
      paddingTop: pose.paddingTopPx,
      paddingBottom: pose.paddingBottomPx,
    );

    // Predictive vector tile pre-fetching every ~350m along active highway corridor
    if (_lastPolylines.isNotEmpty) {
      final movedEnough = _lastPrefetchPoint == null ||
          haversineMeters(_lastPrefetchPoint!, fix.coordinate) >= 350.0;
      if (movedEnough) {
        _lastPrefetchPoint = fix.coordinate;
        prefetchCorridorAhead(
          currentPosition: fix.coordinate,
          speedKmh: fix.speedKmh,
          isOffline: _offlinePrefetchMuted,
        );
      }
    }
  }

  void setOfflinePrefetchMuted(bool muted) {
    _offlinePrefetchMuted = muted;
  }

  /// Plans and dispatches speed-adaptive vector tile pre-fetching along the active
  /// route corridor + probable next turns (±60 deg alternate-exit fan-out).
  PrefetchBatchPlan prefetchCorridorAhead({
    required Coordinate currentPosition,
    double speedKmh = 95.0,
    bool isOffline = false,
  }) {
    if (_lastPolylines.isEmpty) {
      return const PrefetchBatchPlan(
        tilesToFetch: <VectorTileCoord>[],
        lookaheadKm: 0,
        zoomLevels: <int>[],
        cacheHitsSkipped: 0,
        planningMs: 0,
      );
    }
    final activeLine = _lastPolylines[_lastSelectedIdx.clamp(0, _lastPolylines.length - 1)];
    final maxBatch = _targetFps <= 20 ? 16 : 36;
    final plan = tilePrefetcher.planCorridorPrefetch(
      routePoints: activeLine,
      currentPosition: currentPosition,
      speedKmh: speedKmh,
      upcomingTurnCoords: _activeTurnCoords,
      maxBatchSize: maxBatch,
      isOfflineMode: isOffline || _isCanvasPausedForThermal,
    );
    if (plan.tilesToFetch.isNotEmpty) {
      _driver?.prefetchVectorTiles(plan.tilesToFetch);
    }
    return plan;
  }

  /// Applies adaptive thermal throttling & dual-screen projection budgets from
  /// [ThermalAdaptationController] to the phone/desktop MapLibre renderer.
  void applyThermalRenderProfile(ThermalRenderProfile profile) {
    final effective3D = _userPreferred3D && profile.enablePhone3DBuildings;
    final changed = _targetFps != profile.phoneTargetFps ||
        _isCompanionProjected != profile.isProjectedToHeadUnit ||
        _isCanvasPausedForThermal != profile.pausePhoneMapCanvas ||
        _is3DEnabled != effective3D;

    _targetFps = profile.phoneTargetFps;
    _isCompanionProjected = profile.isProjectedToHeadUnit;
    _isCanvasPausedForThermal = profile.pausePhoneMapCanvas;
    _is3DEnabled = effective3D;
    if (!effective3D && _pitch > 0) {
      _pitch = 0.0;
    } else if (effective3D && _pitch == 0.0) {
      _pitch = 56.0;
    }

    _driver?.set3DBuildingsEnabled(_is3DEnabled);
    _driver?.setThermalRenderProfile(
      targetFps: _targetFps,
      enable3DBuildings: _is3DEnabled,
      pausedForProjection: _isCanvasPausedForThermal,
    );

    if (changed) {
      notifyListeners();
    }
  }

  void setCameraLocked(bool locked) {
    _isCameraLocked = locked;
    notifyListeners();
  }

  void hideVehiclePuck() {
    setDrivingSpeed(0.0);
    _driver?.setVehiclePose(
      coordinate: _center,
      bearingDeg: 0,
      speedKmh: 0,
      visible: false,
    );
  }

  void toggle3DBuildings() {
    _userPreferred3D = !_userPreferred3D;
    _is3DEnabled = _userPreferred3D && !_isCompanionProjected;
    _pitch = _is3DEnabled ? 56.0 : 0.0;
    _driver?.set3DBuildingsEnabled(_is3DEnabled);
    _driver?.easeCamera(
      center: _center,
      pitch: _pitch,
      durationMs: 450,
    );
    notifyListeners();
  }

  void resetNorth() {
    _bearing = 0.0;
    _driver?.easeCamera(center: _center, bearing: 0.0, durationMs: 380);
    notifyListeners();
  }

  /// Builds road-snapped curved 2D turn direction arrows along [route].
  static List<KartaMapTurnArrow> buildTurnArrowsForRoute(
    CandidateRoute route, {
    RouteManeuver? activeManeuver,
    RouteManeuver? nextManeuver,
    int maxArrows = 10,
  }) {
    final geom = RouteGeometryIndex.fromRoute(route);
    if (geom.points.length < 2 || geom.totalMeters < 20) {
      return const <KartaMapTurnArrow>[];
    }

    const nonTurnTypes = <int>{0, 1, 2, 3, 4, 5, 6, 8};
    final arrows = <KartaMapTurnArrow>[];

    KartaMapTurnArrow? buildForManeuver(int legIdx, RouteManeuver man, {required bool isActive}) {
      if (nonTurnTypes.contains(man.type)) return null;
      final dTurn = geom.distanceAtLegShapeIndex(legIdx, man.beginShapeIndex);
      if (dTurn <= 8 || dTurn >= geom.totalMeters - 8) return null;

      final halfSpan = isActive ? 42.0 : 32.0;
      final dStart = (dTurn - halfSpan).clamp(0.0, geom.totalMeters);
      final dEnd = (dTurn + halfSpan).clamp(0.0, geom.totalMeters);
      if (dEnd - dStart < 12.0) return null;

      const sampleCount = 9;
      final shaft = <Coordinate>[];
      for (var s = 0; s < sampleCount; s++) {
        final d = dStart + (dEnd - dStart) * (s / (sampleCount - 1));
        shaft.add(geom.sampleAtDistance(d).coordinate);
      }
      if (shaft.length < 2) return null;
      final tipBearing = initialBearingDeg(shaft[shaft.length - 2], shaft.last);
      return KartaMapTurnArrow(
        shaftPoints: shaft,
        tipCoordinate: shaft.last,
        tipBearingDeg: tipBearing,
        isActive: isActive,
        maneuverType: man.type,
      );
    }

    // Active navigation mode: emphasize the immediate next maneuver & following turn
    if (activeManeuver != null) {
      for (var l = 0; l < route.legs.length; l++) {
        for (final man in route.legs[l].maneuvers) {
          final isCurrent = man.beginShapeIndex == activeManeuver.beginShapeIndex &&
              man.type == activeManeuver.type;
          final isNext = nextManeuver != null &&
              man.beginShapeIndex == nextManeuver.beginShapeIndex &&
              man.type == nextManeuver.type;
          if (isCurrent || isNext) {
            final arrow = buildForManeuver(l, man, isActive: isCurrent);
            if (arrow != null) arrows.add(arrow);
          }
        }
      }
      if (arrows.isNotEmpty) return arrows;
    }

    // Route preview mode: extract evenly distributed major turns along the route
    for (var l = 0; l < route.legs.length; l++) {
      for (final man in route.legs[l].maneuvers) {
        if (arrows.length >= maxArrows) break;
        final arrow = buildForManeuver(l, man, isActive: arrows.isEmpty);
        if (arrow != null) arrows.add(arrow);
      }
    }
    return arrows;
  }

  /// Builds Google Maps / Waze-style route ETA / delta callouts anchored along each route.
  static List<KartaMapRouteCallout> buildRouteCallouts(
    List<CandidateRoute> routes,
    List<List<Coordinate>> decoded,
    int selectedIndex,
  ) {
    if (routes.isEmpty || decoded.isEmpty) return const <KartaMapRouteCallout>[];
    final selectedSec = routes[selectedIndex.clamp(0, routes.length - 1)].durationSeconds;
    final callouts = <KartaMapRouteCallout>[];

    for (var i = 0; i < routes.length && i < decoded.length; i++) {
      final pts = decoded[i];
      if (pts.length < 2) continue;
      final r = routes[i];
      final isSel = i == selectedIndex;
      // Stagger anchor fraction across routes so primary & alternate bubbles never collide
      final anchorFrac = isSel ? 0.50 : (i % 2 == 1 ? 0.36 : 0.64);
      final anchorIdx = (pts.length * anchorFrac).round().clamp(1, pts.length - 1);
      final durLabel = RegionalCurrencyFormatter.formatDuration(r.durationSeconds);
      String label;
      String? sublabel;
      if (isSel) {
        label = durLabel;
        sublabel = r.primaryCorridorName ?? 'Fastest';
      } else {
        final deltaMin = ((r.durationSeconds - selectedSec) / 60.0).round();
        if (deltaMin > 0) {
          label = '$deltaMin min slower';
        } else if (deltaMin < 0) {
          label = '${deltaMin.abs()} min faster';
        } else {
          label = 'Similar ETA';
        }
        sublabel = r.primaryCorridorName ?? durLabel;
      }
      callouts.add(
        KartaMapRouteCallout(
          routeIndex: i,
          label: label,
          sublabel: sublabel,
          isSelected: isSel,
          coordinate: pts[anchorIdx],
        ),
      );
    }
    return callouts;
  }

  void setRoutes({
    required List<CandidateRoute> routes,
    required int selectedIndex,
    int? tollFreeIndex,
    required List<KartaMapStopPin> stops,
    bool fitToRoutes = true,
  }) {
    final decoded = routes.map((r) => RouteGeometryIndex.fromRoute(r).points).toList();
    final callouts = buildRouteCallouts(routes, decoded, selectedIndex);
    final turnArrows = routes.isNotEmpty
        ? buildTurnArrowsForRoute(routes[selectedIndex.clamp(0, routes.length - 1)])
        : const <KartaMapTurnArrow>[];

    _lastPolylines = decoded;
    _lastSelectedIdx = selectedIndex;
    _lastTollFreeIdx = tollFreeIndex;
    _lastStops = stops;
    _lastRouteCallouts = callouts;
    _lastTurnArrows = turnArrows;
    _lastPrefetchPoint = null;

    // Extract upcoming maneuver coordinates on the selected route for next-turn tile fan-out
    if (routes.isNotEmpty) {
      final selRoute = routes[selectedIndex.clamp(0, routes.length - 1)];
      final geom = RouteGeometryIndex.fromRoute(selRoute);
      final turns = <Coordinate>[];
      for (var l = 0; l < selRoute.legs.length; l++) {
        for (final man in selRoute.legs[l].maneuvers) {
          if (man.type != 1 && man.type != 4 && man.type != 5 && man.type != 6) {
            final d = geom.distanceAtLegShapeIndex(l, man.beginShapeIndex);
            turns.add(geom.sampleAtDistance(d).coordinate);
          }
        }
      }
      _activeTurnCoords = turns;
    } else {
      _activeTurnCoords = const <Coordinate>[];
    }

    _driver?.setRoutes(
      routePolylines: decoded,
      selectedIndex: selectedIndex,
      tollFreeIndex: tollFreeIndex,
      stops: stops,
      callouts: callouts,
      turnArrows: turnArrows,
    );

    if (decoded.isNotEmpty) {
      final pts = decoded[selectedIndex.clamp(0, decoded.length - 1)];
      if (pts.length >= 2) {
        prefetchCorridorAhead(currentPosition: pts.first, speedKmh: 95.0);
      }
    }

    if (fitToRoutes && decoded.isNotEmpty) {
      final pts = decoded[selectedIndex.clamp(0, decoded.length - 1)];
      if (pts.length >= 2) {
        var minLat = pts.first.lat;
        var maxLat = pts.first.lat;
        var minLon = pts.first.lon;
        var maxLon = pts.first.lon;
        for (final p in pts) {
          if (p.lat < minLat) minLat = p.lat;
          if (p.lat > maxLat) maxLat = p.lat;
          if (p.lon < minLon) minLon = p.lon;
          if (p.lon > maxLon) maxLon = p.lon;
        }
        _driver?.fitBounds(
          minLon: minLon,
          minLat: minLat,
          maxLon: maxLon,
          maxLat: maxLat,
        );
      }
    }
  }

  void updateActiveTurnArrows({
    required CandidateRoute? route,
    RouteManeuver? currentManeuver,
    RouteManeuver? nextManeuver,
  }) {
    final arrows = route == null
        ? const <KartaMapTurnArrow>[]
        : buildTurnArrowsForRoute(
            route,
            activeManeuver: currentManeuver,
            nextManeuver: nextManeuver,
          );
    _lastTurnArrows = arrows;
    _driver?.setTurnArrows(arrows);
  }

  void setSavedPlaces(List<KartaMapSavedPlacePin> savedPlaces) {
    _lastSavedPlaces = savedPlaces;
    _driver?.setSavedPlaces(savedPlaces);
  }

  void clearRoutes() {
    _lastPolylines = const <List<Coordinate>>[];
    _lastStops = const <KartaMapStopPin>[];
    _lastRouteCallouts = const <KartaMapRouteCallout>[];
    _lastTurnArrows = const <KartaMapTurnArrow>[];
    _driver?.setRoutes(
      routePolylines: const <List<Coordinate>>[],
      selectedIndex: 0,
      stops: const <KartaMapStopPin>[],
      callouts: const <KartaMapRouteCallout>[],
      turnArrows: const <KartaMapTurnArrow>[],
    );
  }

  void setPois(List<PoiItem> pois) {
    _lastPois = pois;
    _driver?.setPois(pois);
  }

  void setTollGantries(List<GantryInfo> gantries) {
    // Toll gantry map symbols ("TOL RM", "ERP $", "BN B$") are disabled across Karta.
    _driver?.setTollGantries(const <GantryInfo>[]);
  }

  void setUserLocation({
    required Coordinate? coordinate,
    double? headingDeg,
    double accuracyMeters = 15.0,
    bool visible = true,
  }) {
    _userLocation = coordinate;
    _userHeadingDeg = headingDeg;
    _userAccuracyMeters = accuracyMeters;
    _userLocationVisible = visible && coordinate != null;
    _driver?.setUserLocation(
      coordinate: coordinate,
      headingDeg: headingDeg,
      accuracyMeters: accuracyMeters,
      visible: _userLocationVisible,
    );
    notifyListeners();
  }

  void setDroppedPin({
    required Coordinate? coordinate,
    String? label,
  }) {
    _droppedPinCoord = coordinate;
    _droppedPinLabel = label;
    _driver?.setDroppedPin(coordinate: coordinate, label: label);
    notifyListeners();
  }

  void setHazards(List<HazardRecord> hazards) {
    _lastHazards = hazards;
    _driver?.setHazards(hazards);
  }

  void setTrafficSegments({
    required List<Coordinate> routePoints,
    required List<CongestionSegment> segments,
  }) {
    _driver?.setTrafficSegments(routePoints: routePoints, segments: segments);
  }

  void setFuelPins(List<FuelStationComparison> stations) {
    _lastFuelPins = stations;
    _driver?.setFuelPins(stations);
  }

  void setCarpoolOverlay(CarpoolMapOverlay? overlay) {
    _lastCarpoolOverlay = overlay;
    _driver?.setCarpoolOverlay(overlay);
  }

  void updateVehicleCustomization(KartaVehicleCustomization customization) {
    _vehicleCustomization = customization;
    _driver?.setVehicleCustomization(customization);
    notifyListeners();
  }

  void setPmtilesUrl(String url) {
    _driver?.setPmtilesUrl(url);
  }

  void setLookAroundOrbit({
    required Coordinate center,
    required double bearingDeg,
    required bool active,
  }) {
    _driver?.setLookAroundOrbit(
      center: center,
      bearingDeg: bearingDeg,
      active: active,
    );
  }

  @override
  void dispose() {
    _mapTapController.close();
    _userDragController.close();
    _fuelPinTapController.close();
    _hazardPinTapController.close();
    _poiPinTapController.close();
    _routeCalloutTapController.close();
    _viewportChangedController.close();
    super.dispose();
  }
}
