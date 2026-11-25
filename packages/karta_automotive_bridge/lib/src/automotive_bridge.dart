import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import 'automotive_models.dart';

/// Bidirectional cross-platform automotive bridge & Phone <-> Vehicle handoff
/// coordinator streaming headless [NavigationSnapshot]s, route geometry,
/// offline PMTiles config, privacy scrubs, and adaptive thermal budgets to:
/// - `native/ios/KartaCarPlay` (`CPTemplateApplicationSceneDelegate` / `CPMapTemplate`)
/// - `native/android/karta-android-auto` (`CarAppService` / `NavigationTemplate`)
///
/// Strictly decoupled from Flutter UI widgets so it can run inside a headless
/// background isolate or alongside `KartaAppShell`.
class KartaAutomotiveBridge {
  KartaAutomotiveBridge({
    MethodChannel? channel,
    LocationPrivacyGuard? privacyGuard,
    ThermalAdaptationController? thermalController,
    bool enablePlatformChannel = !kIsWeb,
    DateTime Function()? clock,
  })  : _channel = channel ?? const MethodChannel('com.karta.navigation/automotive_bridge'),
        _privacyGuard = privacyGuard,
        _thermalController = thermalController,
        _enablePlatformChannel = enablePlatformChannel,
        _clock = clock ?? DateTime.now {
    if (_enablePlatformChannel) {
      _channel.setMethodCallHandler(_handleInboundMethodCall);
    }
    if (_thermalController != null) {
      _thermalSub = _thermalController.stream.listen(_onThermalProfileUpdated);
    }
  }

  static const String channelName = 'com.karta.navigation/automotive_bridge';

  final MethodChannel _channel;
  final LocationPrivacyGuard? _privacyGuard;
  final ThermalAdaptationController? _thermalController;
  final bool _enablePlatformChannel;
  final DateTime Function() _clock;

  final StreamController<AutomotiveConnectionState> _connectionController =
      StreamController<AutomotiveConnectionState>.broadcast();
  final StreamController<AutomotiveInboundEvent> _inboundController =
      StreamController<AutomotiveInboundEvent>.broadcast();

  StreamSubscription<NavigationSnapshot>? _navSub;
  StreamSubscription<ThermalRenderProfile>? _thermalSub;

  NavigationSessionController? _session;
  AutomotiveConnectionState _connectionState = const AutomotiveConnectionState();
  AutomotiveRouteGeometryPayload? _activeRouteGeometry;
  List<AutomotiveHazardPin> _activeHazards = const <AutomotiveHazardPin>[];
  AutomotiveOfflineMapConfig _offlineConfig = const AutomotiveOfflineMapConfig(
    activePmtilesUrl: 'http://localhost:8081/my-sg-bn-full.pmtiles',
  );

  int _sequenceId = 0;
  String _activeTripId = '';
  bool _voiceMuted = false;
  bool _isDarkMode = true;
  bool _isRouteOverviewActive = false;
  DateTime? _lastFramePublishedAt;
  NavigationPhase? _lastPublishedPhase;
  int? _lastPublishedManeuverIdx;
  String? _lastPublishedHazardId;
  String? _lastPublishedRerouteId;

  bool get isConnectedToHeadUnit => _connectionState.isConnected;
  AutomotiveConnectionState get connectionState => _connectionState;
  Stream<AutomotiveConnectionState> get connectionStateStream => _connectionController.stream;
  Stream<AutomotiveInboundEvent> get inboundEvents => _inboundController.stream;
  int get lastSequenceId => _sequenceId;
  bool get isDarkMode => _isDarkMode;
  bool get isRouteOverviewActive => _isRouteOverviewActive;

  /// Binds headless [NavigationSessionController] telemetry to the automotive bridge.
  void attachSession(NavigationSessionController session) {
    _session = session;
    _navSub?.cancel();
    _navSub = session.stream.listen(_onSnapshot);
  }

