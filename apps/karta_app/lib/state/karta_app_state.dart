import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_map_engine/karta_map_engine.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import 'package:karta_offline_routing/karta_offline_routing.dart';

import '../services/live_location_platform.dart';
import '../services/live_location_stub.dart'
    if (dart.library.js_interop) '../services/live_location_web.dart' as live_loc_factory;
import 'lighting_providers.dart';
import 'phase3_providers.dart';
import 'phase4_automotive_providers.dart';

/// Named location used as Start (Origin) or End (Destination) in Karta's
/// single-destination navigation planner.
@immutable
class NamedWaypoint {
  const NamedWaypoint({
    required this.id,
    required this.label,
    required this.coordinate,
    this.subtitle,
    this.countryCode,
    this.isCurrentLocation = false,
  });

  final String id;
  final String label;
  final Coordinate coordinate;
  final String? subtitle;
  final String? countryCode;
  final bool isCurrentLocation;
}

/// Inspected place created when tapping any POI icon pin or any unknown/unnamed
/// spot directly on the map (Google Maps-style dropped pin inspection).
@immutable
class InspectedMapSpot {
  const InspectedMapSpot({
    required this.coordinate,
    required this.title,
    this.subtitle,
    this.category,
    this.countryCode,
    this.roadRef,
    this.poi,
  });

  final Coordinate coordinate;
  final String title;
  final String? subtitle;
  final String? category;
  final String? countryCode;
  final String? roadRef;
  final PoiItem? poi;
}

/// Canonical regional anchors for quick selection & verification
/// (never used to mock routing — always passed to live `POST /v1/routes`).
abstract final class KartaRegionalAnchors {
  static const NamedWaypoint penangKomtar = NamedWaypoint(
    id: 'anchor-penang',
    label: 'George Town (Komtar), Penang',
    subtitle: 'Penang Island · Malaysia',
    countryCode: 'MY',
    coordinate: Coordinate(lat: 5.4145, lon: 100.3298),
  );

  static const NamedWaypoint klcc = NamedWaypoint(
    id: 'anchor-klcc',
    label: 'Petronas Twin Towers (KLCC), Kuala Lumpur',
    subtitle: 'Kuala Lumpur City Centre · 3D Skyline Hub',
    countryCode: 'MY',
    coordinate: Coordinate(lat: 3.1579, lon: 101.7116),
  );

  static const NamedWaypoint marinaBay = NamedWaypoint(
    id: 'anchor-sg-mbs',
    label: 'Marina Bay Sands, Singapore',
    subtitle: 'Marina Bay Financial District · Singapore CBD',
    countryCode: 'SG',
    coordinate: Coordinate(lat: 1.2834, lon: 103.8607),
  );

  static const NamedWaypoint bandarSeriBegawan = NamedWaypoint(
    id: 'anchor-bn-bsb',
    label: 'Omar Ali Saifuddien Mosque, Bandar Seri Begawan',
    subtitle: 'Brunei-Muara · Brunei Darussalam',
    countryCode: 'BN',
    coordinate: Coordinate(lat: 4.8895, lon: 114.9392),
  );
}

/// Strictly single-destination route planning state (Origin -> Destination only).
@immutable
class RoutePlannerState {
  const RoutePlannerState({
    required this.origin,
    required this.destination,
    this.profile = RoutingProfileId.driveFastest,
    this.vehicleProfile = VehicleProfile.car,
    this.avoidHighways = false,
    this.isComputing = false,
    this.routeResponse,
    this.selectedRouteIndex = 0,
    this.errorMessage,
    this.departureTime,
  });

  final NamedWaypoint origin;
  final NamedWaypoint destination;
  final RoutingProfileId profile;
  final VehicleProfile vehicleProfile;
  final bool avoidHighways;
  final bool isComputing;
  final RouteResponse? routeResponse;
  final int selectedRouteIndex;
  final String? errorMessage;
  final DateTime? departureTime;

  /// Always strictly 2 endpoints: `[origin, destination]`.
  List<NamedWaypoint> get stops => <NamedWaypoint>[origin, destination];

  CandidateRoute? get selectedRoute {
    final routes = routeResponse?.routes;
    if (routes == null || routes.isEmpty) return null;
    return routes[selectedRouteIndex.clamp(0, routes.length - 1)];
  }

