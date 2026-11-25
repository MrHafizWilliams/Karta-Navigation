import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_map_engine/karta_map_engine.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import '../services/media_web_hook_stub.dart'
    if (dart.library.js_interop) '../services/media_web_hook_web.dart' as media_hook;
import '../services/navigation_voice_engine.dart';
import '../services/voice_input_platform.dart';
import '../services/voice_input_stub.dart'
    if (dart.library.js_interop) '../services/voice_input_web.dart' as speech_factory;
import 'karta_app_state.dart';
import 'phase4_automotive_providers.dart';

void playKartaAudioChime(Ref ref, String chimeType) {
  if (ref.read(voiceMutedProvider)) return;
  media_hook.playKartaChime(chimeType);
}

// ============================================================================
// 1. CUSTOM NAVIGATION VOICE PACK ENGINE
// ============================================================================
final navigationVoiceEngineProvider = ChangeNotifierProvider<NavigationVoiceEngine>((ref) {
  final engine = NavigationVoiceEngine(
    apiClient: ref.watch(kartaApiClientProvider),
  );
  engine.refreshCustomPacks();
  return engine;
});

// ============================================================================
// 2. REAL-TIME GEOSPATIAL PUB/SUB (WEBSOCKET + REDIS GEO + VALHALLA REROUTE)
// ============================================================================
final realtimeSessionIdProvider = Provider<String>(
  (ref) => ref.watch(locationPrivacyGuardProvider).ephemeralSessionToken,
);

final kartaRealtimeClientProvider = Provider<KartaRealtimeClient>((ref) {
  final client = KartaRealtimeClient(
    httpBaseUrl: resolveKartaApiUrl(),
    sessionId: ref.watch(realtimeSessionIdProvider),
  );
  ref.onDispose(() {
    client.dispose();
  });
  return client;
});

@immutable
class RealtimeCrowdsourcingState {
  const RealtimeCrowdsourcingState({
    this.connectionState = RealtimeConnectionState.disconnected,
    this.hazards = const <HazardRecord>[],
    this.dismissedHazardIds = const <String>{},
    this.focusedHazardId,
    this.activeRerouteProposal,
    this.lastToastMessage,
    this.activeFuelOverlayOpen = false,
    this.radialMenuOpen = false,
    this.trafficEpoch = 0,
    this.urgentTimeToLeaveBanner,
  });

  final RealtimeConnectionState connectionState;
  final List<HazardRecord> hazards;
  final Set<String> dismissedHazardIds;
  final String? focusedHazardId;
  final RerouteProposal? activeRerouteProposal;
  final String? lastToastMessage;
  final bool activeFuelOverlayOpen;
  final bool radialMenuOpen;
  final int trafficEpoch;
  final Map<String, dynamic>? urgentTimeToLeaveBanner;

  HazardRecord? get highlightedHazard {
    if (hazards.isEmpty) return null;
    if (focusedHazardId != null) {
      for (final h in hazards) {
        if (h.id == focusedHazardId && !dismissedHazardIds.contains(h.id)) {
          return h;
        }
      }
    }
    for (final h in hazards) {
      if (h.onActiveRoute && !dismissedHazardIds.contains(h.id)) return h;
    }
    for (final h in hazards) {
      if (!dismissedHazardIds.contains(h.id)) return h;
    }
    return null;
  }

  RealtimeCrowdsourcingState copyWith({
    RealtimeConnectionState? connectionState,
    List<HazardRecord>? hazards,
    Set<String>? dismissedHazardIds,
    String? focusedHazardId,
    bool clearFocusedHazard = false,
    RerouteProposal? activeRerouteProposal,
    bool clearRerouteProposal = false,
    String? lastToastMessage,
    bool clearToast = false,
    bool? activeFuelOverlayOpen,
    bool? radialMenuOpen,
    int? trafficEpoch,
    Map<String, dynamic>? urgentTimeToLeaveBanner,
    bool clearTtlBanner = false,
  }) =>
      RealtimeCrowdsourcingState(
        connectionState: connectionState ?? this.connectionState,
        hazards: hazards ?? this.hazards,
        dismissedHazardIds: dismissedHazardIds ?? this.dismissedHazardIds,
        focusedHazardId: clearFocusedHazard ? null : (focusedHazardId ?? this.focusedHazardId),
        activeRerouteProposal: clearRerouteProposal
            ? null
            : (activeRerouteProposal ?? this.activeRerouteProposal),
        lastToastMessage: clearToast ? null : (lastToastMessage ?? this.lastToastMessage),
        activeFuelOverlayOpen: activeFuelOverlayOpen ?? this.activeFuelOverlayOpen,
        radialMenuOpen: radialMenuOpen ?? this.radialMenuOpen,
        trafficEpoch: trafficEpoch ?? this.trafficEpoch,
        urgentTimeToLeaveBanner: clearTtlBanner
            ? null
            : (urgentTimeToLeaveBanner ?? this.urgentTimeToLeaveBanner),
      );
}

class RealtimeCrowdsourcingNotifier extends StateNotifier<RealtimeCrowdsourcingState> {
  RealtimeCrowdsourcingNotifier(this._ref) : super(const RealtimeCrowdsourcingState());

  final Ref _ref;
  StreamSubscription<RealtimeFrame>? _frameSub;
  StreamSubscription<RealtimeConnectionState>? _statusSub;
  StreamSubscription<NavigationSnapshot>? _navSub;
  StreamSubscription<int>? _fuelPinTapSub;
  StreamSubscription<String>? _hazardPinTapSub;
  ProviderSubscription<RoutePlannerState>? _routeSub;
  DateTime? _lastTelemetrySent;
  Timer? _toastClearTimer;
  String? _lastHydratedRouteSig;
  bool _initialized = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    final ws = _ref.read(kartaRealtimeClientProvider);
    final conn = _ref.read(connectivityResilienceProvider);
    _statusSub = ws.statusStream.listen((st) {
      if (mounted) state = state.copyWith(connectionState: st);
      if (st == RealtimeConnectionState.connected) {
        conn.recordNetworkSuccess();
      }
    });
    _frameSub = ws.frames.listen(_onFrame);

    conn.registerReconnectHook(() async {
      final center = _ref.read(kartaMapControllerProvider).center;
      await refreshNearbyHazards(coordinate: center);
    });