  /// Synchronizes active route geometry (Valhalla polyline6 + congestion + destination)
  /// to connected head units and caches it for immediate Phone -> Car handoff.
  Future<void> updateActiveRoute({
    required CandidateRoute? route,
    required String originName,
    required String destinationName,
    required Coordinate destinationCoordinate,
    List<CandidateRoute> alternates = const <CandidateRoute>[],
  }) async {
    if (route == null) {
      _activeRouteGeometry = null;
      _activeTripId = '';
      if (isConnectedToHeadUnit) {
        await _invokeHost('endAutomotiveSession', <String, dynamic>{'reason': 'route_cleared'});
        await _scrubNativeAndLocalIfAllowed(scrubLocal: false);
      }
      return;
    }

    final mergedPoints = RouteGeometryIndex.fromRoute(route).points;
    final poly6 = mergedPoints.isNotEmpty
        ? encodePolyline6(mergedPoints)
        : (route.legs.isNotEmpty ? route.legs.first.shapePolyline6 : '');
    final altPolys = alternates
        .where((r) => r.routeIndex != route.routeIndex && r.legs.isNotEmpty)
        .map((r) => r.legs.first.shapePolyline6)
        .toList();

    _activeTripId = 'karta-trip-${_clock().millisecondsSinceEpoch.toRadixString(36)}';
    _activeRouteGeometry = AutomotiveRouteGeometryPayload(
      tripId: _activeTripId,
      routePolyline6: poly6,
      alternatePolylines6: altPolys,
      congestionSegments: route.congestionSegments,
      originName: originName,
      destinationName: destinationName,
      destinationLat: destinationCoordinate.lat,
      destinationLon: destinationCoordinate.lon,
      tollDisplayTotal: route.tolls.displayTotal,
      hasTolls: route.tolls.hasTolls,
    );

    if (isConnectedToHeadUnit) {
      await _invokeHost('updateRouteGeometry', _activeRouteGeometry!.toMap());
    }
  }

  /// Updates live crowdsourced hazards displayed on the head-unit MapLibre overlay.
  Future<void> updateHazards(List<HazardRecord> hazards) async {
    _activeHazards = hazards.map(AutomotiveHazardPin.fromRecord).toList(growable: false);
    if (isConnectedToHeadUnit) {
      await _invokeHost(
        'updateHazards',
        <String, dynamic>{
          'hazards': _activeHazards.map((h) => h.toMap()).toList(),
        },
      );
    }
  }

  /// Pushes offline map mode & downloaded MY/SG/BN PMTiles pack metadata to the head unit.
  Future<void> updateOfflineMapConfig(AutomotiveOfflineMapConfig config) async {
    _offlineConfig = config;
    if (isConnectedToHeadUnit) {
      await _invokeHost('updateOfflineMapConfig', config.toMap());
    }
  }

  /// Syncs mute button state onto the CarPlay / Android Auto action bar.
  void setVoiceMuted(bool muted) {
    _voiceMuted = muted;
    final snap = _session?.current;
    if (snap != null && isConnectedToHeadUnit) {
      _publishSnapshot(snap, force: true);
    }
  }

  /// Pushes resolved Obsidian Night / Tropical Daylight lighting state to the
  /// connected head unit (e.g., manual override or SMART Tunnel / KPE dip).
  Future<void> setVehicleAppearance(bool isDarkMode) async {
    if (_isDarkMode == isDarkMode) return;
    _isDarkMode = isDarkMode;
    if (isConnectedToHeadUnit) {
      await _invokeHost('setVehicleAppearance', <String, dynamic>{'isDarkMode': isDarkMode});
      final snap = _session?.current;
      if (snap != null) {
        await _publishSnapshot(snap, force: true);
      }
    }
  }

  /// Toggles Route Overview mode across head unit and phone companion view.
  void setRouteOverviewActive(bool active) {
    if (_isRouteOverviewActive == active) return;
    _isRouteOverviewActive = active;
    final snap = _session?.current;
    if (snap != null && isConnectedToHeadUnit) {
      _publishSnapshot(snap, force: true);
    }
  }