  RoutePlannerState copyWith({
    NamedWaypoint? origin,
    NamedWaypoint? destination,
    RoutingProfileId? profile,
    VehicleProfile? vehicleProfile,
    bool? avoidHighways,
    bool? isComputing,
    RouteResponse? routeResponse,
    bool clearRouteResponse = false,
    int? selectedRouteIndex,
    String? errorMessage,
    DateTime? departureTime,
  }) =>
      RoutePlannerState(
        origin: origin ?? this.origin,
        destination: destination ?? this.destination,
        profile: profile ?? this.profile,
        vehicleProfile: vehicleProfile ?? this.vehicleProfile,
        avoidHighways: avoidHighways ?? this.avoidHighways,
        isComputing: isComputing ?? this.isComputing,
        routeResponse: clearRouteResponse ? null : (routeResponse ?? this.routeResponse),
        selectedRouteIndex: selectedRouteIndex ?? this.selectedRouteIndex,
        errorMessage: errorMessage,
        departureTime: departureTime ?? this.departureTime,
      );
}

/// Resolves runtime endpoints from `--dart-define` or browser URL query parameters.
String resolveKartaApiUrl() {
  const envUrl = String.fromEnvironment('KARTA_API_URL', defaultValue: 'http://localhost:8000');
  if (kIsWeb) {
    final q = Uri.base.queryParameters['api'];
    if (q != null && q.isNotEmpty) return q;
  }
  return envUrl;
}

String resolveKartaPmtilesUrl() {
  const envUrl = String.fromEnvironment(
    'KARTA_PMTILES_URL',
    defaultValue: 'http://localhost:8081/my-sg-bn-full.pmtiles',
  );
  if (kIsWeb) {
    final q = Uri.base.queryParameters['pmtiles'];
    if (q != null && q.isNotEmpty) return q;
  }
  return envUrl;
}

final kartaApiClientProvider = Provider<KartaApiClient>((ref) {
  final client = KartaApiClient(baseUrl: resolveKartaApiUrl());
  ref.onDispose(client.close);
  return client;
});

final kartaPmtilesUrlProvider = StateProvider<String>((ref) => resolveKartaPmtilesUrl());

final kartaMapControllerProvider = ChangeNotifierProvider<KartaMapController>((ref) {
  return KartaMapController();
});

final streetLookAroundServiceProvider = Provider<StreetLookAroundService>((ref) {
  const token = String.fromEnvironment('MAPILLARY_ACCESS_TOKEN', defaultValue: '');
  return StreetLookAroundService(mapillaryAccessToken: token.isEmpty ? null : token);
});

final offlineRegionManagerProvider = Provider<OfflineRegionManager>((ref) {
  final mgr = OfflineRegionManager(apiClient: ref.watch(kartaApiClientProvider));
  ref.onDispose(mgr.dispose);
  return mgr;
});

final localPoiFuzzyIndexProvider = Provider<LocalPoiFuzzyIndex>((ref) {
  return ref.watch(offlineRegionManagerProvider).poiIndex;
});

final offlineRegionsStreamProvider = StreamProvider<List<OfflineRegionDownloadState>>((ref) {
  final mgr = ref.watch(offlineRegionManagerProvider);
  mgr.refreshCatalog().catchError((_) => <OfflineRegionDownloadState>[]);
  return mgr.stream;
});

final offlineModeEnabledProvider = StateProvider<bool>((ref) => false);

final connectivityResilienceProvider = Provider<ConnectivityResilienceController>((ref) {
  final api = ref.watch(kartaApiClientProvider);
  final mapCtrl = ref.read(kartaMapControllerProvider);
  final ctrl = ConnectivityResilienceController(
    probeOnline: () => api.pingLiveHealth(),
  );
  final sub = ctrl.stream.listen((snap) {
    mapCtrl.setOfflinePrefetchMuted(snap.isOffline);
  });
  ref.onDispose(() {
    sub.cancel();
    ctrl.dispose();
  });
  return ctrl;
});

final connectivitySnapshotProvider = StreamProvider<ConnectivitySnapshot>((ref) {
  final ctrl = ref.watch(connectivityResilienceProvider);
  return ctrl.stream;
});

