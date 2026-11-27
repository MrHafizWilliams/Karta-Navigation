import 'dart:async';
import 'dart:math' as math;
import 'package:karta_api_client/karta_api_client.dart';
import 'package:meta/meta.dart';
import '../connectivity/connectivity_resilience_controller.dart';
import '../geo/polyline6.dart';
import '../gps/position_source.dart';
import '../privacy/location_privacy_guard.dart';
import '../speed/speed_limit_monitor.dart';
import '../thermal/thermal_adaptation_controller.dart';
import '../voice/voice_pack_models.dart';

enum NavigationPhase {
  idle,
  previewing,
  navigating,
  arrived,
}

@immutable
class NavigationVoiceEvent {
  const NavigationVoiceEvent({
    required this.cueKey,
    required this.text,
    this.isUrgentSafety = false,
  });

  final String cueKey;
  final String text;
  final bool isUrgentSafety;
}

@immutable
class RoadLaneDisplayItem {
  const RoadLaneDisplayItem({
    required this.laneSpec,
    required this.isRecommended,
  });

  final String laneSpec;
  final bool isRecommended;
}

@immutable
class LaneGuidanceBannerState {
  const LaneGuidanceBannerState({
    this.roadLanes = const <RoadLaneDisplayItem>[],
    this.approachingTollGantry,
  });

  final List<RoadLaneDisplayItem> roadLanes;
  final ApproachingGantry? approachingTollGantry;

  bool get hasAnyGuidance => roadLanes.isNotEmpty || approachingTollGantry != null;
}

@immutable
class NavigationSnapshot {
  const NavigationSnapshot({
    required this.phase,
    this.activeRoute,
    this.currentFix,
    this.currentLegIndex = 0,
    this.currentManeuverIndex = 0,
    this.currentManeuver,
    this.nextManeuver,
    this.distanceToManeuverMeters = 0,
    this.remainingDistanceMeters = 0,
    this.remainingDurationSeconds = 0,
    this.liveTrafficDelaySeconds = 0,
    this.progressFraction = 0,
    this.roadContext,
    this.activeCountry = const CountryContext(
      isoA2: 'MY',
      name: 'Malaysia',
      currencyCode: 'MYR',
      currencySymbol: 'RM',
      timezoneIana: 'Asia/Kuala_Lumpur',
    ),
    this.speedTelemetry = const SpeedTelemetryState(
      currentSpeedKmh: 0,
      severity: SpeedAlertSeverity.normal,
    ),
    this.laneGuidance = const LaneGuidanceBannerState(),
    this.approachingHazards = const <HazardRecord>[],
    this.congestionSegments = const <CongestionSegment>[],
    this.activeRerouteProposal,
    this.isOffRoute = false,
    this.lastVoicePrompt,
  });

  final NavigationPhase phase;
  final CandidateRoute? activeRoute;
  final GpsFix? currentFix;
  final int currentLegIndex;
  final int currentManeuverIndex;
  final RouteManeuver? currentManeuver;
  final RouteManeuver? nextManeuver;
  final double distanceToManeuverMeters;
  final double remainingDistanceMeters;
  final double remainingDurationSeconds;
  final double liveTrafficDelaySeconds;
  final double progressFraction;
  final RoadContextResponse? roadContext;
  final CountryContext activeCountry;
  final SpeedTelemetryState speedTelemetry;
  final LaneGuidanceBannerState laneGuidance;
  final List<HazardRecord> approachingHazards;
  final List<CongestionSegment> congestionSegments;
  final RerouteProposal? activeRerouteProposal;
  final bool isOffRoute;
  final String? lastVoicePrompt;

  HazardRecord? get nearestHazard =>
      approachingHazards.isNotEmpty ? approachingHazards.first : null;

  DateTime get estimatedArrival =>
      DateTime.now().add(Duration(seconds: remainingDurationSeconds.round()));
}

/// Pure headless navigation controller: consumes a [PositionSource] and live
/// [KartaApiClient] road-context & Phase 3 real-time hazard/reroute streams,
/// emitting immutable [NavigationSnapshot]s consumable by Flutter UI, CarPlay,
/// and Android Auto without coupling.
class NavigationSessionController {
  NavigationSessionController({
    required KartaApiClient apiClient,
    this.offRouteThresholdMeters = 65.0,
    LocationPrivacyGuard? privacyGuard,
    ThermalAdaptationController? thermalController,
    ConnectivityResilienceController? connectivityController,
  })  : _apiClient = apiClient,
        _ownsPrivacyGuard = privacyGuard == null,
        _privacyGuard = privacyGuard ?? LocationPrivacyGuard(),
        _thermalController = thermalController,
        _connectivityController = connectivityController;