  /// Triggers an immediate full-state Phone -> Car handoff synchronization
  /// (e.g., called automatically when CarPlay / Android Auto connects).
  Future<void> syncFullStateToHeadUnit() async {
    final snap = _session?.current ?? const NavigationSnapshot(phase: NavigationPhase.idle);
    final frame = buildFrameFromSnapshot(snap, incrementSequence: true);
    final profile = _thermalController?.currentProfile ??
        ThermalAdaptationController().currentProfile;
    final privacy = _privacyGuard?.policy ?? const LocationPrivacyPolicy.strictDefault();

    final envelope = AutomotiveHandoffEnvelope(
      sequenceId: frame.sequenceId,
      tripId: _activeTripId,
      frame: frame,
      routeGeometry: _activeRouteGeometry,
      hazards: _activeHazards,
      thermalProfile: profile,
      offlineConfig: _offlineConfig,
      retainTripHistoryOptIn: privacy.retainTripHistoryOptIn,
      disableMapTelemetry: !privacy.allowAnalyticsTelemetry,
      isDarkMode: _isDarkMode,
    );

    await _invokeHost('syncFullState', envelope.toMap());
  }

  /// Explicitly scrubs native head-unit ephemeral GPS state across the bridge.
  Future<void> scrubHeadUnitLocationState() async {
    await _invokeHost('scrubEphemeralLocationState', const <String, dynamic>{});
  }

  /// Drives a real Phone -> Car handoff transition from either a native connect
  /// callback or the Karta Driver Studio vehicle-link verifier.
  Future<void> handleHeadUnitConnected(AutomotiveHeadUnitInfo info) async {
    _isDarkMode = info.isDarkMode;
    _isRouteOverviewActive = false;
    _setConnectionState(
      _connectionState.copyWith(
        phase: AutomotiveHandoffPhase.handingOffToCar,
        platform: info.platform,
        headUnitInfo: info,
        lastTransitionAt: _clock(),
      ),
    );

    // Notify thermal governor immediately so dual-screen GPU throttling activates
    // before the head unit starts rendering MapLibre frames.
    _thermalController?.setProjectedToHeadUnit(true, platform: info.platform.wireValue);

    await syncFullStateToHeadUnit();

    _setConnectionState(
      _connectionState.copyWith(
        phase: AutomotiveHandoffPhase.projectedActive,
        platform: info.platform,
        headUnitInfo: info,
        lastSequenceId: _sequenceId,
        handoffCount: _connectionState.handoffCount + 1,
        lastTransitionAt: _clock(),
      ),
    );

    _emitInbound(HeadUnitConnectedEvent(info));
  }

  /// Drives a graceful Car -> Phone handoff transition when USB/wireless
  /// projection disconnects: scrubs native location RAM and restores phone 3D HUD.
  Future<void> handleHeadUnitDisconnected({
    required AutomotivePlatform platform,
    String reason = 'vehicle_disconnected',
    int? lastSequenceId,
  }) async {
    _setConnectionState(
      _connectionState.copyWith(
        phase: AutomotiveHandoffPhase.handingOffToPhone,
        lastDisconnectReason: reason,
        lastSequenceId: lastSequenceId ?? _sequenceId,
        lastTransitionAt: _clock(),
      ),
    );

    await _scrubNativeAndLocalIfAllowed(
      scrubLocal: _session?.current.phase != NavigationPhase.navigating,
    );

    // Restore full unprojected phone FPS / 3D buildings budget.
    _thermalController?.setProjectedToHeadUnit(false);

    _setConnectionState(
      _connectionState.copyWith(
        phase: AutomotiveHandoffPhase.phoneOnly,
        platform: AutomotivePlatform.none,
        clearHeadUnitInfo: true,
        lastDisconnectReason: reason,
        lastSequenceId: lastSequenceId ?? _sequenceId,
        handoffCount: _connectionState.handoffCount + 1,
        lastTransitionAt: _clock(),
      ),
    );

    _emitInbound(
      HeadUnitDisconnectedEvent(
        platform: platform,
        reason: reason,
        lastSequenceId: lastSequenceId ?? _sequenceId,
      ),
    );
  }