final backendHealthProvider = FutureProvider<KartaHealthStatus?>((ref) async {
  final conn = ref.read(connectivityResilienceProvider);
  try {
    final health = await ref.watch(kartaApiClientProvider).getHealth();
    conn.recordNetworkSuccess();
    return health;
  } catch (_) {
    conn.recordNetworkFailure();
    return null;
  }
});

final navigationSessionProvider = Provider<NavigationSessionController>((ref) {
  final session = NavigationSessionController(
    apiClient: ref.watch(kartaApiClientProvider),
    privacyGuard: ref.watch(locationPrivacyGuardProvider),
    thermalController: ref.watch(thermalAdaptationControllerProvider),
    connectivityController: ref.watch(connectivityResilienceProvider),
  );
  final mapCtrl = ref.read(kartaMapControllerProvider);

  final voiceSub = session.voiceEvents.listen((event) {
    final muted = ref.read(voiceMutedProvider);
    ref.read(navigationVoiceEngineProvider).speakNavigationEvent(event, muted: muted);
  });

  int? lastTurnBeginIdx;
  final snapSub = session.stream.listen((snap) {
    if (snap.phase == NavigationPhase.navigating && snap.currentFix != null) {
      mapCtrl.followNavigationFix(
        snap.currentFix!,
        distanceToManeuverMeters: snap.distanceToManeuverMeters,
      );
      final curIdx = snap.currentManeuver?.beginShapeIndex;
      if (curIdx != lastTurnBeginIdx && snap.activeRoute != null) {
        lastTurnBeginIdx = curIdx;
        mapCtrl.updateActiveTurnArrows(
          route: snap.activeRoute,
          currentManeuver: snap.currentManeuver,
          nextManeuver: snap.nextManeuver,
        );
      }
      ref.read(kartaLightingProvider.notifier).updateTelemetry(
            coordinate: snap.currentFix!.coordinate,
            isTunnel: snap.roadContext?.isTunnel ?? false,
          );
    } else if (snap.phase == NavigationPhase.idle) {
      lastTurnBeginIdx = null;
      mapCtrl.hideVehiclePuck();
    }
  });

  ref.onDispose(() {
    voiceSub.cancel();
    snapSub.cancel();
    session.dispose();
  });
  return session;
});

final navigationSnapshotProvider = StreamProvider<NavigationSnapshot>((ref) {
  final session = ref.watch(navigationSessionProvider);
  return session.stream;
});

final voiceMutedProvider = StateProvider<bool>((ref) => false);
final activeNavTabProvider = StateProvider<String>((ref) => 'navigate');
final selectedPoiProvider = StateProvider<PoiItem?>((ref) => null);
final inspectedMapSpotProvider = StateProvider<InspectedMapSpot?>((ref) => null);
final lookAroundTargetProvider = StateProvider<StreetLookAroundTarget?>((ref) => null);
final mobileNavSheetExpandedProvider = StateProvider<bool>((ref) => false);
final activePlaybackSourceProvider = StateProvider<RoutePlaybackPositionSource?>((ref) => null);
final activeLiveGpsSourceProvider = StateProvider<LiveGpsPositionSource?>((ref) => null);

// ============================================================================
// REAL-TIME GPS CURRENT LOCATION TRACKER
// ============================================================================
class LiveLocationNotifier extends StateNotifier<LiveLocationSnapshot> {
  LiveLocationNotifier(this._ref)
      : _service = live_loc_factory.createPlatformLiveLocationService(),
        super(const LiveLocationSnapshot());

  final Ref _ref;
  final PlatformLiveLocationService _service;
  StreamSubscription<GpsFix>? _watchSub;
  Coordinate? _lastGeocodedCoord;
  DateTime? _lastGeocodedAt;
  bool _hasCenteredInitially = false;
  bool _hasAutoPopulatedOrigin = false;

