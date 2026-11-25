import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_map_engine/karta_map_engine.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import '../../state/karta_app_state.dart';
import '../../state/lighting_providers.dart';
import '../../state/phase3_providers.dart';

/// Top Turn-by-Turn Maneuver HUD Banner with realistic color-coded MY/SG/BN highway
/// signboards (Emerald Expressway Green vs Cobalt Federal Blue) and animated lane-guidance.
class TopManeuverHudBanner extends ConsumerWidget {
  const TopManeuverHudBanner({super.key, required this.snapshot});

  final NavigationSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final man = snapshot.currentManeuver;
    final nextMan = snapshot.nextManeuver;
    final roadRef = snapshot.roadContext?.roadRef ??
        (man != null && man.streetNames.isNotEmpty
            ? _extractShieldRef(man.streetNames)
            : null);
    final roadName = (man != null && man.streetNames.isNotEmpty)
        ? man.streetNames.first
        : (snapshot.roadContext?.roadName ?? 'Following route');
    final laneGuidance = snapshot.laneGuidance;

    final animatedLanes = <KartaAnimatedLaneSpec>[
      for (final lane in laneGuidance.roadLanes)
        KartaAnimatedLaneSpec(
          laneSpec: lane.laneSpec,
          isRecommended: lane.isRecommended,
        ),
    ];
    final hasLanes = animatedLanes.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KartaHighwaySignboard(
          valhallaManeuverType: man?.type ?? 8,
          distanceText: RegionalCurrencyFormatter.formatDistance(
            snapshot.distanceToManeuverMeters,
          ),
          primaryInstruction: man?.instruction ?? roadName,
          roadRef: roadRef,
          highwayClass: snapshot.roadContext?.highwayClass ??
              (man?.highway == true ? 'motorway' : null),
          countryCode: snapshot.activeCountry.isoA2,
          isTollRoad: false,
          exitLabel: _extractExitLabel(man?.instruction),
        ),