  /// Builds a strongly-typed [AutomotiveNavigationFrame] from a headless [NavigationSnapshot].
  AutomotiveNavigationFrame buildFrameFromSnapshot(
    NavigationSnapshot snap, {
    bool incrementSequence = true,
  }) {
    if (incrementSequence) {
      _sequenceId += 1;
    }
    final laneItems = snap.laneGuidance.roadLanes
        .map(
          (l) => AutomotiveLaneItem(
            laneSpec: l.laneSpec,
            isRecommended: l.isRecommended,
          ),
        )
        .toList(growable: false);
    final nearestHazard = snap.nearestHazard;
    final reroute = snap.activeRerouteProposal;
    final etaMs = snap.estimatedArrival.millisecondsSinceEpoch;

    return AutomotiveNavigationFrame(
      sequenceId: _sequenceId,
      tripId: _activeTripId,
      isNavigating: snap.phase == NavigationPhase.navigating,
      phase: snap.phase.name,
      currentLat: snap.currentFix?.coordinate.lat,
      currentLon: snap.currentFix?.coordinate.lon,
      bearingDeg: snap.currentFix?.bearingDeg,
      accuracyMeters: snap.currentFix?.accuracyMeters,
      maneuverType: snap.currentManeuver?.type ?? 8,
      primaryInstruction: snap.currentManeuver?.instruction ?? 'Ready to navigate',
      secondaryInstruction: snap.nextManeuver?.instruction,
      nextManeuverType: snap.nextManeuver?.type,
      roadRef: snap.roadContext?.roadRef,
      roadName: snap.roadContext?.roadName ??
          (snap.currentManeuver != null && snap.currentManeuver!.streetNames.isNotEmpty
              ? snap.currentManeuver!.streetNames.first
              : null),
      drivingSide: snap.activeCountry.drivingSide,
      distanceToManeuverMeters: snap.distanceToManeuverMeters,
      remainingDistanceMeters: snap.remainingDistanceMeters,
      remainingDurationSeconds: snap.remainingDurationSeconds,
      etaEpochMs: etaMs,
      currentSpeedKmh: snap.speedTelemetry.currentSpeedKmh,
      speedLimitKmh: snap.speedTelemetry.speedLimitKmh,
      speedAlertLevel: snap.speedTelemetry.severity.name,
      countryCode: snap.activeCountry.isoA2,
      currencyCode: snap.activeCountry.currencyCode,
      currencySymbol: snap.activeCountry.currencySymbol,
      tripTollSummaryText: snap.activeRoute?.tolls.displayTotal ?? 'Free',
      turnLanes: laneItems.map((l) => l.laneSpec).toList(growable: false),
      laneItems: laneItems,
      approachingTollName: snap.laneGuidance.approachingTollGantry?.name,
      approachingTollDistanceMeters: snap.laneGuidance.approachingTollGantry?.distanceMeters,
      approachingTollPayments: snap.laneGuidance.approachingTollGantry?.acceptedPayments
              .map((p) => p.wireValue)
              .toList(growable: false) ??
          const <String>[],
      approachingHazardId: nearestHazard?.id,
      approachingHazardCategory: nearestHazard?.category.wireValue,
      approachingHazardLabel: nearestHazard?.category.label,
      approachingHazardDistanceMeters: nearestHazard?.distanceMeters,
      liveTrafficDelaySeconds: snap.liveTrafficDelaySeconds,
      rerouteProposalId: reroute?.proposalId,
      rerouteBannerText: reroute != null
          ? '${reroute.reason} · Saves ${(reroute.timeSavedSeconds / 60).round()} min'
          : null,
      rerouteTimeSavedSeconds: reroute?.timeSavedSeconds,
      rerouteTollDeltaText: reroute?.tollDeltaDisplay,
      isOffRoute: snap.isOffRoute,
      voiceMuted: _voiceMuted,
      isDarkMode: _isDarkMode,
      isRouteOverviewActive: _isRouteOverviewActive,
    );
  }

  void _onSnapshot(NavigationSnapshot snap) {
    _publishSnapshot(snap, force: false);
  }