  /// Starts real-time GPS tracking and smoothly centers the map when the first
  /// live fix arrives.
  Future<void> startTracking({bool centerOnFirstFix = true}) async {
    if (state.status == LiveLocationStatus.requesting) return;
    state = state.copyWith(status: LiveLocationStatus.requesting, clearError: true);

    if (!_service.isSupported) {
      state = state.copyWith(
        status: LiveLocationStatus.unavailable,
        errorMessage: 'GPS sensor unavailable on this device.',
      );
      return;
    }

    // Immediate fix probe for fast first-lock
    final immediate = await _service.getCurrentPosition();
    if (!mounted) return;
    if (immediate != null) {
      _handleIncomingFix(immediate, shouldCenter: centerOnFirstFix && !_hasCenteredInitially);
    }

    // Start continuous real-time GPS watch stream
    await _watchSub?.cancel();
    _watchSub = _service
        .watchPosition(
          onError: (code, msg) {
            if (!mounted) return;
            if (code == 'denied') {
              state = state.copyWith(
                status: LiveLocationStatus.denied,
                errorMessage: 'Location permission denied — enable GPS to track your position.',
              );
            } else if (!state.hasLiveFix) {
              state = state.copyWith(
                status: LiveLocationStatus.unavailable,
                errorMessage: msg.isNotEmpty ? msg : 'Waiting for GPS signal...',
              );
            }
          },
        )
        .listen((fix) {
      if (!mounted) return;
      _handleIncomingFix(fix, shouldCenter: centerOnFirstFix && !_hasCenteredInitially);
    });
  }

  /// Requests an immediate high-accuracy fix, flies the map to the user's real
  /// location, and optionally sets Origin to "Your Location".
  Future<bool> locateAndCenter({bool setAsOrigin = false}) async {
    state = state.copyWith(status: LiveLocationStatus.requesting, clearError: true);
    final fix = await _service.getCurrentPosition() ?? state.fix;
    if (!mounted) return false;
    if (fix == null) {
      await startTracking(centerOnFirstFix: true);
      return false;
    }

    _handleIncomingFix(fix, shouldCenter: true, forceSetOrigin: setAsOrigin);
    if (_watchSub == null) {
      unawaited(startTracking(centerOnFirstFix: false));
    }
    return true;
  }

  void _handleIncomingFix(
    GpsFix fix, {
    required bool shouldCenter,
    bool forceSetOrigin = false,
  }) {
    final mapCtrl = _ref.read(kartaMapControllerProvider);
    final isNavigating =
        _ref.read(navigationSessionProvider).current.phase == NavigationPhase.navigating;

    state = state.copyWith(
      status: LiveLocationStatus.active,
      fix: fix,
      clearError: true,
    );

    // Update Google Maps-style blue dot + accuracy halo + heading cone
    mapCtrl.setUserLocation(
      coordinate: fix.coordinate,
      headingDeg: fix.bearingDeg,
      accuracyMeters: fix.accuracyMeters,
      visible: !isNavigating,
    );

    // Feed real-time GPS fixes into LiveGpsPositionSource if live navigation is running
    final liveNavSource = _ref.read(activeLiveGpsSourceProvider);
    if (liveNavSource != null) {
      liveNavSource.pushFix(fix);
    }

    // Update solar daylight/night telemetry from real GPS coordinates
    _ref.read(kartaLightingProvider.notifier).updateTelemetry(
          coordinate: fix.coordinate,
          isTunnel: false,
        );

    if (shouldCenter && !isNavigating) {
      _hasCenteredInitially = true;
      mapCtrl.easeTo(
        center: fix.coordinate,
        zoom: 15.6,
        pitch: mapCtrl.is3DEnabled ? 48.0 : 0.0,
        durationMs: 750,
      );
    }

    final plannerState = _ref.read(routePlannerProvider);
    if (forceSetOrigin ||
        !_hasAutoPopulatedOrigin ||
        plannerState.origin.isCurrentLocation) {
      _hasAutoPopulatedOrigin = true;
      _syncOriginWithCurrentFix(fix);
    }

    // Reverse-resolve nearest road & country via PostGIS /v1/spatial/road-context
    final now = DateTime.now();
    final shouldResolveRoad = _lastGeocodedCoord == null ||
        haversineMeters(_lastGeocodedCoord!, fix.coordinate) >= 75.0 ||
        (_lastGeocodedAt != null && now.difference(_lastGeocodedAt!).inSeconds >= 20);
    if (shouldResolveRoad) {
      _lastGeocodedCoord = fix.coordinate;
      _lastGeocodedAt = now;
      _resolveRoadContext(fix);
    }
  }