  final KartaApiClient _apiClient;
  final double offRouteThresholdMeters;
  final bool _ownsPrivacyGuard;
  final LocationPrivacyGuard _privacyGuard;
  final ThermalAdaptationController? _thermalController;
  final ConnectivityResilienceController? _connectivityController;

  final StreamController<NavigationSnapshot> _stateController =
      StreamController<NavigationSnapshot>.broadcast();
  final StreamController<String> _voiceController = StreamController<String>.broadcast();
  final StreamController<NavigationVoiceEvent> _voiceEventController =
      StreamController<NavigationVoiceEvent>.broadcast();
  final GpsPuckInterpolator puckInterpolator = GpsPuckInterpolator();

  StreamSubscription<GpsFix>? _posSub;
  RouteGeometryIndex? _geometry;
  CandidateRoute? _route;
  List<({int legIndex, int maneuverIndex, double startM, double endM, RouteManeuver maneuver})>
      _flatManeuvers = const [];

  NavigationSnapshot _snapshot = const NavigationSnapshot(phase: NavigationPhase.idle);
  RoadContextResponse? _lastRoadContext;
  Coordinate? _lastRoadQueryPoint;
  DateTime? _lastRoadQueryTime;
  int _lastHintIndex = 0;
  int _lastSpokenManeuverIdx = -1;
  bool _roadQueryInFlight = false;
  List<HazardRecord> _liveHazards = const <HazardRecord>[];
  List<CongestionSegment> _liveCongestionSegments = const <CongestionSegment>[];
  double _liveTrafficDelaySec = 0.0;
  RerouteProposal? _activeRerouteProposal;
  final Set<String> _spokenHazardIds = <String>{};

  Stream<NavigationSnapshot> get stream => _stateController.stream;
  Stream<String> get voiceCues => _voiceController.stream;
  Stream<NavigationVoiceEvent> get voiceEvents => _voiceEventController.stream;
  NavigationSnapshot get current => _snapshot;
  LocationPrivacyGuard get privacyGuard => _privacyGuard;
  ThermalAdaptationController? get thermalController => _thermalController;

  void startNavigation({
    required CandidateRoute route,
    required PositionSource positionSource,
    CountryContext? initialCountry,
  }) {
    stopNavigation(scrubPrivacyState: false, emitIdle: false);
    _route = route;
    _geometry = RouteGeometryIndex.fromRoute(route);
    _flatManeuvers = _indexManeuvers(route, _geometry!);
    _lastHintIndex = 0;
    _lastSpokenManeuverIdx = -1;
    _lastRoadContext = null;
    _lastRoadQueryPoint = null;
    _liveCongestionSegments = route.congestionSegments;
    _liveTrafficDelaySec = route.liveTrafficDelaySeconds;
    _liveHazards = route.activeHazardsOnRoute;
    _activeRerouteProposal = null;
    _spokenHazardIds.clear();
    puckInterpolator.reset();

    final firstM = _flatManeuvers.isNotEmpty ? _flatManeuvers.first.maneuver : null;
    final secondM = _flatManeuvers.length > 1 ? _flatManeuvers[1].maneuver : null;

    _emit(
      NavigationSnapshot(
        phase: NavigationPhase.navigating,
        activeRoute: route,
        currentManeuver: firstM,
        nextManeuver: secondM,
        distanceToManeuverMeters: firstM != null ? firstM.distanceKm * 1000.0 : 0,
        remainingDistanceMeters: route.distanceKm * 1000.0,
        remainingDurationSeconds: route.durationSeconds,
        liveTrafficDelaySeconds: _liveTrafficDelaySec,
        activeCountry: initialCountry ?? _snapshot.activeCountry,
        approachingHazards: _liveHazards,
        congestionSegments: _liveCongestionSegments,
      ),
    );

    _posSub = positionSource.stream.listen(_onFix);
  }