    final navSession = _ref.read(navigationSessionProvider);
    _navSub = navSession.stream.listen(_onNavigationSnapshot);

    final mapCtrl = _ref.read(kartaMapControllerProvider);
    _fuelPinTapSub = mapCtrl.onFuelPinTap.listen((poiId) {
      if (!mounted) return;
      _ref.read(fuelComparisonProvider.notifier).highlightStation(poiId);
      state = state.copyWith(activeFuelOverlayOpen: true);
    });
    _hazardPinTapSub = mapCtrl.onHazardPinTap.listen((hazardId) {
      if (!mounted) return;
      focusHazardFromMap(hazardId);
    });

    // Automatically hydrate inline route fuel price pins whenever the active route updates
    _routeSub = _ref.listen<RoutePlannerState>(routePlannerProvider, (prev, next) {
      final sel = next.selectedRoute;
      if (sel == null || sel.legs.isEmpty) {
        _lastHydratedRouteSig = null;
        return;
      }
      final sig = '${sel.routeIndex}:${sel.legs.first.shapePolyline6.length}:${next.routeResponse?.trafficEpoch ?? 0}';
      if (sig == _lastHydratedRouteSig) return;
      _lastHydratedRouteSig = sig;
      _ref.read(fuelComparisonProvider.notifier).hydrateAlongActiveRoute(
            preferredCountryCode: next.routeResponse?.originCountry?.isoA2,
          );
    });

    final center = mapCtrl.center;
    ws.connect(initialCoord: center, country: 'MY');

