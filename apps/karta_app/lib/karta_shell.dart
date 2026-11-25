import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_automotive_bridge/karta_automotive_bridge.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_map_engine/karta_map_engine.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import 'features/account/account_saved_places_panel.dart';
import 'features/automotive/companion_turn_list_overlay.dart';
import 'features/commuter/commuter_hub_panel.dart';
import 'features/fuel/fuel_comparison_overlay.dart';
import 'features/hazards/live_hazard_banners.dart';
import 'features/hazards/radial_hazard_menu.dart';
import 'features/look_around/street_look_around_modal.dart';
import 'features/navigation/active_navigation_hud.dart';
import 'features/offline/offline_map_manager_panel.dart';
import 'features/personalization/studio_panel.dart';
import 'features/search/unified_search_panel.dart';
import 'services/live_location_platform.dart';
import 'state/auth_saved_places_providers.dart';
import 'state/karta_app_state.dart';
import 'state/lighting_providers.dart';
import 'state/phase3_providers.dart';
import 'state/phase4_automotive_providers.dart';

/// Root responsive shell adapting seamlessly across Smartphone (< 640dp),
/// Tablet & Standard Automotive (640–1079dp), and Desktop & Wide Automotive
/// (>= 1080dp) with real-time GPS tracking, Google Maps-style POI & dropped-pin
/// inspection, automatic Day/Night lighting, and zero-overlap HUD layout.
class KartaAppShell extends ConsumerStatefulWidget {
  const KartaAppShell({super.key});

  @override
  ConsumerState<KartaAppShell> createState() => _KartaAppShellState();
}

class _KartaAppShellState extends ConsumerState<KartaAppShell> {
  StreamSubscription<Coordinate>? _mapTapSub;
  StreamSubscription<int>? _poiTapSub;
  StreamSubscription<int>? _routeCalloutTapSub;
  StreamSubscription<KartaViewportBounds>? _viewportSub;
  DateTime? _lastBboxPoiFetch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(kartaAutomotiveBridgeProvider);
      ref.read(authSavedPlacesProvider);
      ref.read(realtimeCrowdsourcingProvider.notifier).initialize();
      ref.read(offlineRegionManagerProvider).hydrateLocalPoiIndex(limit: 2500);
      ref.read(liveLocationProvider.notifier).startTracking(centerOnFirstFix: true);