  /// Seamlessly swaps the active Valhalla route mid-navigation after accepting a
  /// live dynamic traffic reroute proposal without interrupting the session.
  void applyLiveReroute(CandidateRoute newRoute, {PositionSource? replacementPositionSource}) {
    if (_snapshot.phase != NavigationPhase.navigating) return;
    _route = newRoute;
    _geometry = RouteGeometryIndex.fromRoute(newRoute);
    _flatManeuvers = _indexManeuvers(newRoute, _geometry!);
    _lastHintIndex = 0;
    _lastSpokenManeuverIdx = -1;
    _liveCongestionSegments = newRoute.congestionSegments;
    _liveTrafficDelaySec = newRoute.liveTrafficDelaySeconds;
    _activeRerouteProposal = null;

    if (replacementPositionSource != null) {
      _posSub?.cancel();
      _posSub = replacementPositionSource.stream.listen(_onFix);
    }

    _emitVoice(
      const NavigationVoiceEvent(
        cueKey: 'rerouting',
        text: 'Rerouting onto faster corridor around traffic ahead.',
        isUrgentSafety: true,
      ),
    );

    final firstM = _flatManeuvers.isNotEmpty ? _flatManeuvers.first.maneuver : null;
    final secondM = _flatManeuvers.length > 1 ? _flatManeuvers[1].maneuver : null;
    _emit(
      NavigationSnapshot(
        phase: NavigationPhase.navigating,
        activeRoute: newRoute,
        currentFix: _snapshot.currentFix,
        currentManeuver: firstM,
        nextManeuver: secondM,
        distanceToManeuverMeters: firstM != null ? firstM.distanceKm * 1000.0 : 0,
        remainingDistanceMeters: newRoute.distanceKm * 1000.0,
        remainingDurationSeconds: newRoute.durationSeconds,
        liveTrafficDelaySeconds: _liveTrafficDelaySec,
        progressFraction: 0.0,
        roadContext: _snapshot.roadContext,
        activeCountry: _snapshot.activeCountry,
        speedTelemetry: _snapshot.speedTelemetry,
        laneGuidance: _snapshot.laneGuidance,
        approachingHazards: _liveHazards,
        congestionSegments: _liveCongestionSegments,
        activeRerouteProposal: null,
        lastVoicePrompt: 'Rerouting onto faster corridor.',
      ),
    );
  }

  void updateLiveHazards(List<HazardRecord> hazards) {
    _liveHazards = hazards;
    if (_snapshot.phase == NavigationPhase.navigating) {
      for (final h in hazards) {
        if ((h.distanceMeters ?? 9999) <= 1200 && !_spokenHazardIds.contains(h.id)) {
          _spokenHazardIds.add(h.id);
          final distLabel = h.distanceMeters != null ? ' in ${h.distanceMeters!.round()} meters' : ' ahead';
          _emitVoice(
            NavigationVoiceEvent(
              cueKey: KartaVoicePackCatalog.cueKeyForHazard(h.category),
              text: '${h.category.label} reported$distLabel${h.roadRef != null ? ' on ${h.roadRef}' : ''}.',
              isUrgentSafety: true,
            ),
          );
          break;
        }
      }
      _reemitCurrentWithOverlay();
    }
  }

  void updateLiveTrafficOverlay({
    required double trafficDelaySeconds,
    required List<CongestionSegment> congestionSegments,
  }) {
    _liveTrafficDelaySec = trafficDelaySeconds;
    _liveCongestionSegments = congestionSegments;
    if (_snapshot.phase == NavigationPhase.navigating) {
      _reemitCurrentWithOverlay();
    }
  }

  void setRerouteProposal(RerouteProposal? proposal) {
    _activeRerouteProposal = proposal;
    if (proposal != null && _snapshot.phase == NavigationPhase.navigating) {
      final savedMin = (proposal.timeSavedSeconds / 60.0).round().clamp(1, 180);
      _emitVoice(
        NavigationVoiceEvent(
          cueKey: 'rerouting',
          text: '${proposal.reason}. Faster route saves $savedMin minutes. Say accept reroute to switch.',
          isUrgentSafety: true,
        ),
      );
    }
    if (_snapshot.phase == NavigationPhase.navigating) {
      _reemitCurrentWithOverlay();
    }
  }