    // Also pull initial nearby hazards over REST for immediate map hydration
    refreshNearbyHazards(coordinate: center);
  }

  void _onFrame(RealtimeFrame frame) {
    if (!mounted) return;
    final mapCtrl = _ref.read(kartaMapControllerProvider);
    final navSession = _ref.read(navigationSessionProvider);

    switch (frame.eventType) {
      case 'session.ack':
        final initial = frame.initialHazards ?? const <HazardRecord>[];
        final epoch = (frame.raw['traffic_epoch'] as num?)?.toInt() ?? state.trafficEpoch;
        state = state.copyWith(hazards: initial, trafficEpoch: epoch);
        mapCtrl.setHazards(initial);
        navSession.updateLiveHazards(initial);
        _ref.read(kartaAutomotiveBridgeProvider).updateHazards(initial);
        break;

      case 'hazard.alert':
      case 'hazard.updated':
      case 'hazard.ack':
      case 'hazard.vote_ack':
        final h = frame.hazard;
        if (h == null) return;
        final updated = _upsertHazard(state.hazards, h);
        state = state.copyWith(hazards: updated);
        mapCtrl.setHazards(updated);
        navSession.updateLiveHazards(updated);
        _ref.read(kartaAutomotiveBridgeProvider).updateHazards(updated);
        break;

      case 'hazard.removed':
        final hid = frame.removedHazardId;
        if (hid == null) return;
        final next = state.hazards.where((h) => h.id != hid).toList();
        state = state.copyWith(hazards: next);
        mapCtrl.setHazards(next);
        navSession.updateLiveHazards(next);
        _ref.read(kartaAutomotiveBridgeProvider).updateHazards(next);
        break;

      case 'eta.update':
        final segs = frame.congestionSegments ?? const <CongestionSegment>[];
        final delay = frame.trafficDelaySeconds ?? 0.0;
        navSession.updateLiveTrafficOverlay(
          trafficDelaySeconds: delay,
          congestionSegments: segs,
        );
        final activeRoute = _ref.read(routePlannerProvider).selectedRoute;
        if (activeRoute != null) {
          final pts = RouteGeometryIndex.fromRoute(activeRoute).points;
          mapCtrl.setTrafficSegments(routePoints: pts, segments: segs);
        }
        break;

      case 'route.reroute_proposal':
        final proposal = frame.rerouteProposal;
        if (proposal != null) {
          state = state.copyWith(activeRerouteProposal: proposal);
          navSession.setRerouteProposal(proposal);
        }
        break;

      case 'commuter.time_to_leave':
        state = state.copyWith(urgentTimeToLeaveBanner: frame.raw);
        break;

      case 'fuel.price_updated':
        if (state.activeFuelOverlayOpen ||
            _ref.read(routePlannerProvider).selectedRoute != null) {
          _ref.read(fuelComparisonProvider.notifier).refreshForCurrentContext();
        }
        break;
    }
  }

  void _onNavigationSnapshot(NavigationSnapshot snap) {
    if (snap.phase != NavigationPhase.navigating || snap.currentFix == null) return;
    final now = DateTime.now();
    if (_lastTelemetrySent != null &&
        now.difference(_lastTelemetrySent!) < const Duration(seconds: 2)) {
      return;
    }
    _lastTelemetrySent = now;

    final planner = _ref.read(routePlannerProvider);
    final activeRoute = snap.activeRoute ?? planner.selectedRoute;
    final poly6 = activeRoute != null && activeRoute.legs.isNotEmpty
        ? activeRoute.legs.first.shapePolyline6
        : null;
    final dest = planner.stops.isNotEmpty ? planner.stops.last.coordinate : null;

    _ref.read(kartaRealtimeClientProvider).sendTelemetry(
          coordinate: snap.currentFix!.coordinate,
          headingDeg: snap.currentFix!.bearingDeg,
          speedKmh: snap.currentFix!.speedKmh,
          countryCode: snap.activeCountry.isoA2,
          routeId: 'active-route',
          routePolyline6: poly6,
          routeProfile: planner.profile.wireValue,
          vehicleProfile: planner.vehicleProfile.wireValue,
          vehicleRegistrationCountry: planner.origin.countryCode ?? 'MY',
          destination: dest,
        );
  }

  Future<void> refreshNearbyHazards({
    required Coordinate coordinate,
    double? headingDeg,
    double speedKmh = 0.0,
  }) async {
    try {
      final resp = await _ref.read(kartaApiClientProvider).getNearbyHazards(
            lat: coordinate.lat,
            lon: coordinate.lon,
            headingDeg: headingDeg,
            speedKmh: speedKmh,
            maxRadiusMeters: 12000,
          );
      if (!mounted) return;
      state = state.copyWith(hazards: resp.hazards);
      _ref.read(kartaMapControllerProvider).setHazards(resp.hazards);
      _ref.read(navigationSessionProvider).updateLiveHazards(resp.hazards);
    } catch (_) {}
  }

  Future<HazardRecord?> reportHazard({
    required HazardCategory category,
    String? subtype,
    HazardSeverity severity = HazardSeverity.medium,
    Coordinate? coordinate,
    double? headingDeg,
    bool oppositeSide = false,
    String? laneHint,
    String? description,
    String source = 'radial',
  }) async {
    final navSnap = _ref.read(navigationSessionProvider).current;
    final mapCtrl = _ref.read(kartaMapControllerProvider);
    final coord = coordinate ?? navSnap.currentFix?.coordinate ?? mapCtrl.center;
    final baseHeading = headingDeg ?? navSnap.currentFix?.bearingDeg ?? mapCtrl.bearing;
    final effectiveHeading = oppositeSide ? (baseHeading + 180.0) % 360.0 : baseHeading;

    final req = HazardReportRequest(
      category: category,
      subtype: subtype,
      severity: severity,
      coordinate: coord,
      headingDeg: effectiveHeading,
      affectsBothDirections: category == HazardCategory.roadClosure,
      laneHint: laneHint,
      description: description,
      source: source,
      reporterSessionId: _ref.read(realtimeSessionIdProvider),
    );

    final ws = _ref.read(kartaRealtimeClientProvider);
    if (ws.status == RealtimeConnectionState.connected) {
      ws.sendHazardReport(req);
    }

    try {
      final created = await _ref.read(kartaApiClientProvider).reportHazard(req);
      _ref.read(connectivityResilienceProvider).recordNetworkSuccess();
      if (!mounted) return created;
      final next = _upsertHazard(state.hazards, created);
      final nextDismissed = Set<String>.from(state.dismissedHazardIds)..remove(created.id);
      state = state.copyWith(
        hazards: next,
        dismissedHazardIds: nextDismissed,
        radialMenuOpen: false,
      );
      mapCtrl.setHazards(next);
      _ref.read(navigationSessionProvider).updateLiveHazards(next);
      playKartaAudioChime(_ref, 'reportConfirmed');
      _showToast('${category.label} reported — live map & Valhalla costing updated');
      return created;
    } catch (e) {
      // Seamless tunnel/dead-zone queuing: report stays visible locally and syncs quietly once signal returns
      final conn = _ref.read(connectivityResilienceProvider);
      conn.recordNetworkFailure();
      conn.enqueueOfflineSyncAction(() async {
        await _ref.read(kartaApiClientProvider).reportHazard(req);
      });
      final now = DateTime.now();
      final local = HazardRecord(
        id: 'local-haz-${now.millisecondsSinceEpoch}',
        category: category,
        subtype: subtype,
        severity: severity,
        coordinate: coord,
        roadHeadingDeg: effectiveHeading,
        laneHint: laneHint,
        description: description,
        source: source,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 45)),
      );
      if (mounted) {
        final next = _upsertHazard(state.hazards, local);
        state = state.copyWith(hazards: next, radialMenuOpen: false);
        mapCtrl.setHazards(next);
        playKartaAudioChime(_ref, 'reportConfirmed');
        _showToast('${category.label} queued — auto-syncing when signal returns');
      }
      return local;
    }
  }

  void dismissHazardCard(String hazardId) {
    final nextDismissed = Set<String>.from(state.dismissedHazardIds)..add(hazardId);
    state = state.copyWith(
      dismissedHazardIds: nextDismissed,
      clearFocusedHazard: state.focusedHazardId == hazardId,
    );
  }

  void focusHazardFromMap(String hazardId) {
    final nextDismissed = Set<String>.from(state.dismissedHazardIds)..remove(hazardId);
    state = state.copyWith(
      dismissedHazardIds: nextDismissed,
      focusedHazardId: hazardId,
    );
  }

  void upsertIncomingHazard(HazardRecord hazard) {
    final next = _upsertHazard(state.hazards, hazard);
    final nextDismissed = Set<String>.from(state.dismissedHazardIds)..remove(hazard.id);
    state = state.copyWith(
      hazards: next,
      dismissedHazardIds: nextDismissed,
    );
    _ref.read(kartaMapControllerProvider).setHazards(next);
    _ref.read(navigationSessionProvider).updateLiveHazards(next);
  }

  Future<void> voteHazard(String hazardId, String vote) async {
    final ws = _ref.read(kartaRealtimeClientProvider);
    final navSnap = _ref.read(navigationSessionProvider).current;
    final coord = navSnap.currentFix?.coordinate ?? _ref.read(kartaMapControllerProvider).center;

    if (ws.status == RealtimeConnectionState.connected) {
      ws.sendHazardVote(hazardId: hazardId, vote: vote, coordinate: coord);
    }

    try {
      final updated = await _ref.read(kartaApiClientProvider).voteHazard(
            hazardId: hazardId,
            vote: vote,
            voterSessionId: _ref.read(realtimeSessionIdProvider),
            coordinate: coord,
          );
      if (!mounted) return;
      final next = updated.status == 'active'
          ? _upsertHazard(state.hazards, updated)
          : state.hazards.where((h) => h.id != updated.id).toList();
      state = state.copyWith(hazards: next);
      _ref.read(kartaMapControllerProvider).setHazards(next);
      _ref.read(navigationSessionProvider).updateLiveHazards(next);
      _showToast(vote == 'confirm' ? 'Thanks — hazard confirmed' : 'Thanks — marked cleared');
    } catch (_) {
      if (vote == 'cleared' && mounted) {
        final next = state.hazards.where((h) => h.id != hazardId).toList();
        state = state.copyWith(hazards: next);
        _ref.read(kartaMapControllerProvider).setHazards(next);
      }
    }
  }

  void acceptRerouteProposal() {
    final proposal = state.activeRerouteProposal;
    if (proposal == null) return;
    _ref
        .read(kartaRealtimeClientProvider)
        .sendRerouteDecision(proposalId: proposal.proposalId, action: 'accept');

    final newRoute = proposal.proposedRoute;
    final planner = _ref.read(routePlannerProvider.notifier);
    planner.applyLiveReroutedCandidate(newRoute);

    state = state.copyWith(clearRerouteProposal: true);
    _ref.read(navigationSessionProvider).setRerouteProposal(null);
    _showToast('Switched to faster route (${proposal.tollDeltaDisplay})');
  }

  void dismissRerouteProposal() {
    final proposal = state.activeRerouteProposal;
    if (proposal != null) {
      _ref
          .read(kartaRealtimeClientProvider)
          .sendRerouteDecision(proposalId: proposal.proposalId, action: 'dismiss');
    }
    state = state.copyWith(clearRerouteProposal: true);
    _ref.read(navigationSessionProvider).setRerouteProposal(null);
  }

  void toggleRadialMenu([bool? open]) {
    state = state.copyWith(radialMenuOpen: open ?? !state.radialMenuOpen);
  }

  void toggleFuelOverlay([bool? open]) {
    final next = open ?? !state.activeFuelOverlayOpen;
    state = state.copyWith(activeFuelOverlayOpen: next);
    if (next) {
      _ref.read(fuelComparisonProvider.notifier).refreshForCurrentContext();
    } else {
      // Keep inline fuel price comparison pins visible automatically along active routes!
      final hasRoute = _ref.read(routePlannerProvider).selectedRoute != null;
      final inlineEnabled = _ref.read(fuelComparisonProvider).inlineRoutePinsEnabled;
      if (!hasRoute || !inlineEnabled) {
        _ref.read(kartaMapControllerProvider).setFuelPins(const <FuelStationComparison>[]);
      }
    }
  }

  void dismissTtlBanner() {
    state = state.copyWith(clearTtlBanner: true);
  }

  void showFeedbackToast(String msg) => _showToast(msg);

  void _showToast(String msg) {
    _toastClearTimer?.cancel();
    state = state.copyWith(lastToastMessage: msg);
    _toastClearTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) state = state.copyWith(clearToast: true);
    });
  }

  static List<HazardRecord> _upsertHazard(List<HazardRecord> list, HazardRecord h) {
    if (h.status != 'active') {
      return list.where((x) => x.id != h.id).toList();
    }
    final idx = list.indexWhere((x) => x.id == h.id);
    if (idx >= 0) {
      final copy = List<HazardRecord>.from(list);
      copy[idx] = h;
      return copy;
    }
    return <HazardRecord>[h, ...list];
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _statusSub?.cancel();
    _navSub?.cancel();
    _fuelPinTapSub?.cancel();
    _hazardPinTapSub?.cancel();
    _routeSub?.close();
    _toastClearTimer?.cancel();
    super.dispose();
  }
}

