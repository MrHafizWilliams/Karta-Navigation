import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_automotive_bridge/karta_automotive_bridge.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import 'karta_app_state.dart';
import 'lighting_providers.dart';
import 'phase3_providers.dart';

/// User-toggleable preference for the Phone-to-Car "Turn List & Next-Stop Companion" mode.
/// Defaults to `true` so plugging into CarPlay/Android Auto during navigation smoothly
/// opens the high-legibility companion view while keeping GPS & media uninterrupted.
final companionTurnListEnabledProvider = StateProvider<bool>((ref) => true);

/// Tracks whether the connected vehicle head unit is currently in 1-tap Route Overview mode.
final automotiveRouteOverviewProvider = StateProvider<bool>((ref) => false);

// ============================================================================
// 1. ON-DEVICE LOCATION PRIVACY GUARD (ZERO RAW GPS HISTORY BY DEFAULT)
// ============================================================================
final locationPrivacyGuardProvider = Provider<LocationPrivacyGuard>((ref) {
  final guard = LocationPrivacyGuard(
    policy: const LocationPrivacyPolicy.strictDefault(),
  );
  ref.onDispose(guard.dispose);
  return guard;
});

final privacyAuditProvider = StreamProvider<PrivacyAuditSnapshot>((ref) async* {
  final guard = ref.watch(locationPrivacyGuardProvider);
  yield guard.auditSnapshot;
  yield* guard.auditStream;
});

// ============================================================================
// 2. ADAPTIVE THERMAL & FRAME-RATE GOVERNOR (CARPLAY / ANDROID AUTO + PHONE)
// ============================================================================
final thermalAdaptationControllerProvider = Provider<ThermalAdaptationController>((ref) {
  final ctrl = ThermalAdaptationController();
  final mapCtrl = ref.read(kartaMapControllerProvider);

  // Push initial budget and listen for every thermal or projection transition.
  mapCtrl.applyThermalRenderProfile(ctrl.currentProfile);
  final sub = ctrl.stream.listen(mapCtrl.applyThermalRenderProfile);

  ref.onDispose(() {
    sub.cancel();
    ctrl.dispose();
  });
  return ctrl;
});

final thermalRenderProfileProvider = StreamProvider<ThermalRenderProfile>((ref) async* {
  final ctrl = ref.watch(thermalAdaptationControllerProvider);
  yield ctrl.currentProfile;
  yield* ctrl.stream;
});