  void _syncOriginWithCurrentFix(GpsFix fix) {
    final subtitle = state.roadName != null && state.roadName!.isNotEmpty
        ? 'Live GPS · ${state.roadName}'
        : 'Live GPS · ${fix.coordinate.lat.toStringAsFixed(4)}, ${fix.coordinate.lon.toStringAsFixed(4)}';
    _ref.read(routePlannerProvider.notifier).setOrigin(
          NamedWaypoint(
            id: 'live-gps-origin',
            label: 'Your Location',
            subtitle: subtitle,
            countryCode: state.countryCode ?? 'MY',
            coordinate: fix.coordinate,
            isCurrentLocation: true,
          ),
          recomputeIfActive: false,
        );
  }

  Future<void> _resolveRoadContext(GpsFix fix) async {
    try {
      final ctx = await _ref.read(kartaApiClientProvider).getRoadContext(
            lat: fix.coordinate.lat,
            lon: fix.coordinate.lon,
            heading: fix.bearingDeg,
          );
      if (!mounted) return;
      final roadLabel = <String>[
        if (ctx.roadName != null && ctx.roadName!.trim().isNotEmpty) ctx.roadName!.trim(),
        if (ctx.roadRef != null && ctx.roadRef!.trim().isNotEmpty) ctx.roadRef!.trim(),
      ].join(' · ');
      state = state.copyWith(
        roadName: roadLabel.isNotEmpty ? roadLabel : null,
        placeLabel: roadLabel.isNotEmpty
            ? roadLabel
            : (ctx.country?.name ?? 'Current Location'),
        countryCode: ctx.country?.isoA2,
      );
      if (_ref.read(routePlannerProvider).origin.isCurrentLocation) {
        _syncOriginWithCurrentFix(fix);
      }
    } catch (_) {
      // Keep live GPS dot active even when offline
    }
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}

final liveLocationProvider =
    StateNotifierProvider<LiveLocationNotifier, LiveLocationSnapshot>(
  (ref) => LiveLocationNotifier(ref),
);

// ============================================================================
// SINGLE-DESTINATION ROUTE PLANNER (START -> DESTINATION ONLY, ZERO TOLLS)
// ============================================================================
class RoutePlannerNotifier extends StateNotifier<RoutePlannerState> {
  RoutePlannerNotifier(this._ref)
      : super(
          const RoutePlannerState(
            origin: KartaRegionalAnchors.penangKomtar,
            destination: KartaRegionalAnchors.klcc,
          ),
        );

  final Ref _ref;

  void setOrigin(NamedWaypoint origin, {bool recomputeIfActive = true}) {
    state = state.copyWith(origin: origin, errorMessage: null);
    if (recomputeIfActive && state.routeResponse != null) {
      computeRoute();
    }
  }

  void setDestination(NamedWaypoint dest) {
    state = state.copyWith(destination: dest, errorMessage: null);
  }

  void setEndpoints({
    required NamedWaypoint origin,
    required NamedWaypoint destination,
  }) {
    state = state.copyWith(
      origin: origin,
      destination: destination,
      errorMessage: null,
    );
  }

  void reverseStops() {
    state = state.copyWith(
      origin: state.destination,
      destination: state.origin,
      errorMessage: null,
    );
    if (state.routeResponse != null) computeRoute();
  }

  void setProfile(RoutingProfileId profile) {
    final normalized = profile == RoutingProfileId.driveAvoidTolls
        ? RoutingProfileId.driveFastest
        : profile;
    final nextVehicle = normalized == RoutingProfileId.driveMotorcycle
        ? VehicleProfile.motorcycle
        : (state.vehicleProfile == VehicleProfile.motorcycle
            ? VehicleProfile.car
            : state.vehicleProfile);
    state = state.copyWith(
      profile: normalized,
      vehicleProfile: nextVehicle,
      avoidHighways: normalized == RoutingProfileId.driveNoHighways,
    );
    if (state.routeResponse != null) computeRoute();
  }

  void setVehicleProfile(VehicleProfile vp) {
    state = state.copyWith(vehicleProfile: vp);
    if (state.routeResponse != null) computeRoute();
  }

  void selectRouteIndex(int index) {
    final resp = state.routeResponse;
    if (resp == null || index < 0 || index >= resp.routes.length) return;
    state = state.copyWith(selectedRouteIndex: index);
    _pushRoutesToMap(resp, index, fit: false);
  }