final realtimeCrowdsourcingProvider =
    StateNotifierProvider<RealtimeCrowdsourcingNotifier, RealtimeCrowdsourcingState>(
  (ref) => RealtimeCrowdsourcingNotifier(ref),
);

// ============================================================================
// 3. HANDS-FREE VOICE REPORTING PIPELINE (EN / BM / MANGLISH / SINGLISH)
// ============================================================================
@immutable
class HandsFreeVoiceState {
  const HandsFreeVoiceState({
    this.isListening = false,
    this.interimTranscript = '',
    this.pendingIntent,
    this.countdownSeconds = 0,
    this.statusMessage,
    this.localeTag = 'en-MY',
    this.lastTranscriptTickAt,
    this.isConfirmedFlash = false,
    this.isCancelledFlash = false,
  });

  final bool isListening;
  final String interimTranscript;
  final VoiceIntentResult? pendingIntent;
  final int countdownSeconds;
  final String? statusMessage;
  final String localeTag;
  final DateTime? lastTranscriptTickAt;
  final bool isConfirmedFlash;
  final bool isCancelledFlash;

  bool get isVisible =>
      isListening ||
      pendingIntent != null ||
      isConfirmedFlash ||
      isCancelledFlash ||
      (statusMessage != null && statusMessage!.isNotEmpty);

  HandsFreeVoiceState copyWith({
    bool? isListening,
    String? interimTranscript,
    VoiceIntentResult? pendingIntent,
    bool clearPendingIntent = false,
    int? countdownSeconds,
    String? statusMessage,
    bool clearStatus = false,
    String? localeTag,
    DateTime? lastTranscriptTickAt,
    bool? isConfirmedFlash,
    bool? isCancelledFlash,
  }) =>
      HandsFreeVoiceState(
        isListening: isListening ?? this.isListening,
        interimTranscript: interimTranscript ?? this.interimTranscript,
        pendingIntent: clearPendingIntent ? null : (pendingIntent ?? this.pendingIntent),
        countdownSeconds: countdownSeconds ?? this.countdownSeconds,
        statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
        localeTag: localeTag ?? this.localeTag,
        lastTranscriptTickAt: lastTranscriptTickAt ?? this.lastTranscriptTickAt,
        isConfirmedFlash: isConfirmedFlash ?? this.isConfirmedFlash,
        isCancelledFlash: isCancelledFlash ?? this.isCancelledFlash,
      );
}

class HandsFreeVoiceNotifier extends StateNotifier<HandsFreeVoiceState> {
  HandsFreeVoiceNotifier(this._ref)
      : _recognizer = speech_factory.createPlatformSpeechRecognizer(),
        super(const HandsFreeVoiceState());

  final Ref _ref;
  final PlatformSpeechRecognizer _recognizer;
  Timer? _countdownTimer;
  Timer? _flashDismissTimer;

  bool get isSpeechSupported => _recognizer.isSupported;

  void setLocale(String locale) {
    state = state.copyWith(localeTag: locale);
  }

  Future<void> startListening() async {
    _countdownTimer?.cancel();
    _flashDismissTimer?.cancel();
    HapticFeedback.selectionClick();
    playKartaAudioChime(_ref, 'listenStart');
    state = state.copyWith(
      isListening: true,
      interimTranscript: '',
      clearPendingIntent: true,
      countdownSeconds: 0,
      isConfirmedFlash: false,
      isCancelledFlash: false,
      statusMessage: 'Listening — speak in English, BM, Manglish or Singlish...',
    );

    if (!_recognizer.isSupported) {
      // On desktop / headless builds without a live speech engine, keep the minimal
      // bottom waveform pill active so drivers can use the quick phrase composer or
      // native platform hook without blocking the UI thread.
      return;
    }

    await _recognizer.start(
      localeTag: state.localeTag,
      onResult: (transcript, isFinal) {
        if (!mounted) return;
        state = state.copyWith(
          interimTranscript: transcript,
          lastTranscriptTickAt: DateTime.now(),
        );
        if (isFinal) {
          processTranscript(transcript);
        }
      },
      onError: (err) {
        if (!mounted) return;
        state = state.copyWith(isListening: false, statusMessage: err);
      },
      onDone: () {
        if (!mounted) return;
        if (state.isListening) {
          final text = state.interimTranscript.trim();
          state = state.copyWith(isListening: false);
          if (text.isNotEmpty && state.pendingIntent == null) {
            processTranscript(text);
          }
        }
      },
    );
  }