  Future<void> _publishSnapshot(NavigationSnapshot snap, {required bool force}) async {
    if (!_enablePlatformChannel) return;

    // Never throttle high-priority navigation transitions (phase/maneuver/hazard/reroute)
    final isPriorityChange = force ||
        snap.phase != _lastPublishedPhase ||
        snap.currentManeuverIndex != _lastPublishedManeuverIdx ||
        snap.nearestHazard?.id != _lastPublishedHazardId ||
        snap.activeRerouteProposal?.proposalId != _lastPublishedRerouteId;

    final now = _clock();
    final minIntervalMs = _thermalController?.currentProfile.bridgePublishIntervalMs ?? 100;
    if (!isPriorityChange &&
        _lastFramePublishedAt != null &&
        now.difference(_lastFramePublishedAt!).inMilliseconds < minIntervalMs) {
      return;
    }

    _lastFramePublishedAt = now;
    _lastPublishedPhase = snap.phase;
    _lastPublishedManeuverIdx = snap.currentManeuverIndex;
    _lastPublishedHazardId = snap.nearestHazard?.id;
    _lastPublishedRerouteId = snap.activeRerouteProposal?.proposalId;

    final frame = buildFrameFromSnapshot(snap, incrementSequence: true);

    final ok = await _invokeHost('publishNavigationFrame', frame.toMap());
    if (ok && !isConnectedToHeadUnit) {
      // Backward compatibility if a native host accepts frames prior to sending connect info
      _setConnectionState(
        _connectionState.copyWith(
          phase: AutomotiveHandoffPhase.projectedActive,
          lastSequenceId: frame.sequenceId,
          lastTransitionAt: now,
        ),
      );
    }

    if (snap.phase == NavigationPhase.idle && isConnectedToHeadUnit) {
      await _scrubNativeAndLocalIfAllowed(scrubLocal: false);
    }
  }

  Future<void> _onThermalProfileUpdated(ThermalRenderProfile profile) async {
    if (!isConnectedToHeadUnit) return;
    await _invokeHost('applyThermalRenderProfile', profile.toMap());
  }

  Future<void> _scrubNativeAndLocalIfAllowed({required bool scrubLocal}) async {
    final policy = _privacyGuard?.policy ?? const LocationPrivacyPolicy.strictDefault();
    if (policy.scrubOnHeadUnitDisconnect || policy.scrubOnSessionEnd) {
      await _invokeHost('scrubEphemeralLocationState', const <String, dynamic>{});
      if (scrubLocal) {
        _privacyGuard?.scrubEphemeralState();
      }
    }
  }