  Future<void> computeRoute() async {
    state = state.copyWith(isComputing: true, errorMessage: null);
    final api = _ref.read(kartaApiClientProvider);

    try {
      // Strictly single-destination routing (origin -> destination, zero intermediate stops,
      // zero toll fee calculation or toll-free comparison).
      final req = RouteRequest(
        origin: state.origin.coordinate,
        destination: state.destination.coordinate,
        waypoints: const <Coordinate>[],
        profile: state.profile,
        vehicleProfile: state.vehicleProfile,
        avoidTolls: false,
        avoidHighways: state.avoidHighways,
        alternates: 2,
        includeTollFreeComparison: false,
        departureTime: state.departureTime,
      );

      final resp = await api.computeRoute(req);
      _ref.read(connectivityResilienceProvider).recordNetworkSuccess();
      state = state.copyWith(
        isComputing: false,
        routeResponse: resp,
        selectedRouteIndex: 0,
        errorMessage: null,
      );
      _pushRoutesToMap(resp, 0, fit: true);
    } catch (e) {
      final conn = _ref.read(connectivityResilienceProvider);
      conn.recordNetworkFailure();
      final hasCachedRoute = state.routeResponse != null;
      state = state.copyWith(
        isComputing: false,
        errorMessage: hasCachedRoute
            ? null
            : 'Signal unavailable — offline routing activates automatically with downloaded map packs.',
      );
    }
  }

  /// Starts active turn-by-turn navigation.
  /// When [simulate] is false and a real-time GPS fix is active, drives live
  /// from device GPS via [LiveGpsPositionSource]; otherwise falls back cleanly
  /// to real Valhalla geometry playback so indoor/desktop testing always works.
  void startActiveNavigation({bool simulate = false}) {
    final route = state.selectedRoute;
    if (route == null) return;

    _ref.read(activePlaybackSourceProvider)?.dispose();
    _ref.read(activePlaybackSourceProvider.notifier).state = null;
    _ref.read(activeLiveGpsSourceProvider)?.dispose();
    _ref.read(activeLiveGpsSourceProvider.notifier).state = null;

    final mapCtrl = _ref.read(kartaMapControllerProvider);
    final liveLoc = _ref.read(liveLocationProvider);
    final resp = state.routeResponse;
    if (resp != null) {
      // Ensure precise route polyline, stop markers, and active turn arrows are visible on map
      _pushRoutesToMap(resp, state.selectedRouteIndex, fit: false);
    }
    mapCtrl.setCameraLocked(true);

    final PositionSource source;
    RoutePlaybackPositionSource? playback;

    if (!simulate && liveLoc.hasLiveFix && liveLoc.fix != null) {
      final liveSource = LiveGpsPositionSource(initialFix: liveLoc.fix);
      _ref.read(activeLiveGpsSourceProvider.notifier).state = liveSource;
      source = liveSource;
      // Hide static blue dot because the 3D navigation puck now tracks real GPS
      mapCtrl.setUserLocation(
        coordinate: liveLoc.fix!.coordinate,
        headingDeg: liveLoc.fix!.bearingDeg,
        accuracyMeters: liveLoc.fix!.accuracyMeters,
        visible: false,
      );
    } else {
      final geom = RouteGeometryIndex.fromRoute(route);
      playback = RoutePlaybackPositionSource(
        geometry: geom,
        speedMultiplier: 16.0,
        baseCruiseKmh: 98.0,
      );
      _ref.read(activePlaybackSourceProvider.notifier).state = playback;
      source = playback;
    }

    final session = _ref.read(navigationSessionProvider);
    session.startNavigation(
      route: route,
      positionSource: source,
      initialCountry: state.routeResponse?.originCountry,
    );
    _ref.read(kartaAutomotiveBridgeProvider).updateActiveRoute(
          route: route,
          originName: state.origin.label,
          destinationName: state.destination.label,
          destinationCoordinate: state.destination.coordinate,
          alternates: state.routeResponse?.routes ?? const <CandidateRoute>[],
        );
    playback?.start();
  }