  void updateInterimTranscript(String transcript) {
    if (!mounted) return;
    state = state.copyWith(
      interimTranscript: transcript,
      lastTranscriptTickAt: DateTime.now(),
    );
  }

  Future<void> stopListening() async {
    if (_recognizer.isSupported) {
      await _recognizer.stop();
    }
    if (mounted) state = state.copyWith(isListening: false);
  }

  /// Parses spoken/entered transcript in <15ms on-device (with backend sync)
  /// and starts the zero-touch 3-second auto-submit countdown.
  Future<void> processTranscript(String transcript) async {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return;

    if (_recognizer.isSupported) {
      await _recognizer.stop();
    }
    // 1. Sub-15ms instant on-device regional NLU parse
    final parsed = RegionalVoiceIntentParser.parse(trimmed, locale: state.localeTag);

    if (parsed.intent == 'cancel') {
      cancelPendingReport();
      _speakAck(parsed.confirmationSpeech, 'straight');
      return;
    }

    if (parsed.intent == 'accept_reroute') {
      _ref.read(realtimeCrowdsourcingProvider.notifier).acceptRerouteProposal();
      playKartaAudioChime(_ref, 'reportConfirmed');
      HapticFeedback.mediumImpact();
      _speakAck(parsed.confirmationSpeech, 'rerouting');
      _showFlashAndDismiss(parsed.confirmationSpeech, confirmed: true);
      return;
    }

    if (parsed.intent == 'confirm_hazard' || parsed.intent == 'clear_hazard') {
      final nearest = _ref.read(realtimeCrowdsourcingProvider).highlightedHazard;
      if (nearest != null) {
        await _ref
            .read(realtimeCrowdsourcingProvider.notifier)
            .voteHazard(nearest.id, parsed.intent == 'confirm_hazard' ? 'confirm' : 'cleared');
      }
      playKartaAudioChime(_ref, 'reportConfirmed');
      HapticFeedback.mediumImpact();
      _speakAck(parsed.confirmationSpeech, 'straight');
      _showFlashAndDismiss(parsed.confirmationSpeech, confirmed: true);
      return;
    }

    if (parsed.intent == 'report_hazard' && parsed.hazardCategory != null) {
      playKartaAudioChime(_ref, 'intentDetected');
      HapticFeedback.selectionClick();
      state = state.copyWith(
        isListening: false,
        interimTranscript: trimmed,
        lastTranscriptTickAt: DateTime.now(),
        pendingIntent: parsed,
        countdownSeconds: 3,
        isConfirmedFlash: false,
        isCancelledFlash: false,
        statusMessage: 'Auto-sending in 3s — tap Cancel or say "Batal"',
      );
      _startAutoSubmitCountdown(parsed);
      return;
    }

    state = state.copyWith(
      isListening: false,
      interimTranscript: trimmed,
      clearPendingIntent: true,
      statusMessage: parsed.confirmationSpeech,
    );
  }

  void _startAutoSubmitCountdown(VoiceIntentResult parsed) {
    _countdownTimer?.cancel();
    var remaining = 3;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining -= 1;
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (remaining <= 0) {
        timer.cancel();
        submitPendingNow();
      } else {
        state = state.copyWith(
          countdownSeconds: remaining,
          statusMessage: 'Auto-sending in ${remaining}s — say "Cancel" to abort',
        );
      }
    });
  }

  Future<void> submitPendingNow() async {
    _countdownTimer?.cancel();
    final intent = state.pendingIntent;
    if (intent == null || intent.hazardCategory == null) return;

    HapticFeedback.heavyImpact();
    playKartaAudioChime(_ref, 'reportConfirmed');
    _showFlashAndDismiss(intent.confirmationSpeech, confirmed: true);

    await _ref.read(realtimeCrowdsourcingProvider.notifier).reportHazard(
          category: intent.hazardCategory!,
          subtype: intent.subtype,
          severity: intent.severity,
          oppositeSide: intent.direction == 'opposite',
          laneHint: intent.laneHint,
          description: intent.normalizedTranscript,
          source: 'voice',
        );

    _speakAck(
      intent.confirmationSpeech,
      KartaVoicePackCatalog.cueKeyForHazard(intent.hazardCategory!),
    );
  }

  void cancelPendingReport() {
    _countdownTimer?.cancel();
    HapticFeedback.lightImpact();
    playKartaAudioChime(_ref, 'cancelled');
    _showFlashAndDismiss('Voice report cancelled', confirmed: false);
  }

  void _showFlashAndDismiss(String message, {required bool confirmed}) {
    _flashDismissTimer?.cancel();
    state = state.copyWith(
      isListening: false,
      clearPendingIntent: true,
      countdownSeconds: 0,
      isConfirmedFlash: confirmed,
      isCancelledFlash: !confirmed,
      statusMessage: message,
    );
    _flashDismissTimer = Timer(Duration(milliseconds: confirmed ? 1600 : 900), () {
      if (mounted) clearBanner();
    });
  }

  void clearBanner() {
    _countdownTimer?.cancel();
    _flashDismissTimer?.cancel();
    state = state.copyWith(
      isListening: false,
      clearPendingIntent: true,
      clearStatus: true,
      countdownSeconds: 0,
      isConfirmedFlash: false,
      isCancelledFlash: false,
    );
  }

  void _speakAck(String text, String cueKey) {
    final muted = _ref.read(voiceMutedProvider);
    _ref.read(navigationVoiceEngineProvider).speakNavigationEvent(
          NavigationVoiceEvent(cueKey: cueKey, text: text, isUrgentSafety: true),
          muted: muted,
        );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _flashDismissTimer?.cancel();
    if (_recognizer.isSupported) {
      _recognizer.stop();
    }
    super.dispose();
  }
}

