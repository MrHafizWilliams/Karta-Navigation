import 'dart:async';

import 'package:flutter/services.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import 'live_location_platform.dart';

PlatformLiveLocationService createPlatformLiveLocationService() =>
    _NativeLiveLocationService();

/// Native iOS / Android / Desktop GPS platform-channel bridge
/// (`com.karta.navigation/location` + `location_stream`).
/// Gracefully reports unavailable in headless widget tests without throwing.
class _NativeLiveLocationService implements PlatformLiveLocationService {
  static const MethodChannel _method = MethodChannel('com.karta.navigation/location');
  static const EventChannel _events = EventChannel('com.karta.navigation/location_stream');

  final StreamController<GpsFix> _controller = StreamController<GpsFix>.broadcast();
  StreamSubscription<dynamic>? _nativeSub;

  @override
  bool get isSupported => true;

  GpsFix? _parsePayload(dynamic raw) {
    if (raw is! Map) return null;
    final lat = (raw['lat'] as num?)?.toDouble();
    final lon = (raw['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return GpsFix(
      coordinate: Coordinate(lat: lat, lon: lon),
      bearingDeg: (raw['bearing'] as num?)?.toDouble() ?? 0.0,
      speedKmh: (raw['speed_kmh'] as num?)?.toDouble() ?? 0.0,
      accuracyMeters: (raw['accuracy_m'] as num?)?.toDouble() ?? 10.0,
      timestamp: DateTime.now(),
      isSimulated: false,
    );
  }

  @override
  Future<GpsFix?> getCurrentPosition() async {
    try {
      final raw = await _method.invokeMethod<dynamic>('getCurrentPosition');
      return _parsePayload(raw);
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<GpsFix> watchPosition({
    void Function(String errorCode, String message)? onError,
  }) {
    stopWatching();
    try {
      _nativeSub = _events.receiveBroadcastStream().listen(
        (event) {
          final fix = _parsePayload(event);
          if (fix != null && !_controller.isClosed) {
            _controller.add(fix);
          }
        },
        onError: (Object err) {
          onError?.call('unavailable', '$err');
        },
      );
    } on MissingPluginException {
      onError?.call('unavailable', 'Native location channel not bound.');
    } catch (e) {
      onError?.call('unavailable', '$e');
    }
    return _controller.stream;
  }

  @override
  void stopWatching() {
    _nativeSub?.cancel();
    _nativeSub = null;
  }

  @override
  void dispose() {
    stopWatching();
    _controller.close();
  }
}