  void _reemitCurrentWithOverlay() {
    final s = _snapshot;
    final route = _route;
    final baseRemaining = route != null
        ? route.durationSeconds * (1.0 - s.progressFraction)
        : s.remainingDurationSeconds;
    final extraDelay = math.max(0.0, _liveTrafficDelaySec - (route?.liveTrafficDelaySeconds ?? 0.0));
    _emit(
      NavigationSnapshot(
        phase: s.phase,
        activeRoute: s.activeRoute,
        currentFix: s.currentFix,
        currentLegIndex: s.currentLegIndex,
        currentManeuverIndex: s.currentManeuverIndex,
        currentManeuver: s.currentManeuver,
        nextManeuver: s.nextManeuver,
        distanceToManeuverMeters: s.distanceToManeuverMeters,
        remainingDistanceMeters: s.remainingDistanceMeters,
        remainingDurationSeconds: baseRemaining + extraDelay,
        liveTrafficDelaySeconds: _liveTrafficDelaySec,
        progressFraction: s.progressFraction,
        roadContext: s.roadContext,
        activeCountry: s.activeCountry,
        speedTelemetry: s.speedTelemetry,
        laneGuidance: s.laneGuidance,
        approachingHazards: _liveHazards,
        congestionSegments: _liveCongestionSegments,
        activeRerouteProposal: _activeRerouteProposal,
        isOffRoute: s.isOffRoute,
        lastVoicePrompt: s.lastVoicePrompt,
      ),
    );
  }

  void stopNavigation({bool scrubPrivacyState = true, bool emitIdle = true}) {
    _posSub?.cancel();
    _posSub = null;
    _route = null;
    _geometry = null;
    _flatManeuvers = const [];
    _lastRoadContext = null;
    _lastRoadQueryPoint = null;
    _lastRoadQueryTime = null;
    _liveHazards = const <HazardRecord>[];
    _liveCongestionSegments = const <CongestionSegment>[];
    _liveTrafficDelaySec = 0.0;
    _activeRerouteProposal = null;
    _spokenHazardIds.clear();
    puckInterpolator.reset();
    if (scrubPrivacyState && _privacyGuard.policy.scrubOnSessionEnd) {
      _privacyGuard.scrubEphemeralState();
    }
    if (emitIdle) {
      _emit(const NavigationSnapshot(phase: NavigationPhase.idle));
    }
  }

  /// Explicitly scrubs ephemeral in-memory GPS state (e.g., on head-unit disconnect
  /// when no active phone trip remains, or on privacy purge request).
  void scrubEphemeralState({bool purgeOptInHistory = false}) {
    _lastRoadQueryPoint = null;
    puckInterpolator.reset();
    _privacyGuard.scrubEphemeralState(purgeOptInHistory: purgeOptInHistory);
  }

  void _emitVoice(NavigationVoiceEvent evt) {
    if (!_voiceController.isClosed) _voiceController.add(evt.text);
    if (!_voiceEventController.isClosed) _voiceEventController.add(evt);
  }