final handsFreeVoiceProvider = StateNotifierProvider<HandsFreeVoiceNotifier, HandsFreeVoiceState>(
  (ref) => HandsFreeVoiceNotifier(ref),
);

// ============================================================================
// 4. COMMUNITY FUEL STATION COMPARISON (MY RON95/97/DIESEL · SG 92/95/98)
// ============================================================================
@immutable
class FuelComparisonState {
  const FuelComparisonState({
    this.isLoading = false,
    this.countryCode = 'MY',
    this.selectedGrade = FuelGrade.ron95,
    this.sortBy = 'price',
    this.response,
    this.highlightedPoiId,
    this.inlineRoutePinsEnabled = true,
    this.errorMessage,
  });

  final bool isLoading;
  final String countryCode;
  final FuelGrade selectedGrade;
  final String sortBy;
  final FuelComparisonResponse? response;
  final int? highlightedPoiId;
  final bool inlineRoutePinsEnabled;
  final String? errorMessage;

  FuelComparisonState copyWith({
    bool? isLoading,
    String? countryCode,
    FuelGrade? selectedGrade,
    String? sortBy,
    FuelComparisonResponse? response,
    int? highlightedPoiId,
    bool clearHighlightedPoi = false,
    bool? inlineRoutePinsEnabled,
    String? errorMessage,
    bool clearError = false,
  }) =>
      FuelComparisonState(
        isLoading: isLoading ?? this.isLoading,
        countryCode: countryCode ?? this.countryCode,
        selectedGrade: selectedGrade ?? this.selectedGrade,
        sortBy: sortBy ?? this.sortBy,
        response: response ?? this.response,
        highlightedPoiId: clearHighlightedPoi ? null : (highlightedPoiId ?? this.highlightedPoiId),
        inlineRoutePinsEnabled: inlineRoutePinsEnabled ?? this.inlineRoutePinsEnabled,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

class FuelComparisonNotifier extends StateNotifier<FuelComparisonState> {
  FuelComparisonNotifier(this._ref) : super(const FuelComparisonState());

  final Ref _ref;

  Future<void> setCountry(String isoA2) async {
    final grades = FuelGrade.gradesForCountry(isoA2);
    state = state.copyWith(countryCode: isoA2, selectedGrade: grades.first, clearError: true);
    await refreshForCurrentContext();
  }

  Future<void> setGrade(FuelGrade grade) async {
    state = state.copyWith(selectedGrade: grade, countryCode: grade.countryCode, clearError: true);
    await refreshForCurrentContext();
  }

  Future<void> setSortBy(String sortBy) async {
    state = state.copyWith(sortBy: sortBy);
    await refreshForCurrentContext();
  }

  void highlightStation(int poiId) {
    state = state.copyWith(highlightedPoiId: poiId);
  }

  void toggleInlineRoutePins(bool enabled) {
    state = state.copyWith(inlineRoutePinsEnabled: enabled);
    if (!enabled) {
      _ref.read(kartaMapControllerProvider).setFuelPins(const <FuelStationComparison>[]);
    } else if (state.response != null) {
      _ref.read(kartaMapControllerProvider).setFuelPins(state.response!.stations);
    } else {
      hydrateAlongActiveRoute();
    }
  }

  /// Automatically loads inline fuel price-comparison badges along the active route
  /// without requiring extra taps or forcing open the bottom comparison overlay.
  Future<void> hydrateAlongActiveRoute({String? preferredCountryCode}) async {
    if (!state.inlineRoutePinsEnabled) return;
    final planner = _ref.read(routePlannerProvider);
    final selectedRoute = planner.selectedRoute;
    if (selectedRoute == null || selectedRoute.legs.isEmpty) return;

    final targetCountry = (preferredCountryCode ?? state.countryCode).toUpperCase();
    final targetGrade = state.selectedGrade.countryCode == targetCountry
        ? state.selectedGrade
        : FuelGrade.gradesForCountry(targetCountry).first;

    try {
      final resp = await _ref.read(kartaApiClientProvider).getFuelAlongRoute(
            polyline6: selectedRoute.legs.first.shapePolyline6,
            fuelGrade: targetGrade,
            countryCode: targetCountry,
            sortBy: state.sortBy,
          );
      if (!mounted) return;
      state = state.copyWith(
        countryCode: resp.countryCode,
        selectedGrade: resp.fuelGrade,
        response: resp,
        clearError: true,
      );
      _ref.read(kartaMapControllerProvider).setFuelPins(resp.stations);
    } catch (_) {
      // Silent background hydration so offline / tunnel drives never flash noisy errors
    }
  }

  void insertFuelStationAsStop(FuelStationComparison station) {
    HapticFeedback.mediumImpact();
    playKartaAudioChime(_ref, 'reportConfirmed');
    _ref.read(routePlannerProvider.notifier).setDestination(
          NamedWaypoint(
            id: 'fuel-${station.poiId}',
            label: '${station.brand ?? station.name} (${station.selectedFormattedPrice})',
            subtitle: 'Fuel Station · ${station.selectedGrade.shortLabel}',
            countryCode: station.countryCode,
            coordinate: station.coordinate,
          ),
        );
    _ref.read(realtimeCrowdsourcingProvider.notifier).toggleFuelOverlay(false);
    _ref.read(realtimeCrowdsourcingProvider.notifier).showFeedbackToast(
          'Routing to ${station.brand ?? station.name} (${station.selectedFormattedPrice}/L)',
        );
    _ref.read(routePlannerProvider.notifier).computeRoute();
  }

  Future<void> refreshForCurrentContext() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final api = _ref.read(kartaApiClientProvider);
    final planner = _ref.read(routePlannerProvider);
    final selectedRoute = planner.selectedRoute;

    try {
      FuelComparisonResponse resp;
      if (selectedRoute != null && selectedRoute.legs.isNotEmpty) {
        final poly = selectedRoute.legs.first.shapePolyline6;
        resp = await api.getFuelAlongRoute(
          polyline6: poly,
          fuelGrade: state.selectedGrade,
          countryCode: state.countryCode,
          sortBy: state.sortBy,
        );
      } else {
        final center = _ref.read(kartaMapControllerProvider).center;
        resp = await api.getFuelNearby(
          lat: center.lat,
          lon: center.lon,
          radiusMeters: 8000,
          fuelGrade: state.selectedGrade,
        );
      }
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        countryCode: resp.countryCode,
        selectedGrade: resp.fuelGrade,
        response: resp,
      );
      if (state.inlineRoutePinsEnabled) {
        _ref.read(kartaMapControllerProvider).setFuelPins(resp.stations);
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, errorMessage: 'Fuel lookup error: $e');
    }
  }