// ============================================================================
// 3. BIDIRECTIONAL NATIVE AUTOMOTIVE BRIDGE & HANDOFF ORCHESTRATOR
// ============================================================================
final kartaAutomotiveBridgeProvider = Provider<KartaAutomotiveBridge>((ref) {
  final privacy = ref.watch(locationPrivacyGuardProvider);
  final thermal = ref.watch(thermalAdaptationControllerProvider);
  final session = ref.watch(navigationSessionProvider);
  final offlineMgr = ref.watch(offlineRegionManagerProvider);

  final bridge = KartaAutomotiveBridge(
    privacyGuard: privacy,
    thermalController: thermal,
  )..attachSession(session);

  // Sync offline PMTiles config whenever downloads or offline toggle change
  void syncOfflineConfig() {
    final offlineMode = ref.read(offlineModeEnabledProvider);
    final pmtilesUrl = ref.read(kartaPmtilesUrlProvider);
    bridge.updateOfflineMapConfig(
      AutomotiveOfflineMapConfig(
        offlineModeEnabled: offlineMode,
        activePmtilesUrl: pmtilesUrl,
        downloadedRegions: offlineMgr.downloadedRegionDescriptors(),
      ),
    );
  }

  syncOfflineConfig();

  final offlineSub = offlineMgr.stream.listen((_) => syncOfflineConfig());
  final offlineToggleSub = ref.listen<bool>(offlineModeEnabledProvider, (_, __) {
    syncOfflineConfig();
  });
  final muteSub = ref.listen<bool>(voiceMutedProvider, (_, nextMuted) {
    bridge.setVoiceMuted(nextMuted);
  });
  final lightingSub = ref.listen<KartaLightingState>(kartaLightingProvider, (prev, next) {
    if (prev?.resolvedMode == next.resolvedMode) return;
    // Propagate tunnel dips or explicit manual phone overrides back to CarPlay / Android Auto
    // without echoing vehicle-originated headlight sensor transitions.
    if (next.reason != KartaLightingReason.vehicleHeadlightSensor) {
      bridge.setVehicleAppearance(next.isNight);
    }
  });

  // Wire inbound CarPlay & Android Auto actions directly to shared Karta controllers
  final inboundSub = bridge.inboundEvents.listen((event) {
    switch (event) {
      case HeadUnitConnectedEvent():
        // Sync vehicle headlight/dimmer appearance immediately on connect
        ref.read(kartaLightingProvider.notifier).applyVehicleHeadlightOverride(
              event.info.isDarkMode,
            );
        // Push latest route & hazards cleanly on Phone -> Car handoff
        final planner = ref.read(routePlannerProvider);
        final selected = planner.selectedRoute;
        if (selected != null && planner.stops.length >= 2) {
          bridge.updateActiveRoute(
            route: selected,
            originName: planner.stops.first.label,
            destinationName: planner.stops.last.label,
            destinationCoordinate: planner.stops.last.coordinate,
            alternates: planner.routeResponse?.routes ?? const [],
          );
        }
        bridge.updateHazards(ref.read(realtimeCrowdsourcingProvider).hazards);
        syncOfflineConfig();
        break;

      case HeadUnitAppearanceChangedEvent():
        ref.read(kartaLightingProvider.notifier).applyVehicleHeadlightOverride(
              event.isDarkMode,
            );
        break;

      case HeadUnitDisconnectedEvent():
        // Release vehicle headlight override & route overview state on Car -> Phone handoff
        ref.read(kartaLightingProvider.notifier).applyVehicleHeadlightOverride(null);
        ref.read(automotiveRouteOverviewProvider.notifier).state = false;
        // Restore interactive 3D camera lock if trip is still active (GPS never drops!)
        final snap = session.current;
        if (snap.phase == NavigationPhase.navigating && snap.currentFix != null) {
          ref.read(kartaMapControllerProvider).followNavigationFix(
                snap.currentFix!,
                forceLock: true,
              );
        }
        break;

      case QuickReportHazardEvent():
        ref.read(realtimeCrowdsourcingProvider.notifier).reportHazard(
              category: event.category,
              severity: event.severity,
              oppositeSide: event.oppositeSide,
              source: event.source,
            );
        break;

      case HazardVoteEvent():
        ref.read(realtimeCrowdsourcingProvider.notifier).voteHazard(
              event.hazardId,
              event.vote,
            );
        break;

      case VoiceReportTriggerEvent():
        final voice = ref.read(handsFreeVoiceProvider.notifier);
        voice.setLocale(event.localeTag);
        if (event.transcript != null && event.transcript!.trim().isNotEmpty) {
          voice.processTranscript(event.transcript!);
        } else {
          voice.startListening();
        }
        break;

      case RerouteDecisionEvent():
        final rt = ref.read(realtimeCrowdsourcingProvider.notifier);
        if (event.accepted) {
          rt.acceptRerouteProposal();
        } else {
          rt.dismissRerouteProposal();
        }
        break;

      case NavigationControlEvent():
        switch (event.action) {
          case 'end_trip':
            ref.read(automotiveRouteOverviewProvider.notifier).state = false;
            ref.read(routePlannerProvider.notifier).endActiveNavigation();
            break;
          case 'toggle_mute':
            final muted = ref.read(voiceMutedProvider);
            ref.read(voiceMutedProvider.notifier).state = !muted;
            break;
          case 'toggle_overview':
            ref.read(automotiveRouteOverviewProvider.notifier).state =
                bridge.isRouteOverviewActive;
            break;
          case 'recenter':
            ref.read(automotiveRouteOverviewProvider.notifier).state = false;
            final fix = session.current.currentFix;
            if (fix != null) {
              ref.read(kartaMapControllerProvider).followNavigationFix(fix, forceLock: true);
            }
            break;
          case 'request_fuel_stops':
            ref.read(realtimeCrowdsourcingProvider.notifier).toggleFuelOverlay(true);
            break;
        }
        break;

      case DeviceThermalReportEvent():
        // Already forwarded into ThermalAdaptationController inside KartaAutomotiveBridge
        break;
    }
  });

  ref.onDispose(() {
    offlineSub.cancel();
    offlineToggleSub.close();
    muteSub.close();
    lightingSub.close();
    inboundSub.cancel();
    bridge.dispose();
  });

  return bridge;
});

final automotiveConnectionProvider = StreamProvider<AutomotiveConnectionState>((ref) async* {
  final bridge = ref.watch(kartaAutomotiveBridgeProvider);
  yield bridge.connectionState;
  yield* bridge.connectionStateStream;
});