      final mapCtrl = ref.read(kartaMapControllerProvider);
      _mapTapSub = mapCtrl.onMapTap.listen(_handleMapTap);
      _poiTapSub = mapCtrl.onPoiPinTap.listen(_handlePoiPinTap);
      _routeCalloutTapSub = mapCtrl.onRouteCalloutTap.listen(_handleRouteCalloutTap);
      _viewportSub = mapCtrl.onViewportChanged.listen(_handleViewportChanged);
    });
  }

  @override
  void dispose() {
    _mapTapSub?.cancel();
    _poiTapSub?.cancel();
    _routeCalloutTapSub?.cancel();
    _viewportSub?.cancel();
    super.dispose();
  }

  void _handleRouteCalloutTap(int routeIndex) {
    if (!mounted) return;
    ref.read(routePlannerProvider.notifier).selectRouteIndex(routeIndex);
  }

  Future<void> _handleViewportChanged(KartaViewportBounds bounds) async {
    if (!mounted || bounds.zoom < 11.2) return;
    final now = DateTime.now();
    if (_lastBboxPoiFetch != null && now.difference(_lastBboxPoiFetch!).inMilliseconds < 900) {
      return;
    }
    _lastBboxPoiFetch = now;
    try {
      final resp = await ref.read(kartaApiClientProvider).getPoisInBbox(
            bbox: BoundingBox(
              minLon: bounds.minLon,
              minLat: bounds.minLat,
              maxLon: bounds.maxLon,
              maxLat: bounds.maxLat,
            ),
            limit: 120,
          );
      if (!mounted) return;
      ref.read(connectivityResilienceProvider).recordNetworkSuccess();
      if (resp.items.isNotEmpty) {
        ref.read(kartaMapControllerProvider).setPois(resp.items);
      }
    } catch (_) {
      // Quietly rely on vector tile landmarks if backend is offline
    }
  }

  void _handlePoiPinTap(int poiId) {
    if (!mounted) return;
    final mapCtrl = ref.read(kartaMapControllerProvider);
    PoiItem? matched;
    for (final p in mapCtrl.pois) {
      if (p.id == poiId) {
        matched = p;
        break;
      }
    }
    if (matched == null) return;
    ref.read(selectedPoiProvider.notifier).state = matched;
    ref.read(inspectedMapSpotProvider.notifier).state = null;
    mapCtrl.setDroppedPin(coordinate: matched.coordinate, label: matched.name);
    ref.read(activeNavTabProvider.notifier).state = 'navigate';
    mapCtrl.easeTo(center: matched.coordinate, zoom: 16.0, pitch: mapCtrl.is3DEnabled ? 54 : 0);
  }

  Future<void> _handleMapTap(Coordinate coord) async {
    if (!mounted) return;
    final navPhase = ref.read(navigationSessionProvider).current.phase;
    if (navPhase == NavigationPhase.navigating) return;

    final mapCtrl = ref.read(kartaMapControllerProvider);
    final coordText = '${coord.lat.toStringAsFixed(5)}, ${coord.lon.toStringAsFixed(5)}';
    ref.read(selectedPoiProvider.notifier).state = null;
    ref.read(inspectedMapSpotProvider.notifier).state = InspectedMapSpot(
      coordinate: coord,
      title: 'Dropped Pin',
      subtitle: coordText,
      category: 'unnamed_place',
    );
    mapCtrl.setDroppedPin(coordinate: coord, label: 'Dropped Pin');
    ref.read(activeNavTabProvider.notifier).state = 'navigate';

    try {
      final ctx = await ref.read(kartaApiClientProvider).getRoadContext(
            lat: coord.lat,
            lon: coord.lon,
          );
      if (!mounted) return;
      final currentSpot = ref.read(inspectedMapSpotProvider);
      if (currentSpot == null || currentSpot.coordinate != coord) return;

      final roadName = ctx.roadName?.trim();
      final roadRef = ctx.roadRef?.trim();
      final resolvedTitle = (roadName != null && roadName.isNotEmpty)
          ? roadName
          : (roadRef != null && roadRef.isNotEmpty
              ? 'Route $roadRef'
              : 'Unnamed Place');
      final subtitleParts = <String>[
        if (roadRef != null && roadRef.isNotEmpty && resolvedTitle != 'Route $roadRef')
          roadRef,
        if (ctx.country?.name != null) ctx.country!.name,
        coordText,
      ];
      ref.read(inspectedMapSpotProvider.notifier).state = InspectedMapSpot(
        coordinate: coord,
        title: resolvedTitle,
        subtitle: subtitleParts.join(' · '),
        category: ctx.highwayClass ?? 'place',
        countryCode: ctx.country?.isoA2,
        roadRef: roadRef,
      );
      mapCtrl.setDroppedPin(coordinate: coord, label: resolvedTitle);
    } catch (_) {
      // Keep coordinate dropped pin visible even offline
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapCtrl = ref.watch(kartaMapControllerProvider);
    final pmtilesUrl = ref.watch(kartaPmtilesUrlProvider);
    final selectedTab = ref.watch(activeNavTabProvider);
    final navSnapAsync = ref.watch(navigationSnapshotProvider);
    final lookAroundTarget = ref.watch(lookAroundTargetProvider);
    final rtState = ref.watch(realtimeCrowdsourcingProvider);
    final voiceState = ref.watch(handsFreeVoiceProvider);
    final lighting = ref.watch(kartaLightingProvider);
    final liveLoc = ref.watch(liveLocationProvider);
    final mobileSheetExpanded = ref.watch(mobileNavSheetExpandedProvider);
    final autoConn = ref.watch(automotiveConnectionProvider).valueOrNull ??
        const AutomotiveConnectionState();
    final companionEnabled = ref.watch(companionTurnListEnabledProvider);
    final thermalProfile = ref.watch(thermalRenderProfileProvider).valueOrNull;
    final connSnap = ref.watch(connectivitySnapshotProvider).valueOrNull ??
        ref.read(connectivityResilienceProvider).current;

    final navSnap = navSnapAsync.valueOrNull ?? const NavigationSnapshot(phase: NavigationPhase.idle);
    final isNavigating = navSnap.phase == NavigationPhase.navigating;
    final showCompanionMode = autoConn.isConnected && companionEnabled && isNavigating;
    final showAutomotiveStrip = autoConn.isConnected ||
        (thermalProfile != null && thermalProfile.effectiveTier != DeviceThermalLevel.nominal);
    final pillVisualMode = switch (connSnap.mode) {
      NetworkTransitionState.online => KartaConnectivityVisualMode.online,
      NetworkTransitionState.offlineRoutingActive => KartaConnectivityVisualMode.offlineRoutingActive,
      NetworkTransitionState.syncingQuietly => KartaConnectivityVisualMode.syncingQuietly,
    };

    final authState = ref.watch(authSavedPlacesProvider);
    final navItems = <KartaNavRailItem>[
      const KartaNavRailItem(id: 'navigate', label: 'Navigate', icon: Icons.explore_rounded),
      KartaNavRailItem(
        id: 'saved',
        label: 'Saved',
        icon: Icons.bookmarks_rounded,
        badgeCount: authState.savedPlaces.length,
      ),
      const KartaNavRailItem(id: 'commute', label: 'Commute', icon: Icons.commute_rounded),
      const KartaNavRailItem(
          id: 'offline', label: 'Offline', icon: Icons.download_for_offline_rounded),
      const KartaNavRailItem(
          id: 'vehicle', label: 'Vehicle', icon: Icons.navigation_rounded),
    ];

    final Widget activeSidePanel = AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.04, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: switch (selectedTab) {
        'saved' => const AccountSavedPlacesPanel(key: ValueKey<String>('panel-saved')),
        'commute' => const CommuterHubPanel(key: ValueKey<String>('panel-commute')),
        'offline' => const OfflineMapManagerPanel(key: ValueKey<String>('panel-offline')),
        'vehicle' => const KartaStudioPanel(key: ValueKey<String>('panel-vehicle')),
        _ => const UnifiedNavigationPanel(key: ValueKey<String>('panel-navigate')),
      },
    );

    final hasTopHudContent = pillVisualMode != KartaConnectivityVisualMode.online ||
        showAutomotiveStrip ||
        isNavigating;

    final Widget? topHudStack = hasTopHudContent
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (pillVisualMode != KartaConnectivityVisualMode.online) ...<Widget>[
                Align(
                  alignment: Alignment.topCenter,
                  child: KartaOfflineStatusPill(
                    mode: pillVisualMode,
                    regionLabel: connSnap.activeOfflineRegion ?? navSnap.activeCountry.name,
                    pendingSyncCount: connSnap.pendingSyncCount,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (showAutomotiveStrip) ...<Widget>[
                _AutomotiveProjectionStatusBanner(
                  connection: autoConn,
                  thermal: thermalProfile,
                  showTurnListButton: autoConn.isConnected && isNavigating && !companionEnabled,
                  onOpenTurnList: () =>
                      ref.read(companionTurnListEnabledProvider.notifier).state = true,
                ),
                const SizedBox(height: 6),
              ],
              if (isNavigating) TopManeuverHudBanner(snapshot: navSnap),
            ],
          )
        : null;

    Widget? bottomCenterWidget;
    if (rtState.activeFuelOverlayOpen) {
      bottomCenterWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const FuelComparisonOverlay(),
          if (isNavigating) ...<Widget>[
            const SizedBox(height: 8),
            NavigationTripDock(snapshot: navSnap),
          ],
        ],
      );
    } else if (isNavigating) {
      bottomCenterWidget = NavigationTripDock(snapshot: navSnap);
    }

    Widget? activeModal;
    if (rtState.radialMenuOpen) {
      activeModal = const RadialHazardMenuOverlay();
    } else if (lookAroundTarget != null) {
      activeModal = StreetLookAroundOverlay(target: lookAroundTarget);
    }

    void handleOpenLookAround() {
      ref.read(lookAroundTargetProvider.notifier).state = StreetLookAroundTarget(
        coordinate: mapCtrl.center,
        headingDeg: mapCtrl.bearing,
        title: '3D Street-Level Look-Around',
        subtitle: 'Tap presets or drag bearing to inspect buildings',
      );
    }

    void handleRecenter() {
      if (isNavigating && navSnap.currentFix != null) {
        mapCtrl.followNavigationFix(
          navSnap.currentFix!,
          forceLock: true,
          distanceToManeuverMeters: navSnap.distanceToManeuverMeters,
        );
      } else {
        ref.read(liveLocationProvider.notifier).locateAndCenter(setAsOrigin: false).then((locked) {
          if (!locked && mounted) {
            final fallback = liveLoc.coordinate ?? KartaRegionalAnchors.klcc.coordinate;
            mapCtrl.easeTo(
              center: fallback,
              zoom: 15.6,
              pitch: mapCtrl.is3DEnabled ? 54 : 0,
            );
          }
        });
      }
    }

    return KartaAdaptiveScaffold(
      navItems: navItems,
      selectedNavId: selectedTab,
      onSelectNav: (id) => ref.read(activeNavTabProvider.notifier).state = id,
      hideSidePanel: isNavigating && selectedTab == 'navigate',
      mobileSheetExpanded: mobileSheetExpanded,
      mapLayer: KartaMapView(
        controller: mapCtrl,
        pmtilesUrl: pmtilesUrl,
        initialCenter: liveLoc.coordinate ?? KartaRegionalAnchors.klcc.coordinate,
        initialZoom: 14.8,
        initialPitch: 48.0,
      ),
      sidePanel: activeSidePanel,
      topHudOverlay: topHudStack,
      cornerHazardOverlay: const SpatialHazardCornerPill(),
      topRightControls: _MapUtilityButtons(
        axis: Axis.vertical,
        mapCtrl: mapCtrl,
        lighting: lighting,
        liveLocation: liveLoc,
        isNavigating: isNavigating,
        onCycleLighting: () => ref.read(kartaLightingProvider.notifier).cyclePreference(),
        onOpenLookAround: handleOpenLookAround,
        onRecenter: handleRecenter,
      ),
      topRightControlsHorizontal: _MapUtilityButtons(
        axis: Axis.horizontal,
        mapCtrl: mapCtrl,
        lighting: lighting,
        liveLocation: liveLoc,
        isNavigating: isNavigating,
        onCycleLighting: () => ref.read(kartaLightingProvider.notifier).cyclePreference(),
        onOpenLookAround: handleOpenLookAround,
        onRecenter: handleRecenter,
      ),
      floatingRightOverlay: const FloatingCrowdsourcingTriggerCluster(),
      bottomLeftOverlay: isNavigating ? SpeedTelemetryCluster(snapshot: navSnap) : null,
      bottomCenterOverlay: bottomCenterWidget,
      bottomVoiceWaveformOverlay: voiceState.isVisible ? const BottomVoiceWaveformPill() : null,
      mobileActiveSheetOverlay: isNavigating ? MobileActiveNavigationSheet(snapshot: navSnap) : null,
      bottomRightOverlay: null,
      companionOverlay: IgnorePointer(
        ignoring: !showCompanionMode,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          reverseDuration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: showCompanionMode
              ? KartaPointerShield(
                  key: const ValueKey<String>('karta-companion-turn-list'),
                  child: KartaCompanionTurnListOverlay(
                    snapshot: navSnap,
                    connection: autoConn,
                    thermal: thermalProfile,
                    lighting: lighting,
                    onShowLiveMap: () =>
                        ref.read(companionTurnListEnabledProvider.notifier).state = false,
                  ),
                )
              : const SizedBox.shrink(key: ValueKey<String>('karta-companion-empty')),
        ),
      ),
      modalOverlay: activeModal,
    );
  }
}