  Future<String?> submitCommunityPrice({
    required int poiId,
    required FuelGrade grade,
    required int priceMinor,
  }) async {
    try {
      final quote = await _ref.read(kartaApiClientProvider).updateFuelPrice(
            poiId: poiId,
            fuelGrade: grade,
            priceMinor: priceMinor,
            reporterSessionId: _ref.read(realtimeSessionIdProvider),
          );
      await refreshForCurrentContext();
      return 'Updated ${grade.shortLabel} to ${quote.formattedPrice}/L';
    } catch (e) {
      return 'Could not update price: $e';
    }
  }
}

final fuelComparisonProvider = StateNotifierProvider<FuelComparisonNotifier, FuelComparisonState>(
  (ref) => FuelComparisonNotifier(ref),
);

// ============================================================================
// 5. SMART COMMUTER HUB (CALENDAR TIME-TO-LEAVE + PRIVACY-FIRST CARPOOL)
// ============================================================================
@immutable
class SmartCommuterState {
  const SmartCommuterState({
    this.isEvaluatingCalendar = false,
    this.evaluations = const <TimeToLeaveEvaluation>[],
    this.isSearchingCarpool = false,
    this.activeOffers = const <CarpoolOfferPublic>[],
    this.carpoolMatches = const <CarpoolMatchCandidate>[],
    this.lastMatchRecord,
    this.statusMessage,
    this.errorMessage,
  });

  final bool isEvaluatingCalendar;
  final List<TimeToLeaveEvaluation> evaluations;
  final bool isSearchingCarpool;
  final List<CarpoolOfferPublic> activeOffers;
  final List<CarpoolMatchCandidate> carpoolMatches;
  final CarpoolMatchRecord? lastMatchRecord;
  final String? statusMessage;
  final String? errorMessage;

  SmartCommuterState copyWith({
    bool? isEvaluatingCalendar,
    List<TimeToLeaveEvaluation>? evaluations,
    bool? isSearchingCarpool,
    List<CarpoolOfferPublic>? activeOffers,
    List<CarpoolMatchCandidate>? carpoolMatches,
    CarpoolMatchRecord? lastMatchRecord,
    String? statusMessage,
    String? errorMessage,
    bool clearError = false,
  }) =>
      SmartCommuterState(
        isEvaluatingCalendar: isEvaluatingCalendar ?? this.isEvaluatingCalendar,
        evaluations: evaluations ?? this.evaluations,
        isSearchingCarpool: isSearchingCarpool ?? this.isSearchingCarpool,
        activeOffers: activeOffers ?? this.activeOffers,
        carpoolMatches: carpoolMatches ?? this.carpoolMatches,
        lastMatchRecord: lastMatchRecord ?? this.lastMatchRecord,
        statusMessage: statusMessage ?? this.statusMessage,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

class SmartCommuterNotifier extends StateNotifier<SmartCommuterState> {
  SmartCommuterNotifier(this._ref) : super(const SmartCommuterState());

  final Ref _ref;
  static const String _commuterToken = 'karta-commuter-default';

  Future<void> evaluateCalendarDepartures() async {
    state = state.copyWith(isEvaluatingCalendar: true, clearError: true);
    try {
      final origin = _ref.read(navigationSessionProvider).current.currentFix?.coordinate ??
          _ref.read(kartaMapControllerProvider).center;
      final resp = await _ref.read(kartaApiClientProvider).evaluateDepartures(
            userToken: _commuterToken,
            origin: origin,
          );
      if (!mounted) return;
      state = state.copyWith(
        isEvaluatingCalendar: false,
        evaluations: resp.evaluations,
        statusMessage: resp.evaluations.isEmpty
            ? 'No upcoming calendar events yet — import .ics or add an event.'
            : 'Evaluated ${resp.evaluations.length} events with live Valhalla traffic.',
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isEvaluatingCalendar: false, errorMessage: 'Calendar eval error: $e');
    }
  }

  Future<void> addManualCalendarEvent({
    required String title,
    required String locationText,
    Coordinate? destination,
    required DateTime startsAt,
    String provider = 'manual',
  }) async {
    state = state.copyWith(isEvaluatingCalendar: true, clearError: true);
    try {
      await _ref.read(kartaApiClientProvider).createCalendarEvent(
            userToken: _commuterToken,
            title: title,
            provider: provider,
            locationText: locationText,
            destination: destination,
            startsAt: startsAt,
          );
      await evaluateCalendarDepartures();
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isEvaluatingCalendar: false, errorMessage: 'Event save error: $e');
    }
  }

  Future<void> importIcsPayload(String icsText, {String provider = 'ics_url'}) async {
    state = state.copyWith(isEvaluatingCalendar: true, clearError: true);
    try {
      final imported = await _ref.read(kartaApiClientProvider).importCalendarIcs(
            userToken: _commuterToken,
            icsContent: icsText,
            provider: provider,
          );
      state = state.copyWith(
        statusMessage: 'Imported ${imported.length} events — computing live traffic departures...',
      );
      await evaluateCalendarDepartures();
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isEvaluatingCalendar: false, errorMessage: 'ICS import error: $e');
    }
  }

  Future<void> refreshCarpoolOffers() async {
    try {
      final offers = await _ref.read(kartaApiClientProvider).listCarpoolOffers();
      if (mounted) state = state.copyWith(activeOffers: offers);
    } catch (_) {}
  }

