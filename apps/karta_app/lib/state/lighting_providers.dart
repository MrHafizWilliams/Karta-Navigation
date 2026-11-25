import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import 'karta_app_state.dart';

KartaLightingPreference _resolveInitialLightingPreference() {
  if (kIsWeb) {
    final q = Uri.base.queryParameters['theme']?.toLowerCase();
    if (q == 'day' || q == 'light') return KartaLightingPreference.day;
    if (q == 'night' || q == 'dark') return KartaLightingPreference.night;
    if (q == 'auto') return KartaLightingPreference.auto;
  }
  return KartaLightingPreference.auto;
}

/// Reactive Solar & Tunnel Lighting Controller tied to live MY/SG/BN GPS coordinates.
/// Automatically transitions between High-Glare Tropical Daylight Mode and Obsidian
/// Night Mode at sunrise/sunset and inside tunnels (e.g. SMART Tunnel KL, CTE/KPE
/// Singapore) with 4-second exit hysteresis, while supporting 1-tap manual overrides.
class KartaLightingNotifier extends StateNotifier<KartaLightingState> {
  KartaLightingNotifier(this._ref)
      : _preference = _resolveInitialLightingPreference(),
        super(
          SolarTunnelLightingEngine().resolve(
            preference: _resolveInitialLightingPreference(),
            coordinate: KartaRegionalAnchors.klcc.coordinate,
            nowUtc: DateTime.now().toUtc(),
            isInTunnel: false,
          ),
        ) {
    Future<void>.microtask(() {
      if (mounted) _syncMapLighting(state.resolvedMode);
    });
    _solarTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_preference == KartaLightingPreference.auto) {
        _recompute();
      }
    });
  }

  final Ref _ref;
  final SolarTunnelLightingEngine _engine = SolarTunnelLightingEngine();
  Timer? _solarTicker;
  Timer? _hysteresisTimer;

  Coordinate _lastCoord = KartaRegionalAnchors.klcc.coordinate;
  KartaLightingPreference _preference;
  bool _roadTunnelActive = false;
  bool _simulatedTunnelActive = false;
  bool? _vehicleHeadlightDark;

  bool get simulatedTunnelActive => _simulatedTunnelActive;
  bool? get vehicleHeadlightDark => _vehicleHeadlightDark;

  void setPreference(KartaLightingPreference pref) {
    _preference = pref;
    _recompute();
  }

  /// Cycles smoothly: Auto (Solar + Tunnel) -> Night -> Day -> Auto.
  void cyclePreference() {
    final next = switch (_preference) {
      KartaLightingPreference.auto =>
        state.isDaylight ? KartaLightingPreference.night : KartaLightingPreference.day,
      KartaLightingPreference.night => KartaLightingPreference.day,
      KartaLightingPreference.day => KartaLightingPreference.auto,
    };
    setPreference(next);
  }

  /// Feeds live GPS coordinate + PostGIS `roadContext.isTunnel` state into the engine.
  void updateTelemetry({
    required Coordinate coordinate,
    required bool isTunnel,
  }) {
    final coordChanged = (coordinate.lat - _lastCoord.lat).abs() > 0.01 ||
        (coordinate.lon - _lastCoord.lon).abs() > 0.01;
    final tunnelChanged = _roadTunnelActive != isTunnel;
    _lastCoord = coordinate;
    _roadTunnelActive = isTunnel;
    if (coordChanged || tunnelChanged) {
      _recompute();
    }
  }

  /// Toggleable tunnel test hook (e.g. simulating SMART Tunnel KL or Singapore KPE
  /// from midday Penang Bridge / KLCC daylight).
  void toggleSimulatedTunnel() {
    _simulatedTunnelActive = !_simulatedTunnelActive;
    if (_simulatedTunnelActive && _preference == KartaLightingPreference.day) {
      _preference = KartaLightingPreference.auto;
    }
    _recompute();
  }

  void setSimulatedTunnel(bool inTunnel) {
    if (_simulatedTunnelActive == inTunnel) return;
    _simulatedTunnelActive = inTunnel;
    _recompute();
  }

  /// Syncs Karta's theme with Apple CarPlay (`UIUserInterfaceStyle`) or Android Auto
  /// (`onCarConfigurationChanged` / `isDarkMode`) vehicle headlight/dimmer sensor state.
  /// Pass `null` on disconnect to return automatically to solar/tunnel lighting.
  void applyVehicleHeadlightOverride(bool? isDarkMode) {
    if (_vehicleHeadlightDark == isDarkMode) return;
    _vehicleHeadlightDark = isDarkMode;
    _recompute();
  }

  void _recompute() {
    final effectiveTunnel = _roadTunnelActive || _simulatedTunnelActive;
    final nowUtc = DateTime.now().toUtc();
    final next = _engine.resolve(
      preference: _preference,
      coordinate: _lastCoord,
      nowUtc: nowUtc,
      isInTunnel: effectiveTunnel,
      vehicleHeadlightDark: _vehicleHeadlightDark,
    );

    final modeChanged = next.resolvedMode != state.resolvedMode;
    state = next;
    if (modeChanged) {
      _syncMapLighting(next.resolvedMode);
    }

    // If holding Night during the 4s tunnel exit hysteresis window, schedule automatic release
    _hysteresisTimer?.cancel();
    if (!effectiveTunnel && next.tunnelHoldActive) {
      _hysteresisTimer = Timer(
        _engine.tunnelExitHysteresis + const Duration(milliseconds: 250),
        _recompute,
      );
    }
  }

  void _syncMapLighting(KartaVisualMode mode) {
    _ref.read(kartaMapControllerProvider).setLightingMode(mode);
  }

  @override
  void dispose() {
    _solarTicker?.cancel();
    _hysteresisTimer?.cancel();
    super.dispose();
  }
}

final kartaLightingProvider =
    StateNotifierProvider<KartaLightingNotifier, KartaLightingState>(
  (ref) => KartaLightingNotifier(ref),
);
