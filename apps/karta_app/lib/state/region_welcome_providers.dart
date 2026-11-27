import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';

import '../data/sea_state_regions.dart';

@immutable
class RegionWelcomeState {
  const RegionWelcomeState({
    this.isNavigationActive = false,
    this.currentRegion,
    this.activeBannerRegion,
    this.bannerSequence = 0,
  });

  final bool isNavigationActive;
  final KartaStateRegion? currentRegion;
  final KartaStateRegion? activeBannerRegion;
  final int bannerSequence;

  bool get isVisible => isNavigationActive && activeBannerRegion != null;

  RegionWelcomeState copyWith({
    bool? isNavigationActive,
    KartaStateRegion? currentRegion,
    bool clearCurrentRegion = false,
    KartaStateRegion? activeBannerRegion,
    bool clearBanner = false,
    int? bannerSequence,
  }) =>
      RegionWelcomeState(
        isNavigationActive: isNavigationActive ?? this.isNavigationActive,
        currentRegion: clearCurrentRegion
            ? null
            : (currentRegion ?? this.currentRegion),
        activeBannerRegion:
            clearBanner ? null : (activeBannerRegion ?? this.activeBannerRegion),
        bannerSequence: bannerSequence ?? this.bannerSequence,
      );
}

/// Tracks the driver's state, federal territory, province, or district ONLY
/// during active turn-by-turn navigation between Origin and Destination.
///
/// Seeds the starting state silently when navigation starts, and triggers a
/// welcome & greetings notification with the official state/district flag ONLY
/// when the vehicle actually crosses a border into a different state/district.
class RegionWelcomeNotifier extends StateNotifier<RegionWelcomeState> {
  RegionWelcomeNotifier() : super(const RegionWelcomeState());

  Timer? _autoDismissTimer;

  /// Called when active turn-by-turn navigation starts. Silently records the
  /// starting state/district without popping a greeting for the origin state.
  void beginNavigationSession(Coordinate originCoordinate) {
    _autoDismissTimer?.cancel();
    final initialRegion = SeaStateRegionResolver.resolve(originCoordinate);
    state = RegionWelcomeState(
      isNavigationActive: true,
      currentRegion: initialRegion,
      activeBannerRegion: null,
      bannerSequence: state.bannerSequence,
    );
  }

  /// Called on every vehicle position update during active navigation.
  /// Displays the border-crossing welcome banner with the authentic official
  /// flag ONLY when crossing from one state/district/province into another.
  void onNavigationFix(
    Coordinate vehicleCoordinate, {
    Duration displayDuration = const Duration(seconds: 7),
  }) {
    if (!state.isNavigationActive) return;

    final resolved = SeaStateRegionResolver.resolve(vehicleCoordinate);
    if (resolved == null) return;

    final previous = state.currentRegion;
    if (previous == null) {
      // Seed starting state silently if origin didn't resolve yet
      state = state.copyWith(currentRegion: resolved);
      return;
    }

    if (previous.id == resolved.id) return;

    // Vehicle has genuinely crossed a state / district / province border!
    _autoDismissTimer?.cancel();
    state = state.copyWith(
      currentRegion: resolved,
      activeBannerRegion: resolved,
      bannerSequence: state.bannerSequence + 1,
    );

    _autoDismissTimer = Timer(displayDuration, () {
      if (mounted) {
        state = state.copyWith(clearBanner: true);
      }
    });
  }

  /// Clears active border-crossing tracking when turn-by-turn navigation ends.
  void endNavigationSession() {
    _autoDismissTimer?.cancel();
    if (!state.isNavigationActive && state.activeBannerRegion == null) return;
    state = RegionWelcomeState(
      isNavigationActive: false,
      currentRegion: null,
      activeBannerRegion: null,
      bannerSequence: state.bannerSequence,
    );
  }

  void dismissBanner() {
    _autoDismissTimer?.cancel();
    if (state.activeBannerRegion != null) {
      state = state.copyWith(clearBanner: true);
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }
}

final regionWelcomeProvider =
    StateNotifierProvider<RegionWelcomeNotifier, RegionWelcomeState>(
  (ref) => RegionWelcomeNotifier(),
);