  Future<void> publishCarpoolOffer({
    required String alias,
    required Coordinate origin,
    required Coordinate destination,
    required DateTime departureAt,
    int seatsTotal = 3,
    String? notes,
  }) async {
    state = state.copyWith(isSearchingCarpool: true, clearError: true);
    try {
      final offer = await _ref.read(kartaApiClientProvider).createCarpoolOffer(
            driverToken: _ref.read(realtimeSessionIdProvider),
            driverAlias: alias,
            verifiedBadge: 'Verified Commuter',
            origin: origin,
            destination: destination,
            departureAt: departureAt,
            seatsTotal: seatsTotal,
            notes: notes,
          );
      if (!mounted) return;
      state = state.copyWith(
        isSearchingCarpool: false,
        activeOffers: <CarpoolOfferPublic>[offer, ...state.activeOffers],
        statusMessage: 'Published privacy-shielded offer (${offer.originLandmarkName})',
      );
      _showOfferOnMap(offer);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isSearchingCarpool: false, errorMessage: 'Carpool offer error: $e');
    }
  }

  Future<void> searchCarpoolMatches({
    required Coordinate pickup,
    required Coordinate dropoff,
    required DateTime departureAt,
  }) async {
    state = state.copyWith(isSearchingCarpool: true, clearError: true);
    try {
      final matches = await _ref.read(kartaApiClientProvider).searchCarpoolMatches(
            riderToken: 'rider-${_ref.read(realtimeSessionIdProvider)}',
            pickup: pickup,
            dropoff: dropoff,
            departureAt: departureAt,
          );
      if (!mounted) return;
      state = state.copyWith(
        isSearchingCarpool: false,
        carpoolMatches: matches,
        statusMessage: matches.isEmpty
            ? 'No same-direction commuters matched yet — try posting an offer.'
            : 'Found ${matches.length} privacy-shielded same-direction matches.',
      );
      if (matches.isNotEmpty) {
        _showOfferOnMap(matches.first.offer);
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isSearchingCarpool: false, errorMessage: 'Carpool match error: $e');
    }
  }

  Future<void> requestSeat({
    required CarpoolMatchCandidate candidate,
    required String riderAlias,
    required Coordinate pickup,
    required Coordinate dropoff,
  }) async {
    try {
      final rec = await _ref.read(kartaApiClientProvider).requestCarpoolSeat(
            offerId: candidate.offer.id,
            riderToken: 'rider-${_ref.read(realtimeSessionIdProvider)}',
            riderAlias: riderAlias,
            pickup: pickup,
            dropoff: dropoff,
            rendezvousNote: 'Meeting at ${candidate.pickupLandmarkName}',
          );
      if (!mounted) return;
      state = state.copyWith(
        lastMatchRecord: rec,
        statusMessage: 'Seat requested with ${rec.driverAlias} — exact pin hidden until accepted.',
      );
    } catch (e) {
      if (mounted) state = state.copyWith(errorMessage: 'Request error: $e');
    }
  }

  void previewCarpoolOnMap(CarpoolOfferPublic offer) => _showOfferOnMap(offer);

  /// One-tap direct route assignment for Smart Calendar "Time to Leave" cards
  /// (strictly single-destination Start -> Destination navigation).
  void insertCalendarEventIntoRoute(TimeToLeaveEvaluation eval) {
    final dest = eval.event.destination;
    if (dest == null) return;
    HapticFeedback.mediumImpact();
    playKartaAudioChime(_ref, 'reportConfirmed');
    final wp = NamedWaypoint(
      id: 'cal-${eval.event.id}',
      label: eval.event.title,
      subtitle: eval.event.locationText ?? 'Calendar Event',
      countryCode: eval.event.countryCode,
      coordinate: dest,
    );
    final planner = _ref.read(routePlannerProvider.notifier);
    planner.setDestination(wp);
    state = state.copyWith(statusMessage: 'Routing to "${eval.event.title}"');
    _ref.read(realtimeCrowdsourcingProvider.notifier).showFeedbackToast(
          'Routing to "${eval.event.title}" — live traffic active',
        );
    _ref.read(activeNavTabProvider.notifier).state = 'navigate';
    planner.computeRoute();
  }

  /// One-tap direct route assignment for Privacy-First Carpool matches:
  /// sets the 500m privacy-fuzzed pickup as Origin and dropoff as Destination
  /// (strictly single-leg Start -> Destination) and paints the 500m shield zones.
  void insertCarpoolIntoRoute(CarpoolMatchCandidate match) {
    HapticFeedback.mediumImpact();
    playKartaAudioChime(_ref, 'reportConfirmed');
    final planner = _ref.read(routePlannerProvider.notifier);
    planner.setOrigin(
      NamedWaypoint(
        id: 'carpool-pickup-${match.offer.id}',
        label: 'Pickup: ${match.pickupLandmarkName}',
        subtitle: '500m Privacy Zone · ${match.offer.driverAlias}',
        countryCode: match.offer.countryCode,
        coordinate: match.pickupZoneCenter,
      ),
    );
    planner.setDestination(
      NamedWaypoint(
        id: 'carpool-dropoff-${match.offer.id}',
        label: 'Dropoff: ${match.dropoffLandmarkName}',
        subtitle: '500m Privacy Zone · Split ${match.splitCostFormatted}',
        countryCode: match.offer.countryCode,
        coordinate: match.dropoffZoneCenter,
      ),
    );
    _showOfferOnMap(match.offer);
    state = state.copyWith(
      statusMessage:
          'Routing from ${match.pickupLandmarkName} to ${match.dropoffLandmarkName}',
    );
    _ref.read(realtimeCrowdsourcingProvider.notifier).showFeedbackToast(
          'Carpool route ready (500m Privacy Zone active)',
        );
    _ref.read(activeNavTabProvider.notifier).state = 'navigate';
    planner.computeRoute();
  }

  void clearCarpoolMapOverlay() {
    _ref.read(kartaMapControllerProvider).setCarpoolOverlay(null);
  }

  void _showOfferOnMap(CarpoolOfferPublic offer) {
    final pts = offer.routePolyline6.isNotEmpty
        ? decodePolyline6(offer.routePolyline6)
        : <Coordinate>[offer.originZoneCenter, offer.destZoneCenter];
    _ref.read(kartaMapControllerProvider).setCarpoolOverlay(
          CarpoolMapOverlay(
            corridorPoints: pts,
            originZoneCenter: offer.originZoneCenter,
            destZoneCenter: offer.destZoneCenter,
            privacyRadiusMeters: offer.privacyRadiusM,
            originLabel: offer.originLandmarkName,
            destLabel: offer.destLandmarkName,
          ),
        );
  }
}

final smartCommuterProvider = StateNotifierProvider<SmartCommuterNotifier, SmartCommuterState>(
  (ref) => SmartCommuterNotifier(ref),
);
