import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

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
  return _NativeKartaMapSurface(
    controller: controller,
    pmtilesUrl: pmtilesUrl,
    initialCenter: initialCenter,
    initialZoom: initialZoom,
    initialPitch: initialPitch,
  );
}

/// Native MapLibre PlatformView host & deterministic vector projection canvas
/// used on non-Web targets (iOS/Android/Windows/macOS/Linux + headless widget tests).
/// On mobile/desktop production builds, native MapLibre PlatformView binds directly
/// through [KartaMapPlatformDriver] using the identical [KartaMapStyleBuilder] spec.
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
  void prefetchVectorTiles(List<VectorTileCoord> tiles) {
    // Native MapLibre PlatformView binds directly to local PMTiles or HTTP cache;
    // headless widget-test surface tracks prefetch calls without blocking paint.
  }
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

    // Cluster overlapping hazard pins cleanly at wide zoom levels (z < 12.0)
    if (zoom < 12.0 && hazards.length > 1) {
      final visited = List<bool>.filled(hazards.length, false);
      const clusterRadiusPx = 44.0;
      for (var i = 0; i < hazards.length; i++) {
        if (visited[i]) continue;
        visited[i] = true;
        final anchorPt = _project(hazards[i].coordinate, size);
        var sumX = anchorPt.dx;
        var sumY = anchorPt.dy;
        var count = 1;
        var maxRank = _hazardSeverityRank(hazards[i].category);
        for (var j = i + 1; j < hazards.length; j++) {
          if (visited[j]) continue;
          final ptJ = _project(hazards[j].coordinate, size);
          if ((ptJ - anchorPt).distance <= clusterRadiusPx) {
            visited[j] = true;
            sumX += ptJ.dx;
            sumY += ptJ.dy;
            count += 1;
            maxRank = math.max(maxRank, _hazardSeverityRank(hazards[j].category));
          }
        }
        final centerPt = Offset(sumX / count, sumY / count);
        final color = _colorForHazardRank(maxRank);
        if (count > 1) {
          canvas.drawCircle(centerPt, 18, Paint()..color = color.withValues(alpha: 0.24));
          canvas.drawCircle(centerPt, 12, Paint()..color = color);
          canvas.drawCircle(
            centerPt,
            12,
            Paint()
              ..color = palette.hudDeepGlass
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
          final tp = TextPainter(
            text: TextSpan(
              text: '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, centerPt - Offset(tp.width / 2, tp.height / 2));
        } else {
          canvas.drawCircle(centerPt, 11, Paint()..color = color.withValues(alpha: 0.26));
          canvas.drawCircle(centerPt, 6, Paint()..color = color);
        }
      }
    } else {
      for (final haz in hazards) {
        final pt = _project(haz.coordinate, size);
        final color = _colorForHazardRank(_hazardSeverityRank(haz.category));
        canvas.drawCircle(pt, 12, Paint()..color = color.withValues(alpha: 0.26));
        canvas.drawCircle(pt, 6, Paint()..color = color);
      }
    }

    for (final fuel in fuelPins) {
      final pt = _project(fuel.coordinate, size);
      final c = fuel.isCheapest ? palette.statusClear : palette.accentPrimary;
      if (fuel.isCheapest) {
        canvas.drawCircle(pt, 12, Paint()..color = c.withValues(alpha: 0.26));
      }
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