class _MapUtilityButtons extends StatelessWidget {
  const _MapUtilityButtons({
    required this.axis,
    required this.mapCtrl,
    required this.lighting,
    required this.liveLocation,
    required this.isNavigating,
    required this.onCycleLighting,
    required this.onOpenLookAround,
    required this.onRecenter,
  });

  final Axis axis;
  final KartaMapController mapCtrl;
  final KartaLightingState lighting;
  final LiveLocationSnapshot liveLocation;
  final bool isNavigating;
  final VoidCallback onCycleLighting;
  final VoidCallback onOpenLookAround;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    final isTunnelActive = lighting.isInTunnel || lighting.tunnelHoldActive;
    final lightingIcon = isTunnelActive
        ? Icons.nights_stay_rounded
        : (lighting.preference == KartaLightingPreference.auto
            ? (lighting.isDaylight ? Icons.wb_sunny_rounded : Icons.brightness_auto_rounded)
            : (lighting.isDaylight ? Icons.light_mode_rounded : Icons.dark_mode_rounded));
    final lightingLabel = isTunnelActive
        ? 'TUNNEL'
        : lighting.vehicleHeadlightSynced
            ? (lighting.isDaylight ? 'CAR' : 'CAR')
            : switch (lighting.preference) {
                KartaLightingPreference.auto => 'AUTO',
                KartaLightingPreference.day => 'DAY',
                KartaLightingPreference.night => 'NIGHT',
              };
    final lightingTooltip =
        '${lighting.statusChipLabel} (Sun ${lighting.solarElevationDeg >= 0 ? '+' : ''}${lighting.solarElevationDeg.toStringAsFixed(1)}°) — Tap to switch lighting mode';