  void endActiveNavigation() {
    _ref.read(activePlaybackSourceProvider)?.dispose();
    _ref.read(activePlaybackSourceProvider.notifier).state = null;
    _ref.read(activeLiveGpsSourceProvider)?.dispose();
    _ref.read(activeLiveGpsSourceProvider.notifier).state = null;
    _ref.read(mobileNavSheetExpandedProvider.notifier).state = false;
    _ref.read(navigationSessionProvider).stopNavigation();
    _ref.read(kartaAutomotiveBridgeProvider).updateActiveRoute(
          route: null,
          originName: '',
          destinationName: '',
          destinationCoordinate: const Coordinate(lat: 0, lon: 0),
        );
    final mapCtrl = _ref.read(kartaMapControllerProvider);
    mapCtrl.setCameraLocked(false);

    // Restore live GPS blue dot when returning to explore mode
    final liveLoc = _ref.read(liveLocationProvider);
    if (liveLoc.hasLiveFix && liveLoc.fix != null) {
      mapCtrl.setUserLocation(
        coordinate: liveLoc.fix!.coordinate,
        headingDeg: liveLoc.fix!.bearingDeg,
        accuracyMeters: liveLoc.fix!.accuracyMeters,
        visible: true,
      );
    }

    final resp = state.routeResponse;
    if (resp != null) {
      _pushRoutesToMap(resp, state.selectedRouteIndex, fit: true);
    }
  }

  /// Seamlessly swaps in a live Valhalla reroute proposal mid-drive without ending the session.
  void applyLiveReroutedCandidate(CandidateRoute newRoute) {
    final prevResp = state.routeResponse;
    if (prevResp != null) {
      final updatedRoutes = <CandidateRoute>[
        newRoute,
        ...prevResp.routes.where((r) => r.routeIndex != state.selectedRouteIndex),
      ];
      final updatedResp = RouteResponse(
        originCountry: prevResp.originCountry,
        destinationCountry: prevResp.destinationCountry,
        departureTime: DateTime.now(),
        routes: updatedRoutes,
        tollFreeComparison: null,
        cached: false,
        trafficEpoch: prevResp.trafficEpoch + 1,
        exclusionsApplied: prevResp.exclusionsApplied + 1,
      );
      state = state.copyWith(routeResponse: updatedResp, selectedRouteIndex: 0);
      _pushRoutesToMap(updatedResp, 0, fit: false);
    }

    final existingPlayback = _ref.read(activePlaybackSourceProvider);
    RoutePlaybackPositionSource? nextPlayback;
    if (existingPlayback != null) {
      final speedMult = existingPlayback.speedMultiplier;
      existingPlayback.dispose();
      nextPlayback = RoutePlaybackPositionSource(
        geometry: RouteGeometryIndex.fromRoute(newRoute),
        speedMultiplier: speedMult,
        baseCruiseKmh: 96.0,
      );
      _ref.read(activePlaybackSourceProvider.notifier).state = nextPlayback;
      nextPlayback.start();
    }

    _ref
        .read(navigationSessionProvider)
        .applyLiveReroute(newRoute, replacementPositionSource: nextPlayback);
    _ref.read(kartaAutomotiveBridgeProvider).updateActiveRoute(
          route: newRoute,
          originName: state.origin.label,
          destinationName: state.destination.label,
          destinationCoordinate: state.destination.coordinate,
        );
  }

  void _pushRoutesToMap(RouteResponse resp, int selectedIdx, {required bool fit}) {
    final stopsPins = <KartaMapStopPin>[
      KartaMapStopPin(
        label: state.origin.label.split(',').first,
        role: 'origin',
        coordinate: state.origin.coordinate,
      ),
      KartaMapStopPin(
        label: state.destination.label.split(',').first,
        role: 'destination',
        coordinate: state.destination.coordinate,
      ),
    ];

    final mapCtrl = _ref.read(kartaMapControllerProvider);
    mapCtrl.setRoutes(
      routes: resp.routes,
      selectedIndex: selectedIdx,
      tollFreeIndex: null,
      stops: stopsPins,
      fitToRoutes: fit,
    );

    if (resp.routes.isNotEmpty) {
      final chosen = resp.routes[selectedIdx.clamp(0, resp.routes.length - 1)];
      final pts = RouteGeometryIndex.fromRoute(chosen).points;
      mapCtrl.setTrafficSegments(
        routePoints: pts,
        segments: chosen.congestionSegments,
      );
    }
  }
}

final routePlannerProvider = StateNotifierProvider<RoutePlannerNotifier, RoutePlannerState>(
  (ref) => RoutePlannerNotifier(ref),
);