  void _onFix(GpsFix rawFix) {
    final route = _route;
    final geom = _geometry;
    if (route == null || geom == null) return;

    final fix = _privacyGuard.processLiveFix(rawFix);
    puckInterpolator.pushFix(fix);
    final snap = geom.snapToRoute(fix.coordinate, hintIndex: _lastHintIndex);
    _lastHintIndex = snap.nearestIndex;

    final distAlong = snap.routeDistanceMeters;
    final totalM = math.max(1.0, geom.totalMeters);
    final remainingM = math.max(0.0, totalM - distAlong);
    final progress = (distAlong / totalM).clamp(0.0, 1.0);
    final remainingSec = route.durationSeconds * (1.0 - progress);
    final isOffRoute = !fix.isSimulated && snap.crossTrackMeters > offRouteThresholdMeters;

    // Locate active maneuver
    var activeFlatIdx = 0;
    for (var i = 0; i < _flatManeuvers.length; i++) {
      if (distAlong >= _flatManeuvers[i].startM) {
        activeFlatIdx = i;
      } else {
        break;
      }
    }

    final currentEntry = _flatManeuvers.isNotEmpty ? _flatManeuvers[activeFlatIdx] : null;
    final upcomingIdx = math.min(_flatManeuvers.length - 1, activeFlatIdx + 1);
    final upcomingEntry =
        _flatManeuvers.length > 1 ? _flatManeuvers[upcomingIdx] : currentEntry;
    final afterNextEntry = (upcomingIdx + 1 < _flatManeuvers.length)
        ? _flatManeuvers[upcomingIdx + 1]
        : null;

    final distToManeuver = upcomingEntry != null
        ? math.max(0.0, upcomingEntry.startM - distAlong)
        : 0.0;

    // Emit verbal pre-transition instruction once per approaching maneuver
    String? voicePrompt = _snapshot.lastVoicePrompt;
    if (upcomingEntry != null &&
        upcomingIdx != _lastSpokenManeuverIdx &&
        distToManeuver <= 650) {
      _lastSpokenManeuverIdx = upcomingIdx;
      voicePrompt = upcomingEntry.maneuver.verbalPreTransitionInstruction ??
          upcomingEntry.maneuver.instruction;
      _emitVoice(
        NavigationVoiceEvent(
          cueKey: KartaVoicePackCatalog.cueKeyForValhallaManeuver(upcomingEntry.maneuver.type),
          text: voicePrompt,
        ),
      );
    }

    // Trigger throttled real PostGIS/Redis road-context query
    _maybeRefreshRoadContext(fix);

    final ctx = _lastRoadContext;
    final activeCountry = ctx?.country ?? _inferFallbackCountry(fix.coordinate, _snapshot.activeCountry);
    final speedState = SpeedLimitMonitor.evaluate(
      currentSpeedKmh: fix.speedKmh,
      roadSpeedLimitKmh: ctx?.speedLimitKmh,
      speedLimitSource: ctx?.speedLimitSource,
      approachingZones: ctx?.approachingSpeedZones ?? const <ApproachingSpeedZone>[],
    );

    final laneGuidance = _buildLaneGuidance(ctx, upcomingEntry?.maneuver);
    final arrived = remainingM < 45.0 && progress > 0.985;
    final extraDelay = math.max(0.0, _liveTrafficDelaySec - route.liveTrafficDelaySeconds);

    _emit(
      NavigationSnapshot(
        phase: arrived ? NavigationPhase.arrived : NavigationPhase.navigating,
        activeRoute: route,
        currentFix: fix,
        currentLegIndex: currentEntry?.legIndex ?? 0,
        currentManeuverIndex: upcomingEntry?.maneuverIndex ?? 0,
        currentManeuver: upcomingEntry?.maneuver ?? currentEntry?.maneuver,
        nextManeuver: afterNextEntry?.maneuver,
        distanceToManeuverMeters: distToManeuver,
        remainingDistanceMeters: remainingM,
        remainingDurationSeconds: remainingSec + extraDelay,
        liveTrafficDelaySeconds: _liveTrafficDelaySec,
        progressFraction: progress,
        roadContext: ctx,
        activeCountry: activeCountry,
        speedTelemetry: speedState,
        laneGuidance: laneGuidance,
        approachingHazards: _liveHazards,
        congestionSegments: _liveCongestionSegments,
        activeRerouteProposal: _activeRerouteProposal,
        isOffRoute: isOffRoute,
        lastVoicePrompt: voicePrompt,
      ),
    );
  }

  void _maybeRefreshRoadContext(GpsFix fix) {
    if (_roadQueryInFlight) return;
    if (_apiClient.isUsingPublicFallback) {
      // Live routing is operating smoothly via public FOSSGIS Valhalla without a
      // local PostGIS server — skip local `/v1/spatial/road-context` polling so
      // connectivity stays Online without spurious offline-banner flapping.
      return;
    }
    if (_connectivityController?.current.isOffline == true) {
      // Tunnel / rural dead zone: rely smoothly on local route geometry & country inference
      // while ConnectivityResilienceController quietly probes recovery in the background.
      return;
    }
    final now = DateTime.now();
    final minInterval =
        _thermalController?.currentProfile.roadContextPollInterval ?? const Duration(seconds: 2);
    final timeOk = _lastRoadQueryTime == null ||
        now.difference(_lastRoadQueryTime!) >= minInterval;
    final distOk = _lastRoadQueryPoint == null ||
        haversineMeters(_lastRoadQueryPoint!, fix.coordinate) >= 120.0;

    if (!timeOk && !distOk) return;
    _roadQueryInFlight = true;
    _lastRoadQueryTime = now;
    _lastRoadQueryPoint = fix.coordinate;

    _apiClient
        .getRoadContext(
          lat: fix.coordinate.lat,
          lon: fix.coordinate.lon,
          heading: fix.bearingDeg,
          lookaheadMeters: 1800.0,
        )
        .then((ctx) {
          _lastRoadContext = ctx;
          _connectivityController?.recordNetworkSuccess();
        })
        .catchError((_) {
          _connectivityController?.recordNetworkFailure();
        })
        .whenComplete(() {
          _roadQueryInFlight = false;
        });
  }