  /// Dispatches inbound native CarPlay & Android Auto actions into the shared Dart layer.
  Future<dynamic> _handleInboundMethodCall(MethodCall call) async {
    final args = (call.arguments is Map)
        ? Map<Object?, Object?>.from(call.arguments as Map<Object?, Object?>)
        : const <Object?, Object?>{};

    switch (call.method) {
      case 'onHeadUnitConnected':
        await handleHeadUnitConnected(AutomotiveHeadUnitInfo.fromMap(args));
        return true;

      case 'onHeadUnitDisconnected':
        _isRouteOverviewActive = false;
        await handleHeadUnitDisconnected(
          platform: AutomotivePlatform.fromWire(args['platform'] as String?),
          reason: (args['reason'] as String?) ?? 'vehicle_disconnected',
          lastSequenceId: (args['lastSequenceId'] as num?)?.toInt(),
        );
        return true;

      case 'onHeadUnitAppearanceChanged':
        final platform = AutomotivePlatform.fromWire(args['platform'] as String?);
        final isDark = (args['isDarkMode'] as bool?) ?? true;
        final source = (args['source'] as String?) ?? 'vehicle_headlight_sensor';
        _isDarkMode = isDark;
        _emitInbound(
          HeadUnitAppearanceChangedEvent(
            platform: platform,
            isDarkMode: isDark,
            source: source,
          ),
        );
        return true;

      case 'onQuickReportHazard':
        final cat = HazardCategory.fromWire((args['category'] as String?) ?? 'accident');
        final sev = HazardSeverity.fromWire((args['severity'] as String?) ?? 'medium');
        final opposite = (args['oppositeSide'] as bool?) ?? false;
        final source = (args['source'] as String?) ?? _connectionState.platform.wireValue;
        _emitInbound(
          QuickReportHazardEvent(
            category: cat,
            severity: sev,
            oppositeSide: opposite,
            source: source,
          ),
        );
        return true;

      case 'onHazardVote':
        final hazardId = (args['hazardId'] as String?) ?? '';
        final vote = (args['vote'] as String?) ?? 'confirm';
        if (hazardId.isNotEmpty) {
          _emitInbound(HazardVoteEvent(hazardId: hazardId, vote: vote));
        }
        return true;

      case 'onVoiceReportTriggered':
        _emitInbound(
          VoiceReportTriggerEvent(
            localeTag: (args['localeTag'] as String?) ?? 'en-MY',
          ),
        );
        return true;

      case 'onVoiceTranscriptCaptured':
        _emitInbound(
          VoiceReportTriggerEvent(
            localeTag: (args['localeTag'] as String?) ?? 'en-MY',
            transcript: (args['transcript'] as String?) ?? '',
          ),
        );
        return true;

      case 'onRerouteDecision':
        final proposalId = (args['proposalId'] as String?) ?? '';
        final accepted = (args['accepted'] as bool?) ?? false;
        if (proposalId.isNotEmpty) {
          _emitInbound(RerouteDecisionEvent(proposalId: proposalId, accepted: accepted));
        }
        return true;

      case 'onNavigationControlAction':
        final action = (args['action'] as String?) ?? '';
        if (action == 'toggle_overview') {
          _isRouteOverviewActive = !_isRouteOverviewActive;
        } else if (action == 'recenter' || action == 'end_trip') {
          _isRouteOverviewActive = false;
        }
        if (action.isNotEmpty) {
          _emitInbound(NavigationControlEvent(action));
        }
        return true;

      case 'onThermalStateChanged':
        final platform = AutomotivePlatform.fromWire(args['platform'] as String?);
        final thermalLevel = DeviceThermalLevel.fromWire(
          (args['thermalLevel'] as String?) ?? 'nominal',
        );
        final batteryLevel = (args['batteryLevelPercent'] as num?)?.toInt();
        final isCharging = (args['isCharging'] as bool?) ?? false;
        final batteryTemp = (args['batteryTempCelsius'] as num?)?.toDouble();
        final lowPower = (args['isLowPowerMode'] as bool?) ?? false;

        _thermalController?.updateTelemetry(
          ThermalTelemetryInput(
            deviceThermalLevel: thermalLevel,
            batteryLevelPercent: batteryLevel,
            isCharging: isCharging,
            batteryTempCelsius: batteryTemp,
            isLowPowerMode: lowPower,
            isProjectedToHeadUnit: isConnectedToHeadUnit,
            headUnitPlatform: platform.wireValue,
            timestamp: _clock(),
          ),
        );

        _emitInbound(
          DeviceThermalReportEvent(
            platform: platform,
            thermalLevel: thermalLevel,
            batteryLevelPercent: batteryLevel,
            isCharging: isCharging,
            batteryTempCelsius: batteryTemp,
            isLowPowerMode: lowPower,
          ),
        );
        return true;

      default:
        return null;
    }
  }

  /// Directly injects an inbound event for Driver Studio simulation or unit tests.
  Future<void> dispatchSyntheticNativeCall(String method, Map<String, dynamic> arguments) {
    return _handleInboundMethodCall(MethodCall(method, arguments));
  }

  Future<bool> _invokeHost(String method, Map<String, dynamic> payload) async {
    if (!_enablePlatformChannel) return false;
    try {
      await _channel.invokeMethod<void>(method, payload);
      return true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  void _setConnectionState(AutomotiveConnectionState next) {
    _connectionState = next;
    if (!_connectionController.isClosed) {
      _connectionController.add(next);
    }
  }

  void _emitInbound(AutomotiveInboundEvent event) {
    if (!_inboundController.isClosed) {
      _inboundController.add(event);
    }
  }

  void dispose() {
    if (_enablePlatformChannel) {
      _channel.setMethodCallHandler(null);
    }
    _navSub?.cancel();
    _thermalSub?.cancel();
    _connectionController.close();
    _inboundController.close();
  }
}
