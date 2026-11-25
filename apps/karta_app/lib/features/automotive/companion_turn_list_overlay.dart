import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_automotive_bridge/karta_automotive_bridge.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import '../../state/karta_app_state.dart';
import '../../state/phase3_providers.dart';
import '../../state/phase4_automotive_providers.dart';

/// Flagship Phone-to-Car "Turn List & Destination Companion" viewport presented
/// smoothly above the throttled phone map when projected to Apple CarPlay or
/// Android Auto during active navigation.
///
/// Design & Engineering Guarantees:
/// - Never unmounts `KartaMapView` or `NavigationSessionController`.
/// - Mirrors vehicle headlight/dimmer lighting (`Obsidian Night` & `Tropical Daylight`).
/// - Provides 1-tap switching to `Show Live Map` and mirrors the head unit's 3 primary
///   driver/passenger controls (`Voice Report`, `Guidance Audio`, `Route Overview`).
class KartaCompanionTurnListOverlay extends ConsumerWidget {
  const KartaCompanionTurnListOverlay({
    super.key,
    required this.snapshot,
    required this.connection,
    required this.thermal,
    required this.lighting,
    required this.onShowLiveMap,
  });

  final NavigationSnapshot snapshot;
  final AutomotiveConnectionState connection;
  final ThermalRenderProfile? thermal;
  final KartaLightingState lighting;
  final VoidCallback onShowLiveMap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final planner = ref.watch(routePlannerProvider);
    final voiceMuted = ref.watch(voiceMutedProvider);
    final overviewActive = ref.watch(automotiveRouteOverviewProvider);
    final bridge = ref.read(kartaAutomotiveBridgeProvider);

    final route = snapshot.activeRoute;
    final destination = planner.destination;
    final upcomingSteps = _collectUpcomingSteps(snapshot);
    final eta = snapshot.estimatedArrival;
    final etaFormatted =
        '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';