  LaneGuidanceBannerState _buildLaneGuidance(
    RoadContextResponse? ctx,
    RouteManeuver? upcoming,
  ) {
    final approachingGantry =
        (ctx != null && ctx.approachingGantries.isNotEmpty) ? ctx.approachingGantries.first : null;

    final rawLanes = ctx?.turnLanes ?? const <String>[];
    final lanes = <RoadLaneDisplayItem>[];

    if (rawLanes.isNotEmpty) {
      final wantLeft = upcoming != null && const {14, 15, 16, 19, 21, 24, 26}.contains(upcoming.type);
      final wantRight = upcoming != null && const {9, 10, 11, 18, 20, 23, 25}.contains(upcoming.type);
      for (final spec in rawLanes) {
        final low = spec.toLowerCase();
        final recommended = wantLeft
            ? low.contains('left')
            : (wantRight ? low.contains('right') : (low.contains('through') || low == 'none' || low.isEmpty));
        lanes.add(RoadLaneDisplayItem(laneSpec: spec.isEmpty ? 'through' : spec, isRecommended: recommended));
      }
    } else if (upcoming != null && (ctx?.lanesTotal ?? 0) >= 2) {
      // Synthesize lane guidance from OSM lane count + upcoming Valhalla turn direction
      final count = (ctx!.lanesTotal!).clamp(2, 5);
      final wantLeft = const {14, 15, 16, 19, 21, 24, 26}.contains(upcoming.type);
      final wantRight = const {9, 10, 11, 18, 20, 23, 25}.contains(upcoming.type);
      for (var i = 0; i < count; i++) {
        if (i == 0 && wantLeft) {
          lanes.add(const RoadLaneDisplayItem(laneSpec: 'slight_left', isRecommended: true));
        } else if (i == count - 1 && wantRight) {
          lanes.add(const RoadLaneDisplayItem(laneSpec: 'slight_right', isRecommended: true));
        } else {
          lanes.add(RoadLaneDisplayItem(
            laneSpec: 'through',
            isRecommended: !wantLeft && !wantRight,
          ));
        }
      }
    }

    return LaneGuidanceBannerState(
      roadLanes: lanes,
      approachingTollGantry: approachingGantry,
    );
  }

  /// Lightweight geographic fallback used only between PostGIS `/v1/spatial/road-context` ticks.
  CountryContext _inferFallbackCountry(Coordinate c, CountryContext previous) {
    if (c.lat >= 1.15 && c.lat <= 1.47 && c.lon >= 103.59 && c.lon <= 104.09) {
      return const CountryContext(
        isoA2: 'SG',
        name: 'Singapore',
        currencyCode: 'SGD',
        currencySymbol: '\$',
        timezoneIana: 'Asia/Singapore',
      );
    }
    if (c.lat >= 4.00 && c.lat <= 5.06 && c.lon >= 114.07 && c.lon <= 115.36) {
      return const CountryContext(
        isoA2: 'BN',
        name: 'Brunei Darussalam',
        currencyCode: 'BND',
        currencySymbol: 'B\$',
        timezoneIana: 'Asia/Brunei',
      );
    }
    if (c.lat >= 0.85 && c.lat <= 7.45 && c.lon >= 99.55 && c.lon <= 119.40) {
      return const CountryContext(
        isoA2: 'MY',
        name: 'Malaysia',
        currencyCode: 'MYR',
        currencySymbol: 'RM',
        timezoneIana: 'Asia/Kuala_Lumpur',
      );
    }
    return previous;
  }

  List<({int legIndex, int maneuverIndex, double startM, double endM, RouteManeuver maneuver})>
      _indexManeuvers(CandidateRoute route, RouteGeometryIndex geom) {
    final out =
        <({int legIndex, int maneuverIndex, double startM, double endM, RouteManeuver maneuver})>[];
    for (var l = 0; l < route.legs.length; l++) {
      final leg = route.legs[l];
      for (var m = 0; m < leg.maneuvers.length; m++) {
        final man = leg.maneuvers[m];
        final startM = geom.distanceAtLegShapeIndex(l, man.beginShapeIndex);
        final endM = geom.distanceAtLegShapeIndex(l, man.endShapeIndex);
        out.add((legIndex: l, maneuverIndex: m, startM: startM, endM: endM, maneuver: man));
      }
    }
    return out;
  }

  void _emit(NavigationSnapshot next) {
    _snapshot = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void dispose() {
    _posSub?.cancel();
    if (_ownsPrivacyGuard) {
      _privacyGuard.dispose();
    } else if (_privacyGuard.policy.scrubOnSessionEnd) {
      _privacyGuard.scrubEphemeralState();
    }
    _stateController.close();
    _voiceController.close();
    _voiceEventController.close();
  }
}
