import 'package:flutter/foundation.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

enum LiveLocationStatus {
  idle,
  requesting,
  active,
  denied,
  unavailable,
}

@immutable
class LiveLocationSnapshot {
  const LiveLocationSnapshot({
    this.status = LiveLocationStatus.idle,
    this.fix,
    this.placeLabel,
    this.roadName,
    this.countryCode,
    this.errorMessage,
  });

  final LiveLocationStatus status;
  final GpsFix? fix;
  final String? placeLabel;
  final String? roadName;
  final String? countryCode;
  final String? errorMessage;

  bool get hasLiveFix => fix != null && status == LiveLocationStatus.active;

  Coordinate? get coordinate => fix?.coordinate;

  LiveLocationSnapshot copyWith({
    LiveLocationStatus? status,
    GpsFix? fix,
    String? placeLabel,
    String? roadName,
    String? countryCode,
    String? errorMessage,
    bool clearError = false,
  }) =>
      LiveLocationSnapshot(
        status: status ?? this.status,
        fix: fix ?? this.fix,
        placeLabel: placeLabel ?? this.placeLabel,
        roadName: roadName ?? this.roadName,
        countryCode: countryCode ?? this.countryCode,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// Decoupled platform contract for real-time device GPS / geolocation tracking.
abstract class PlatformLiveLocationService {
  bool get isSupported;

  /// Requests an immediate high-accuracy GPS fix.
  Future<GpsFix?> getCurrentPosition();

  /// Starts continuous real-time GPS tracking and returns a broadcast stream of fixes.
  Stream<GpsFix> watchPosition({
    void Function(String errorCode, String message)? onError,
  });

  void stopWatching();
  void dispose();
}