    return Material(
      color: palette.backgroundPrimary.withValues(alpha: 0.96),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // 1. Projected Vehicle Header Card
                  _CompanionHeaderCard(
                    connection: connection,
                    thermal: thermal,
                    lighting: lighting,
                    onShowLiveMap: onShowLiveMap,
                  ),
                  const SizedBox(height: 10),

                  // 2. Destination Telemetry Card + 3 Quick Head-Unit Controls
                  KartaSurfaceCard(
                    padding: const EdgeInsets.all(14),
                    borderRadius: 16,
                    highlighted: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: palette.accentGlow,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: palette.accentPrimary.withValues(alpha: 0.6),
                                ),
                              ),
                              child: Icon(
                                Icons.flag_rounded,
                                color: palette.accentBright,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'DESTINATION · ${snapshot.activeCountry.isoA2}',
                                    style: KartaTypography.monoBadge.copyWith(
                                      fontSize: 11,
                                      letterSpacing: 0.8,
                                      color: palette.accentBright,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    destination.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: KartaTypography.sectionTitle.copyWith(
                                      fontSize: 16,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                  if (route?.primaryCorridorName != null) ...<Widget>[
                                    const SizedBox(height: 2),
                                    Text(
                                      route!.primaryCorridorName!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: KartaTypography.bodySecondary.copyWith(
                                        fontSize: 12,
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                Text(
                                  etaFormatted,
                                  style: KartaTypography.telemetryValue.copyWith(
                                    fontSize: 22,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                Text(
                                  '${RegionalCurrencyFormatter.formatDuration(snapshot.remainingDurationSeconds)} · ${RegionalCurrencyFormatter.formatDistance(snapshot.remainingDistanceMeters)}',
                                  style: KartaTypography.monoBadge.copyWith(
                                    fontSize: 11,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: <Widget>[
                            _TelemetryPill(
                              icon: Icons.speed_rounded,
                              label:
                                  '${snapshot.speedTelemetry.currentSpeedKmh.round()} km/h${snapshot.speedTelemetry.speedLimitKmh != null ? ' / ${snapshot.speedTelemetry.speedLimitKmh}' : ''}',
                              accent: switch (snapshot.speedTelemetry.severity) {
                                SpeedAlertSeverity.alert => palette.statusAlert,
                                SpeedAlertSeverity.caution => palette.statusCaution,
                                SpeedAlertSeverity.normal => palette.accentBright,
                              },
                            ),
                            _TelemetryPill(
                              icon: Icons.shield_outlined,
                              label: 'ZERO-RETENTION GPS',
                              accent: palette.accentPrimary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Mirror of head-unit 3 primary actions
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _CompanionActionButton(
                                key: const ValueKey<String>('companion-voice-report'),
                                icon: Icons.mic_rounded,
                                label: 'Voice Report',
                                highlighted: true,
                                onTap: () =>
                                    ref.read(handsFreeVoiceProvider.notifier).startListening(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompanionActionButton(
                                key: const ValueKey<String>('companion-mute-toggle'),
                                icon: voiceMuted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                label: voiceMuted ? 'Unmute' : 'Mute',
                                highlighted: voiceMuted,
                                onTap: () =>
                                    ref.read(voiceMutedProvider.notifier).state = !voiceMuted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompanionActionButton(
                                key: const ValueKey<String>('companion-overview-toggle'),
                                icon: Icons.alt_route_rounded,
                                label: overviewActive ? 'Resume' : 'Overview',
                                highlighted: overviewActive,
                                onTap: () {
                                  final next = !overviewActive;
                                  ref.read(automotiveRouteOverviewProvider.notifier).state =
                                      next;
                                  bridge.setRouteOverviewActive(next);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 3. Scrollable Upcoming Turn-by-Turn Maneuver List
                  Expanded(
                    child: KartaSurfaceCard(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      borderRadius: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'TURN-BY-TURN COMPANION',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: KartaTypography.monoBadge.copyWith(
                                    fontSize: 10.5,
                                    letterSpacing: 0.9,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${upcomingSteps.length} steps ahead',
                                style: KartaTypography.monoBadge.copyWith(
                                  fontSize: 10,
                                  color: palette.accentBright,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: upcomingSteps.isEmpty
                                ? Center(
                                    child: Text(
                                      'Following active corridor on ${connection.platform.label}',
                                      style: KartaTypography.bodySecondary.copyWith(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: upcomingSteps.length,
                                    separatorBuilder: (_, __) => Divider(
                                      height: 1,
                                      color: palette.borderSubtle,
                                    ),
                                    itemBuilder: (context, idx) {
                                      final item = upcomingSteps[idx];
                                      return _CompanionTurnRow(
                                        step: item,
                                        liveDistanceMeters: idx == 0
                                            ? snapshot.distanceToManeuverMeters
                                            : null,
                                        laneGuidance: idx == 0 ? snapshot.laneGuidance : null,
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
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

  List<_UpcomingCompanionStep> _collectUpcomingSteps(NavigationSnapshot snap) {
    final route = snap.activeRoute;
    if (route == null || route.legs.isEmpty) {
      if (snap.currentManeuver != null) {
        return <_UpcomingCompanionStep>[
          _UpcomingCompanionStep(
            legIndex: snap.currentLegIndex,
            maneuverIndex: snap.currentManeuverIndex,
            maneuver: snap.currentManeuver!,
            isActive: true,
          ),
        ];
      }
      return const <_UpcomingCompanionStep>[];
    }

    final result = <_UpcomingCompanionStep>[];
    for (int legIdx = 0; legIdx < route.legs.length; legIdx++) {
      if (legIdx < snap.currentLegIndex) continue;
      final leg = route.legs[legIdx];
      final startIdx = legIdx == snap.currentLegIndex
          ? snap.currentManeuverIndex.clamp(0, leg.maneuvers.length)
          : 0;
      for (int mIdx = startIdx; mIdx < leg.maneuvers.length; mIdx++) {
        result.add(
          _UpcomingCompanionStep(
            legIndex: legIdx,
            maneuverIndex: mIdx,
            maneuver: leg.maneuvers[mIdx],
            isActive: legIdx == snap.currentLegIndex && mIdx == snap.currentManeuverIndex,
          ),
        );
      }
    }
    return result;
  }
}

class _CompanionHeaderCard extends StatelessWidget {
  const _CompanionHeaderCard({
    required this.connection,
    required this.thermal,
    required this.lighting,
    required this.onShowLiveMap,
  });

  final AutomotiveConnectionState connection;
  final ThermalRenderProfile? thermal;
  final KartaLightingState lighting;
  final VoidCallback onShowLiveMap;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final viewportBadge = switch (connection.headUnitInfo?.viewportClass) {
      AutomotiveViewportClass.ultraWide => 'ULTRA-WIDE',
      AutomotiveViewportClass.wide => 'WIDE',
      _ => 'DISPLAY',
    };

    return KartaSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: 16,
      deepGlass: true,
      borderColor: palette.accentPrimary.withValues(alpha: 0.72),
      child: Row(
        children: <Widget>[
          Icon(
            connection.platform == AutomotivePlatform.carPlay
                ? Icons.directions_car_filled_rounded
                : Icons.connected_tv_rounded,
            color: palette.accentBright,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${connection.platform.label} · $viewportBadge',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KartaTypography.sectionTitle.copyWith(
                    fontSize: 13.5,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${lighting.statusChipLabel} · Head Unit ${thermal?.headUnitTargetFps ?? 60} fps',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KartaTypography.monoBadge.copyWith(
                    fontSize: 10,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            key: const ValueKey<String>('companion-show-live-map'),
            onTap: onShowLiveMap,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: KartaSpacing.minTouchTarget,
                minHeight: KartaSpacing.minTouchTarget,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.accentPrimary.withValues(alpha: 0.7)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.map_rounded, size: 16, color: palette.accentBright),
                    const SizedBox(width: 6),
                    Text(
                      'Show Map',
                      style: KartaTypography.captionLabel.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanionActionButton extends StatelessWidget {
  const _CompanionActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: KartaSpacing.minTouchTarget),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: highlighted ? palette.accentGlow : palette.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted ? palette.accentPrimary : palette.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 18,
                color: highlighted ? palette.accentBright : palette.textPrimary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KartaTypography.captionLabel.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TelemetryPill extends StatelessWidget {
  const _TelemetryPill({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: KartaTypography.monoBadge.copyWith(
              fontSize: 10,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingCompanionStep {
  const _UpcomingCompanionStep({
    required this.legIndex,
    required this.maneuverIndex,
    required this.maneuver,
    required this.isActive,
  });

  final int legIndex;
  final int maneuverIndex;
  final RouteManeuver maneuver;
  final bool isActive;
}

class _CompanionTurnRow extends StatelessWidget {
  const _CompanionTurnRow({
    required this.step,
    this.liveDistanceMeters,
    this.laneGuidance,
  });

  final _UpcomingCompanionStep step;
  final double? liveDistanceMeters;
  final LaneGuidanceBannerState? laneGuidance;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final m = step.maneuver;
    final distText = RegionalCurrencyFormatter.formatDistance(
      liveDistanceMeters ?? (m.distanceKm * 1000.0),
    );
    final roadLabel = m.streetNames.isNotEmpty ? m.streetNames.join(' · ') : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: step.isActive ? palette.accentGlow : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: step.isActive
            ? Border.all(color: palette.accentPrimary.withValues(alpha: 0.72))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: step.isActive ? palette.accentPrimary : palette.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: KartaManeuverIcon(
              valhallaType: m.type,
              size: 22,
              color: step.isActive
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
                  distText,
                  style: KartaTypography.monoBadge.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: step.isActive ? palette.accentBright : palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  m.instruction,
                  style: KartaTypography.bodyPrimary.copyWith(
                    fontSize: step.isActive ? 14 : 13,
                    fontWeight: step.isActive ? FontWeight.w700 : FontWeight.w500,
                    color: palette.textPrimary,
                  ),
                ),
                if (roadLabel != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    roadLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KartaTypography.bodySecondary.copyWith(
                      fontSize: 11.5,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
                if (step.isActive &&
                    laneGuidance != null &&
                    laneGuidance!.roadLanes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: <Widget>[
                      for (final lane in laneGuidance!.roadLanes.take(5))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: lane.isRecommended
                                ? palette.accentPrimary.withValues(alpha: 0.26)
                                : palette.surfaceElevated,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: lane.isRecommended
                                  ? palette.accentBright
                                  : palette.borderSubtle,
                            ),
                          ),
                          child: Text(
                            _laneGlyphText(lane.laneSpec),
                            style: KartaTypography.monoBadge.copyWith(
                              fontSize: 10.5,
                              color: lane.isRecommended
                                  ? palette.textPrimary
                                  : palette.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _laneGlyphText(String spec) {
    final s = spec.toLowerCase();
    final parts = <String>[];
    if (s.contains('left')) parts.add('↰');
    if (s.contains('through') || parts.isEmpty) parts.add('↑');
    if (s.contains('right')) parts.add('↱');
    return parts.join('');
  }
}