    final isHorizontal = axis == Axis.horizontal;
    final double targetMin = isNavigating && !isHorizontal
        ? KartaSpacing.minDrivingTouchTarget
        : KartaSpacing.minTouchTarget;

    final locIcon = liveLocation.status == LiveLocationStatus.requesting
        ? Icons.gps_not_fixed_rounded
        : (liveLocation.hasLiveFix ? Icons.my_location_rounded : Icons.location_searching_rounded);
    final locTooltip = isNavigating
        ? 'Re-center on vehicle'
        : (liveLocation.hasLiveFix
            ? 'Center on Your Live Location (${liveLocation.placeLabel ?? 'GPS Active'})'
            : 'Detect My Current GPS Location');

    final buttons = <Widget>[
      _MapActionPill(
        key: const ValueKey<String>('karta-lighting-toggle'),
        tooltip: lightingTooltip,
        icon: lightingIcon,
        label: isHorizontal ? null : lightingLabel,
        active: lighting.isDaylight || isTunnelActive,
        minExtent: targetMin,
        onTap: onCycleLighting,
      ),
      _MapActionPill(
        tooltip: mapCtrl.is3DEnabled ? 'Switch to 2D Flat Map' : 'Enable 3D Extruded Buildings',
        icon: mapCtrl.is3DEnabled ? Icons.view_in_ar_rounded : Icons.map_rounded,
        label: isHorizontal ? null : (mapCtrl.is3DEnabled ? '3D' : '2D'),
        active: mapCtrl.is3DEnabled,
        minExtent: targetMin,
        onTap: mapCtrl.toggle3DBuildings,
      ),
      _MapActionPill(
        tooltip: 'Reset Compass North',
        icon: Icons.explore_outlined,
        minExtent: targetMin,
        onTap: mapCtrl.resetNorth,
      ),
      if (!isHorizontal)
        _MapActionPill(
          tooltip: 'Street-Level Look-Around Preview',
          icon: Icons.streetview_rounded,
          active: false,
          minExtent: targetMin,
          onTap: onOpenLookAround,
        ),
      _MapActionPill(
        key: const ValueKey<String>('karta-my-location-btn'),
        tooltip: locTooltip,
        icon: locIcon,
        active: liveLocation.hasLiveFix || (isNavigating && !mapCtrl.isCameraLocked),
        minExtent: targetMin,
        onTap: onRecenter,
      ),
    ];