        // Secondary "Then" Maneuver + Animated Lane-Guidance Strip
        if (nextMan != null || hasLanes) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              if (hasLanes)
                Expanded(
                  flex: 3,
                  child: KartaAnimatedLaneGuidanceStrip(lanes: animatedLanes),
                ),
              if (hasLanes && nextMan != null) const SizedBox(width: 8),
              if (nextMan != null)
                Expanded(
                  flex: 2,
                  child: KartaSurfaceCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    borderRadius: 12,
                    deepGlass: true,
                    child: Row(
                      children: <Widget>[
                        Text(
                          'THEN',
                          style: KartaTypography.monoBadge.copyWith(
                            fontSize: 11,
                            color: palette.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        KartaManeuverIcon(
                          valhallaType: nextMan.type,
                          size: 18,
                          color: palette.textPrimary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            nextMan.instruction,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KartaTypography.bodySecondary.copyWith(
                              color: palette.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static final RegExp _shieldPattern = RegExp(
    r'\b(E\d{1,2}|FT\d{1,3}|CTE|PIE|AYE|ECP|BKE|SLE|KJE|TPE|MCE|KPE)\b',
    caseSensitive: false,
  );

  static final RegExp _exitPattern = RegExp(r'\bEXIT\s+\d+[A-Z]?\b', caseSensitive: false);

  static String? _extractShieldRef(List<String> streetNames) {
    for (final s in streetNames) {
      final m = _shieldPattern.firstMatch(s);
      if (m != null) return m.group(0)!.toUpperCase();
    }
    return null;
  }

  static String? _extractExitLabel(String? instruction) {
    if (instruction == null) return null;
    final m = _exitPattern.firstMatch(instruction);
    return m?.group(0)?.toUpperCase();
  }
}

/// Live Speed vs Speed Limit Cluster + Active Country/Currency Indicator (MY RM / SG $ / BN B$)
/// + Approaching AWAS / Singapore TP Speed Camera Warning Pill.
class SpeedTelemetryCluster extends ConsumerWidget {
  const SpeedTelemetryCluster({super.key, required this.snapshot});

  final NavigationSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final mapCtrl = ref.watch(kartaMapControllerProvider);
    final lighting = ref.watch(kartaLightingProvider);
    final speed = snapshot.speedTelemetry;
    final country = snapshot.activeCountry;
    final alertColor = switch (speed.severity) {
      SpeedAlertSeverity.alert => palette.statusAlert,
      SpeedAlertSeverity.caution => palette.statusCaution,
      SpeedAlertSeverity.normal => palette.accentPrimary,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Approaching AWAS / TP Speed Camera Alert (constrained to cluster width)
        if (speed.approachingCamera != null) ...<Widget>[
          KartaSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            borderRadius: 11,
            borderColor: palette.statusAlert,
            backgroundColor: palette.statusAlert.withValues(alpha: palette.isDaylight ? 0.16 : 0.24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.photo_camera_front_rounded, size: 16, color: palette.statusAlert),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${speed.approachingCamera!.zoneType == 'tp_speed_camera' ? 'TP CAM' : 'AWAS'} · '
                    '${RegionalCurrencyFormatter.formatDistance(speed.approachingCamera!.distanceMeters)} '
                    '(${speed.approachingCamera!.limitKmh} km/h)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KartaTypography.monoBadge.copyWith(
                      color: palette.textPrimary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],

        // Speedometer + Speed Limit Sign + Country Currency & Declutter Tag
        KartaSurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          borderRadius: 16,
          deepGlass: true,
          borderColor: speed.severity == SpeedAlertSeverity.normal
              ? palette.borderSubtle
              : alertColor,
          backgroundColor: speed.severity == SpeedAlertSeverity.alert
              ? palette.statusAlert.withValues(alpha: palette.isDaylight ? 0.15 : 0.22)
              : palette.hudDeepGlass,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Circular MY/SG/BN Speed Limit Sign
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.statusAlert, width: 4.5),
                ),
                child: Text(
                  speed.speedLimitKmh?.toString() ?? '--',
                  style: KartaTypography.telemetryValue.copyWith(
                    fontSize: 16.5,
                    color: const Color(0xFF11161C),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Live Current Speed Readout
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        speed.currentSpeedKmh.round().toString(),
                        style: KartaTypography.hudHero.copyWith(
                          fontSize: 30,
                          color: speed.severity == SpeedAlertSeverity.normal
                              ? palette.textPrimary
                              : alertColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'km/h',
                        style: KartaTypography.captionLabel.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 5,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: palette.accentGlow,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          country.isoA2,
                          style: KartaTypography.monoBadge.copyWith(
                            fontSize: 11,
                            color: palette.accentBright,
                          ),
                        ),
                      ),
                      if (lighting.isInTunnel || lighting.tunnelHoldActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.statusCaution.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'TUNNEL',
                            style: KartaTypography.monoBadge.copyWith(
                              fontSize: 11,
                              color: palette.statusCaution,
                            ),
                          ),
                        )
                      else if (mapCtrl.minorLabelsDecluttered)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.surfaceElevated,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'HWY',
                            style: KartaTypography.monoBadge.copyWith(
                              fontSize: 11,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      if (speed.overLimitByKmh > 0)
                        Text(
                          '+${speed.overLimitByKmh} OVER',
                          style: KartaTypography.monoBadge.copyWith(
                            fontSize: 11,
                            color: alertColor,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bottom Trip Telemetry Dock for Desktop & Tablet with Fitts's Law 60x60dp
/// ergonomic driving action targets + interactive speed/tunnel simulation bar.
class NavigationTripDock extends ConsumerWidget {
  const NavigationTripDock({super.key, required this.snapshot});

  final NavigationSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final playback = ref.watch(activePlaybackSourceProvider);
    final voiceMuted = ref.watch(voiceMutedProvider);
    final eta = snapshot.estimatedArrival;
    final etaStr = '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactDock = constraints.maxWidth < 460;
        final ultraCompactDock = constraints.maxWidth < 380;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (playback != null) ...<Widget>[
              _PlaybackSimulationStrip(playback: playback),
              const SizedBox(height: 6),
            ],

            // Primary Automotive ETA / Remaining Distance + Fitts's Law 60x60dp Driving Buttons
            KartaSurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              borderRadius: 18,
              deepGlass: true,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(
                              RegionalCurrencyFormatter.formatDuration(
                                snapshot.remainingDurationSeconds,
                              ),
                              style: KartaTypography.telemetryValue.copyWith(
                                color: palette.accentBright,
                                fontSize: 22,
                              ),
                            ),
                            Text(
                              'ETA $etaStr',
                              style: KartaTypography.monoBadge.copyWith(
                                color: palette.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${RegionalCurrencyFormatter.formatDistance(snapshot.remainingDistanceMeters)} remaining',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KartaTypography.bodySecondary.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _DrivingActionTarget(
                    key: const ValueKey<String>('nav-action-mute'),
                    tooltip: voiceMuted ? 'Unmute Voice Guidance' : 'Mute Voice Guidance',
                    icon: voiceMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    label: voiceMuted ? 'Muted' : 'Audio',
                    color: voiceMuted ? palette.textSecondary : palette.textPrimary,
                    onTap: () => ref.read(voiceMutedProvider.notifier).state = !voiceMuted,
                  ),
                  if (!ultraCompactDock) ...<Widget>[
                    const SizedBox(width: 6),
                    _DrivingActionTarget(
                      key: const ValueKey<String>('nav-action-voice'),
                      tooltip: 'Hands-Free Voice Hazard Report',
                      icon: Icons.mic_rounded,
                      label: 'Voice',
                      color: palette.accentBright,
                      onTap: () => ref.read(handsFreeVoiceProvider.notifier).startListening(),
                    ),
                  ],
                  if (!compactDock) ...<Widget>[
                    const SizedBox(width: 6),
                    _DrivingActionTarget(
                      key: const ValueKey<String>('nav-action-fuel'),
                      tooltip: 'Compare Fuel Prices Along Route',
                      icon: Icons.local_gas_station_rounded,
                      label: 'Fuel',
                      color: palette.statusClear,
                      onTap: () =>
                          ref.read(realtimeCrowdsourcingProvider.notifier).toggleFuelOverlay(),
                    ),
                    const SizedBox(width: 6),
                    _DrivingActionTarget(
                      key: const ValueKey<String>('nav-action-lookaround'),
                      tooltip: 'Street Look-Around Here',
                      icon: Icons.streetview_rounded,
                      label: '3D View',
                      color: palette.accentBright,
                      onTap: () {
                        final coord = snapshot.currentFix?.coordinate ??
                            ref.read(kartaMapControllerProvider).center;
                        ref.read(lookAroundTargetProvider.notifier).state = StreetLookAroundTarget(
                          coordinate: coord,
                          headingDeg: snapshot.currentFix?.bearingDeg ?? 0,
                          title: snapshot.roadContext?.roadName ?? 'Current Route Position',
                          subtitle: '${snapshot.activeCountry.name} · Street-Level Preview',
                        );
                      },
                    ),
                  ],
                  const SizedBox(width: 8),
                  _DrivingEndButton(
                    key: const ValueKey<String>('nav-action-end'),
                    onTap: () => ref.read(routePlannerProvider.notifier).endActiveNavigation(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Mobile 3-State Spring-Physics Draggable Bottom Sheet for Active Navigation:
/// 1. Collapsed (~102dp): Compact ETA pill + 60x60dp End target.
/// 2. Half-Expanded (~50%): 60x60dp lower-thumb actions + Unified Media Bar + Fuel/Sim strip.
/// 3. Full-Expanded (~84%): Scrollable Turn-by-Turn Maneuver Itinerary across all legs.
class MobileActiveNavigationSheet extends ConsumerWidget {
  const MobileActiveNavigationSheet({super.key, required this.snapshot});

  final NavigationSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final playback = ref.watch(activePlaybackSourceProvider);
    final voiceMuted = ref.watch(voiceMutedProvider);
    final eta = snapshot.estimatedArrival;
    final etaStr = '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';

    final collapsedEtaPill = Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    RegionalCurrencyFormatter.formatDuration(
                      snapshot.remainingDurationSeconds,
                    ),
                    style: KartaTypography.telemetryValue.copyWith(
                      color: palette.accentBright,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    'ETA $etaStr',
                    style: KartaTypography.monoBadge.copyWith(
                      color: palette.textPrimary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${RegionalCurrencyFormatter.formatDistance(snapshot.remainingDistanceMeters)} remaining',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KartaTypography.bodySecondary.copyWith(
                  color: palette.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _DrivingEndButton(
          key: const ValueKey<String>('mobile-nav-end'),
          onTap: () => ref.read(routePlannerProvider.notifier).endActiveNavigation(),
        ),
      ],
    );

    final halfActionHub = ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      children: <Widget>[
        // Lower-thumb ergonomic row of >=60x60dp Fitts's Law driving actions
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          children: <Widget>[
            _DrivingActionTarget(
              key: const ValueKey<String>('mobile-action-mute'),
              tooltip: voiceMuted ? 'Unmute Voice' : 'Mute Voice',
              icon: voiceMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              label: voiceMuted ? 'Muted' : 'Audio',
              color: voiceMuted ? palette.textSecondary : palette.textPrimary,
              onTap: () => ref.read(voiceMutedProvider.notifier).state = !voiceMuted,
            ),
            _DrivingActionTarget(
              key: const ValueKey<String>('mobile-action-voice'),
              tooltip: 'Voice Report',
              icon: Icons.mic_rounded,
              label: 'Voice',
              color: palette.accentBright,
              onTap: () => ref.read(handsFreeVoiceProvider.notifier).startListening(),
            ),
            _DrivingActionTarget(
              key: const ValueKey<String>('mobile-action-fuel'),
              tooltip: 'Fuel Stops',
              icon: Icons.local_gas_station_rounded,
              label: 'Fuel',
              color: palette.statusClear,
              onTap: () =>
                  ref.read(realtimeCrowdsourcingProvider.notifier).toggleFuelOverlay(),
            ),
            _DrivingActionTarget(
              key: const ValueKey<String>('mobile-action-hazard'),
              tooltip: 'Report Hazard',
              icon: Icons.add_alert_rounded,
              label: 'Hazard',
              color: palette.statusCaution,
              onTap: () => ref.read(realtimeCrowdsourcingProvider.notifier).toggleRadialMenu(),
            ),
            _DrivingActionTarget(
              key: const ValueKey<String>('mobile-action-lookaround'),
              tooltip: 'Street Look-Around',
              icon: Icons.streetview_rounded,
              label: '3D View',
              color: palette.accentBright,
              onTap: () {
                final coord = snapshot.currentFix?.coordinate ??
                    ref.read(kartaMapControllerProvider).center;
                ref.read(lookAroundTargetProvider.notifier).state = StreetLookAroundTarget(
                  coordinate: coord,
                  headingDeg: snapshot.currentFix?.bearingDeg ?? 0,
                  title: snapshot.roadContext?.roadName ?? 'Current Route Position',
                  subtitle: '${snapshot.activeCountry.name} · Street-Level Preview',
                );
              },
            ),
          ],
        ),
        if (playback != null) ...<Widget>[
          const SizedBox(height: 12),
          _PlaybackSimulationStrip(playback: playback),
        ],
      ],
    );

    final expandedTurnList = _TurnByTurnItineraryList(snapshot: snapshot);

    return KartaSpringBottomSheet(
      key: const ValueKey<String>('mobile-nav-spring-sheet'),
      collapsedHeight: 104.0,
      halfFraction: 0.44,
      expandedFraction: 0.62,
      onDetentChanged: (detent) {
        ref.read(mobileNavSheetExpandedProvider.notifier).state =
            detent != KartaSheetDetent.collapsed;
      },
      collapsedChild: collapsedEtaPill,
      halfChild: halfActionHub,
      expandedChild: expandedTurnList,
    );
  }
}

class _TurnByTurnItineraryList extends StatelessWidget {
  const _TurnByTurnItineraryList({required this.snapshot});

  final NavigationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final route = snapshot.activeRoute;
    if (route == null || route.legs.isEmpty) {
      return Center(
        child: Text(
          'No turn maneuvers available for this route.',
          style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
        ),
      );
    }

    final rows = <({int legIndex, RouteManeuver maneuver, bool isCurrent})>[];
    for (var l = 0; l < route.legs.length; l++) {
      for (final m in route.legs[l].maneuvers) {
        final isCurrent = snapshot.currentManeuver != null &&
            m.instruction == snapshot.currentManeuver!.instruction &&
            m.beginShapeIndex == snapshot.currentManeuver!.beginShapeIndex;
        rows.add((legIndex: l, maneuver: m, isCurrent: isCurrent));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'TURN-BY-TURN STEPS (${rows.length})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${route.distanceKm.toStringAsFixed(1)} km',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KartaTypography.monoBadge.copyWith(
                  fontSize: 11,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, idx) {
              final row = rows[idx];
              final man = row.maneuver;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: row.isCurrent ? palette.accentGlow : palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: row.isCurrent ? palette.accentPrimary : palette.borderSubtle,
                    width: row.isCurrent ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: row.isCurrent ? palette.accentPrimary : palette.surfaceCard,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: KartaManeuverIcon(
                        valhallaType: man.type,
                        size: 22,
                        color: row.isCurrent
                            ? Theme.of(context).colorScheme.onPrimary
                            : palette.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            man.instruction,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: KartaTypography.bodyPrimary.copyWith(
                              fontSize: 13.5,
                              color: palette.textPrimary,
                              fontWeight: row.isCurrent ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            <String>[
                              RegionalCurrencyFormatter.formatDistance(man.distanceKm * 1000.0),
                              if (man.streetNames.isNotEmpty) man.streetNames.first,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KartaTypography.bodySecondary.copyWith(
                              fontSize: 11.5,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlaybackSimulationStrip extends ConsumerWidget {
  const _PlaybackSimulationStrip({required this.playback});

  final RoutePlaybackPositionSource playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final lightingNotifier = ref.read(kartaLightingProvider.notifier);
    final lightingState = ref.watch(kartaLightingProvider);
    final isTunnelSim = lightingNotifier.simulatedTunnelActive || lightingState.isInTunnel;

    return KartaSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      borderRadius: 12,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                playback.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 18,
                color: palette.accentBright,
              ),
              onPressed: () => playback.setPaused(!playback.isPaused),
            ),
            _SimChip(
              label: '${playback.speedMultiplier.round()}x',
              active: true,
              onTap: () {
                final next = playback.speedMultiplier < 10
                    ? 16.0
                    : (playback.speedMultiplier < 30 ? 40.0 : 4.0);
                playback.setSpeedMultiplier(next);
              },
            ),
            const SizedBox(width: 6),
            _SimChip(
              label: '30 km/h',
              active: playback.baseCruiseKmh <= 45,
              onTap: () => playback.setBaseCruiseKmh(30.0),
            ),
            const SizedBox(width: 4),
            _SimChip(
              label: '80 km/h',
              active: playback.baseCruiseKmh > 45 && playback.baseCruiseKmh < 100,
              onTap: () => playback.setBaseCruiseKmh(80.0),
            ),
            const SizedBox(width: 4),
            _SimChip(
              label: '110 km/h',
              active: playback.baseCruiseKmh >= 100,
              onTap: () => playback.setBaseCruiseKmh(110.0),
            ),
            const SizedBox(width: 6),
            _SimChip(
              label: isTunnelSim ? 'Tunnel ON' : 'Tunnel',
              active: isTunnelSim,
              alertColor: palette.statusCaution,
              onTap: lightingNotifier.toggleSimulatedTunnel,
            ),
            const SizedBox(width: 6),
            _SimChip(
              label: playback.overspeedDemoActive ? 'Overspeed ON' : 'Overspeed',
              active: playback.overspeedDemoActive,
              alertColor: palette.statusAlert,
              onTap: () => playback.setOverspeedBoost(
                playback.overspeedDemoActive ? 0.0 : 32.0,
              ),
            ),
            const SizedBox(width: 8),
            _SimChip(label: 'Penang', onTap: () => playback.seekProgress(0.03)),
            const SizedBox(width: 4),
            _SimChip(label: 'KLCC', onTap: () => playback.seekProgress(0.49)),
            const SizedBox(width: 4),
            _SimChip(label: 'SG Border', onTap: () => playback.seekProgress(0.95)),
            const SizedBox(width: 4),
            _SimChip(label: 'Marina Bay', onTap: () => playback.seekProgress(0.985)),
          ],
        ),
      ),
    );
  }
}

/// Fitts's Law ergonomic driving button strictly enforcing >= 60x60dp touch targets.
class _DrivingActionTarget extends StatelessWidget {
  const _DrivingActionTarget({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Tooltip(
      message: tooltip,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: KartaSpacing.minDrivingTouchTarget,
          minHeight: KartaSpacing.minDrivingTouchTarget,
        ),
        child: Material(
          color: palette.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: palette.borderSubtle),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 22, color: color),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: KartaTypography.monoBadge.copyWith(
                      fontSize: 11,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// High-contrast 60x60dp Fitts's Law End Navigation button.
class _DrivingEndButton extends StatelessWidget {
  const _DrivingEndButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: KartaSpacing.minDrivingTouchTarget,
        minHeight: KartaSpacing.minDrivingTouchTarget,
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: palette.statusAlert,
          foregroundColor: palette.isDaylight ? Colors.white : palette.backgroundPrimary,
          minimumSize: const Size(
            KartaSpacing.minDrivingTouchTarget,
            KartaSpacing.minDrivingTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onTap,
        child: Text(
          'End',
          style: KartaTypography.bodyPrimary.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.isDaylight ? Colors.white : palette.backgroundPrimary,
          ),
        ),
      ),
    );
  }
}

class _SimChip extends StatelessWidget {
  const _SimChip({
    required this.label,
    required this.onTap,
    this.active = false,
    this.alertColor,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? alertColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final c = alertColor ?? palette.accentPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active ? c.withValues(alpha: 0.22) : palette.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? c : palette.borderSubtle),
        ),
        child: Text(
          label,
          style: KartaTypography.monoBadge.copyWith(
            fontSize: 11,
            color: active ? palette.textPrimary : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}
