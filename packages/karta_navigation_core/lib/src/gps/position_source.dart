import 'dart:async';
import 'dart:math' as math;
import 'package:karta_api_client/karta_api_client.dart';
import 'package:meta/meta.dart';
import '../geo/polyline6.dart';

@immutable
class GpsFix {
  const GpsFix({
    required this.coordinate,
    required this.bearingDeg,
    required this.speedKmh,
    required this.timestamp,
    this.accuracyMeters = 5.0,
    this.isSimulated = false,
  });

  final Coordinate coordinate;
  final double bearingDeg;
  final double speedKmh;
  final DateTime timestamp;
  final double accuracyMeters;
  final bool isSimulated;
}

/// Abstract position feed decoupled from UI and map rendering.
abstract class PositionSource {
  Stream<GpsFix> get stream;
  void dispose();
}

/// Real-time live GPS position source backed by browser W3C Geolocation or
/// native iOS/Android/Desktop GPS streams. Decoupled from UI and map layers.
class LiveGpsPositionSource implements PositionSource {
  LiveGpsPositionSource({Stream<GpsFix>? upstream, GpsFix? initialFix}) {
    if (initialFix != null) {
      _lastFix = initialFix;
      scheduleMicrotask(() {
        if (!_controller.isClosed) _controller.add(initialFix);
      });
    }
    if (upstream != null) {
      _sub = upstream.listen(
        (fix) {
          _lastFix = fix;
          if (!_controller.isClosed) _controller.add(fix);
        },
        onError: (_) {},
      );
    }
  }

  final StreamController<GpsFix> _controller = StreamController<GpsFix>.broadcast();
  StreamSubscription<GpsFix>? _sub;
  GpsFix? _lastFix;

  GpsFix? get lastFix => _lastFix;

  @override
  Stream<GpsFix> get stream => _controller.stream;

  void pushFix(GpsFix fix) {
    _lastFix = fix;
    if (!_controller.isClosed) _controller.add(fix);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}

/// Smooth 60fps puck interpolator between 1Hz/5Hz raw GPS ticks with
/// shortest-arc bearing slerp so the 3D Karta pin/vehicle glides seamlessly.
class GpsPuckInterpolator {
  GpsFix? _from;
  GpsFix? _to;
  DateTime? _transitionStart;
  Duration _transitionDuration = const Duration(milliseconds: 350);

  void pushFix(GpsFix next, {Duration smoothing = const Duration(milliseconds: 320)}) {
    final now = DateTime.now();
    _from = sampleAt(now) ?? next;
    _to = next;
    _transitionStart = now;
    _transitionDuration = smoothing;
  }

  GpsFix? sampleAt(DateTime now) {
    final to = _to;
    final from = _from;
    final start = _transitionStart;
    if (to == null) return null;
    if (from == null || start == null || _transitionDuration.inMilliseconds <= 0) {
      return to;
    }

    final elapsed = now.difference(start).inMilliseconds;
    final rawT = (elapsed / _transitionDuration.inMilliseconds).clamp(0.0, 1.0);
    // Smoothstep ease-out curve for crisp automotive puck glide
    final t = rawT * rawT * (3.0 - 2.0 * rawT);

    return GpsFix(
      coordinate: Coordinate(
        lat: from.coordinate.lat + (to.coordinate.lat - from.coordinate.lat) * t,
        lon: from.coordinate.lon + (to.coordinate.lon - from.coordinate.lon) * t,
      ),
      bearingDeg: lerpBearingDeg(from.bearingDeg, to.bearingDeg, t),
      speedKmh: from.speedKmh + (to.speedKmh - from.speedKmh) * t,
      timestamp: now,
      accuracyMeters: to.accuracyMeters,
      isSimulated: to.isSimulated,
    );
  }

  void reset() {
    _from = null;
    _to = null;
    _transitionStart = null;
  }
}

/// Deterministic GPS simulator that drives along a real Valhalla [CandidateRoute]
/// polyline for live HUD testing, demoing cross-border MY -> SG transitions,
/// and verifying dynamic speed/lane/toll updates without mocking route geometry.
class RoutePlaybackPositionSource implements PositionSource {
  RoutePlaybackPositionSource({
    required this.geometry,
    double speedMultiplier = 8.0,
    double baseCruiseKmh = 96.0,
  })  : _speedMultiplier = speedMultiplier,
        _baseCruiseKmh = baseCruiseKmh;

  final RouteGeometryIndex geometry;
  final StreamController<GpsFix> _controller = StreamController<GpsFix>.broadcast();

  Timer? _timer;
  double _distanceMeters = 0.0;
  double _speedMultiplier;
  double _baseCruiseKmh;
  double _overspeedBoostKmh = 0.0;
  bool _paused = false;

  @override
  Stream<GpsFix> get stream => _controller.stream;

  double get distanceMeters => _distanceMeters;
  double get progress => geometry.totalMeters > 0
      ? (_distanceMeters / geometry.totalMeters).clamp(0.0, 1.0)
      : 0.0;
  double get speedMultiplier => _speedMultiplier;
  double get baseCruiseKmh => _baseCruiseKmh;
  bool get isPaused => _paused;
  bool get overspeedDemoActive => _overspeedBoostKmh > 0;

  void start() {
    _timer?.cancel();
    _emitCurrent();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_paused || geometry.totalMeters <= 0) return;
      final activeSpeedKmh = _currentSimulatedSpeedKmh();
      final metersPerSec = (activeSpeedKmh / 3.6) * _speedMultiplier;
      _distanceMeters = math.min(geometry.totalMeters, _distanceMeters + metersPerSec * 0.1);
      _emitCurrent();
      if (_distanceMeters >= geometry.totalMeters) {
        _paused = true;
      }
    });
  }

  void setPaused(bool paused) {
    _paused = paused;
  }

  void setSpeedMultiplier(double mult) {
    _speedMultiplier = mult.clamp(1.0, 80.0);
  }

  void setBaseCruiseKmh(double kmh) {
    _baseCruiseKmh = kmh.clamp(18.0, 130.0);
    _emitCurrent();
  }

  void setOverspeedBoost(double extraKmh) {
    _overspeedBoostKmh = extraKmh.clamp(0.0, 45.0);
    _emitCurrent();
  }

  /// Jumps directly to a normalized progress fraction `[0.0, 1.0]` along the real route
  /// (e.g. Penang exit, KLCC stopover, Johor Causeway CIQ, Singapore CTE).
  void seekProgress(double fraction) {
    _distanceMeters = geometry.totalMeters * fraction.clamp(0.0, 1.0);
    _emitCurrent();
  }

  void seekDistanceMeters(double meters) {
    _distanceMeters = meters.clamp(0.0, geometry.totalMeters);
    _emitCurrent();
  }

  double _currentSimulatedSpeedKmh() {
    final base = _baseCruiseKmh + math.sin(_distanceMeters / 900.0) * 6.0;
    return (base + _overspeedBoostKmh).clamp(15.0, 155.0);
  }

  void _emitCurrent() {
    if (_controller.isClosed) return;
    final sample = geometry.sampleAtDistance(_distanceMeters);
    _controller.add(
      GpsFix(
        coordinate: sample.coordinate,
        bearingDeg: sample.bearingDeg,
        speedKmh: _currentSimulatedSpeedKmh(),
        timestamp: DateTime.now(),
        accuracyMeters: 3.0,
        isSimulated: true,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