    if (isHorizontal) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: buttons,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < buttons.length; i++) ...<Widget>[
          buttons[i],
          if (i < buttons.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _MapActionPill extends StatelessWidget {
  const _MapActionPill({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.label,
    this.active = false,
    this.minExtent = KartaSpacing.minTouchTarget,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final bool active;
  final double minExtent;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minExtent, minHeight: minExtent),
          child: KartaSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            borderRadius: 14,
            highlighted: active,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: 21,
                  color: active ? palette.accentBright : palette.textPrimary,
                ),
                if (label != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    label!,
                    style: KartaTypography.monoBadge.copyWith(
                      fontSize: 11,
                      color: active ? palette.accentBright : palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AutomotiveProjectionStatusBanner extends StatelessWidget {
  const _AutomotiveProjectionStatusBanner({
    required this.connection,
    required this.thermal,
    this.showTurnListButton = false,
    this.onOpenTurnList,
  });

  final AutomotiveConnectionState connection;
  final ThermalRenderProfile? thermal;
  final bool showTurnListButton;
  final VoidCallback? onOpenTurnList;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final isHot = thermal != null && thermal!.effectiveTier != DeviceThermalLevel.nominal;
    final accent = isHot ? palette.statusCaution : palette.accentBright;
    final headline = connection.isConnected
        ? '${connection.platform.label} Active · Companion ${thermal?.pausePhoneMapCanvas == true ? 'Canvas Paused' : '${thermal?.phoneTargetFps ?? 15} fps'}'
        : 'Thermal Governor · ${thermal?.effectiveTier.label ?? 'Throttling'} (${thermal?.phoneTargetFps ?? 30} fps)';

    return KartaSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      borderRadius: 12,
      deepGlass: true,
      borderColor: accent.withValues(alpha: 0.7),
      child: Row(
        children: <Widget>[
          Icon(
            connection.isConnected ? Icons.connected_tv_rounded : Icons.thermostat_rounded,
            size: 16,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KartaTypography.monoBadge.copyWith(
                fontSize: 11,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (showTurnListButton && onOpenTurnList != null)
            InkWell(
              key: const ValueKey<String>('banner-open-turn-list'),
              onTap: onOpenTurnList,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.accentGlow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.accentPrimary),
                  ),
                  child: Text(
                    'TURN LIST',
                    style: KartaTypography.monoBadge.copyWith(
                      fontSize: 11,
                      color: palette.accentBright,
                    ),
                  ),
                ),
              ),
            )
          else
            Text(
              'ZERO-RETENTION GPS',
              style: KartaTypography.monoBadge.copyWith(
                fontSize: 11,
                color: palette.accentBright,
              ),
            ),
        ],
      ),
    );
  }
}
