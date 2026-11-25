import 'dart:async';
import 'dart:js_interop';

import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import 'package:web/web.dart' as web;

import 'live_location_platform.dart';

PlatformLiveLocationService createPlatformLiveLocationService() =>
    _WebLiveLocationService();

class _WebLiveLocationService implements PlatformLiveLocationService {
  final StreamController<GpsFix> _controller = StreamController<GpsFix>.broadcast();
  int? _watchId;
  double _lastBearing = 0.0;

  @override
  bool get isSupported {
    try {
      // Accessing navigator.geolocation verifies W3C Geolocation availability
      final _ = web.window.navigator.geolocation;
      return true;
    } catch (_) {
      return false;
    }
  }

  GpsFix _convertPosition(web.GeolocationPosition pos) {
    final c = pos.coords;
    final heading = c.heading;
    if (heading != null && !heading.isNaN && heading >= 0) {
      _lastBearing = heading.toDouble();
    }
    final rawSpeedMs = c.speed;
    final speedKmh = (rawSpeedMs != null && !rawSpeedMs.isNaN && rawSpeedMs >= 0)
        ? rawSpeedMs.toDouble() * 3.6
        : 0.0;
    final accuracy = c.accuracy.isNaN ? 15.0 : c.accuracy.toDouble();

    return GpsFix(
      coordinate: Coordinate(
        lat: c.latitude.toDouble(),
        lon: c.longitude.toDouble(),
      ),
      bearingDeg: _lastBearing,
      speedKmh: speedKmh,
      accuracyMeters: accuracy,
      timestamp: DateTime.now(),
      isSimulated: false,
    );
  }

  @override
  Future<GpsFix?> getCurrentPosition() async {
    if (!isSupported) return null;
    final completer = Completer<GpsFix?>();
    try {
      final geo = web.window.navigator.geolocation;
      geo.getCurrentPosition(
        ((web.GeolocationPosition pos) {
          if (!completer.isCompleted) {
            completer.complete(_convertPosition(pos));
          }
        }).toJS,
        ((web.GeolocationPositionError err) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        }).toJS,
        web.PositionOptions(
          enableHighAccuracy: true,
          timeout: 12000,
          maximumAge: 4000,
        ),
      );
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future.timeout(
      const Duration(seconds: 13),
      onTimeout: () => null,
    );
  }

  @override
  Stream<GpsFix> watchPosition({
    void Function(String errorCode, String message)? onError,
  }) {
    stopWatching();
    if (!isSupported) {
      onError?.call('unavailable', 'Geolocation API unavailable in this browser.');
      return _controller.stream;
    }

    try {
      final geo = web.window.navigator.geolocation;
      _watchId = geo.watchPosition(
        ((web.GeolocationPosition pos) {
          if (!_controller.isClosed) {
            _controller.add(_convertPosition(pos));
          }
        }).toJS,
        ((web.GeolocationPositionError err) {
          final code = switch (err.code) {
            1 => 'denied',
            2 => 'unavailable',
            3 => 'timeout',
            _ => 'error',
          };
          onError?.call(code, err.message);
        }).toJS,
        web.PositionOptions(
          enableHighAccuracy: true,
          timeout: 15000,
          maximumAge: 3000,
        ),
      );
    } catch (e) {
      onError?.call('unavailable', '$e');
    }
    return _controller.stream;
  }

  @override
  void stopWatching() {
    if (_watchId != null) {
      try {
        web.window.navigator.geolocation.clearWatch(_watchId!);
      } catch (_) {}
      _watchId = null;
    }
  }

  @override
  void dispose() {
    stopWatching();
    _controller.close();
  }
}
