import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_automotive_bridge/karta_automotive_bridge.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import '../../state/phase4_automotive_providers.dart';

/// Driver Studio panel for inspecting & managing:
/// 1. Apple CarPlay & Android Auto Phone <-> Vehicle handoff link
/// 2. Strict On-Device Location Privacy (zero raw GPS history retention without opt-in)
/// 3. Adaptive Frame-Rate & Thermal Throttling Governor
class AutomotivePrivacyThermalPanel extends ConsumerWidget {
  const AutomotivePrivacyThermalPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final conn = ref.watch(automotiveConnectionProvider).valueOrNull ??
        const AutomotiveConnectionState();
    final audit = ref.watch(privacyAuditProvider).valueOrNull ??
        ref.read(locationPrivacyGuardProvider).auditSnapshot;
    final thermal = ref.watch(thermalRenderProfileProvider).valueOrNull ??
        ref.read(thermalAdaptationControllerProvider).currentProfile;
    final bridge = ref.read(kartaAutomotiveBridgeProvider);
    final privacyGuard = ref.read(locationPrivacyGuardProvider);
    final thermalCtrl = ref.read(thermalAdaptationControllerProvider);

    final thermalColor = switch (thermal.effectiveTier) {
      DeviceThermalLevel.nominal => palette.statusClear,
      DeviceThermalLevel.fair => palette.statusCaution,
      DeviceThermalLevel.serious =>
        palette.isDaylight ? const Color(0xFFC2410C) : const Color(0xFFF97316),
      DeviceThermalLevel.critical => palette.statusAlert,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 1. Vehicle Head-Unit Projection & Handoff Status
          KartaSurfaceCard(
            padding: const EdgeInsets.all(12),
            borderRadius: 14,
            highlighted: conn.isConnected,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      conn.isConnected
                          ? Icons.connected_tv_rounded
                          : Icons.directions_car_outlined,
                      size: 18,
                      color: conn.isConnected ? palette.accentBright : palette.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        conn.isConnected
                            ? '${conn.platform.label} Projected'
                            : 'Vehicle Link · Phone Standalone',
                        style: KartaTypography.sectionTitle.copyWith(
                          fontSize: 13.5,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: (conn.isConnected ? palette.statusClear : palette.borderSubtle)
                            .withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        conn.phase.name.toUpperCase(),
                        style: KartaTypography.monoBadge.copyWith(
                          fontSize: 11,
                          color: conn.isConnected ? palette.statusClear : palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Seamless state handoff synced via Pigeon/MethodChannel · Seq #${conn.lastSequenceId} · Handoffs: ${conn.handoffCount}',
                  style: KartaTypography.bodySecondary.copyWith(
                    fontSize: 11.5,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () {
                        if (conn.platform == AutomotivePlatform.carPlay) {
                          bridge.handleHeadUnitDisconnected(
                            platform: AutomotivePlatform.carPlay,
                            reason: 'user_disconnect',
                          );
                        } else {
                          bridge.handleHeadUnitConnected(
                            const AutomotiveHeadUnitInfo(
                              platform: AutomotivePlatform.carPlay,
                              screenWidthPx: 1280,
                              screenHeightPx: 720,
                              densityScale: 2.0,
                              apiLevel: 18,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.apple, size: 16),
                      label: Text(
                        conn.platform == AutomotivePlatform.carPlay
                            ? 'Disconnect CarPlay'
                            : 'Link CarPlay',
                        style: KartaTypography.captionLabel.copyWith(color: palette.textPrimary),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        if (conn.platform == AutomotivePlatform.androidAuto) {
                          bridge.handleHeadUnitDisconnected(
                            platform: AutomotivePlatform.androidAuto,
                            reason: 'user_disconnect',
                          );
                        } else {
                          bridge.handleHeadUnitConnected(
                            const AutomotiveHeadUnitInfo(
                              platform: AutomotivePlatform.androidAuto,
                              screenWidthPx: 1280,
                              screenHeightPx: 720,
                              densityScale: 2.0,
                              apiLevel: 7,
                              supportsInstrumentCluster: true,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.android_rounded, size: 16),
                      label: Text(
                        conn.platform == AutomotivePlatform.androidAuto
                            ? 'Disconnect AA'
                            : 'Link Android Auto',
                        style: KartaTypography.captionLabel.copyWith(color: palette.textPrimary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 2. Strict On-Device Location Privacy Guard
          KartaSurfaceCard(
            padding: const EdgeInsets.all(12),
            borderRadius: 14,
            borderColor: palette.accentPrimary.withValues(alpha: 0.6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.shield_rounded, size: 18, color: palette.accentBright),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'On-Device Location Privacy',
                        style: KartaTypography.sectionTitle.copyWith(
                          fontSize: 13.5,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: palette.accentGlow,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        audit.policy.retainTripHistoryOptIn ? 'OPT-IN RAM' : 'ZERO RETENTION',
                        style: KartaTypography.monoBadge.copyWith(
                          fontSize: 11,
                          color: palette.accentBright,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Raw GPS fixes retained: ${audit.retainedHistoryCount} · '
                  'Memory scrubs: ${audit.scrubCount} · '
                  'MapLibre telemetry: OFF',
                  style: KartaTypography.bodySecondary.copyWith(
                    fontSize: 11.5,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Opt in to local trip breadcrumb buffer',
                    style: KartaTypography.bodyPrimary.copyWith(
                      fontSize: 12.5,
                      color: palette.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Off by default — zero raw GPS history stored on device or synced.',
                    style: KartaTypography.bodySecondary.copyWith(
                      fontSize: 11.5,
                      color: palette.textSecondary,
                    ),
                  ),
                  value: audit.policy.retainTripHistoryOptIn,
                  activeThumbColor: palette.accentBright,
                  onChanged: privacyGuard.setTripHistoryOptIn,
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Ephemeral ID: ${audit.ephemeralSessionToken}',
                        overflow: TextOverflow.ellipsis,
                        style: KartaTypography.monoBadge.copyWith(
                          fontSize: 11,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        privacyGuard.scrubEphemeralState(purgeOptInHistory: true);
                        bridge.scrubHeadUnitLocationState();
                      },
                      icon: const Icon(Icons.cleaning_services_rounded, size: 15),
                      label: Text(
                        'Scrub Now',
                        style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 3. Adaptive Thermal & Frame-Rate Governor
          KartaSurfaceCard(
            padding: const EdgeInsets.all(12),
            borderRadius: 14,
            borderColor: thermalColor.withValues(alpha: 0.65),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.thermostat_rounded, size: 18, color: thermalColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Thermal & Adaptive FPS Governor',
                        style: KartaTypography.sectionTitle.copyWith(
                          fontSize: 13.5,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: thermalColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        thermal.effectiveTier.label.toUpperCase(),
                        style: KartaTypography.monoBadge.copyWith(
                          fontSize: 11,
                          color: thermalColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    _MetricChip(label: 'Car FPS', value: '${thermal.headUnitTargetFps}'),
                    _MetricChip(
                      label: 'Phone FPS',
                      value: thermal.pausePhoneMapCanvas ? 'PAUSED' : '${thermal.phoneTargetFps}',
                    ),
                    _MetricChip(
                      label: '3D Bldgs',
                      value: thermal.enableHeadUnit3DBuildings ? 'ON' : 'SHED',
                    ),
                    _MetricChip(
                      label: 'Poll',
                      value: '${(thermal.roadContextPollIntervalMs / 1000).toStringAsFixed(0)}s',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  thermal.reason,
                  style: KartaTypography.bodySecondary.copyWith(
                    fontSize: 11.5,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final lvl in DeviceThermalLevel.values)
                      ChoiceChip(
                        label: Text(
                          lvl.wireValue.toUpperCase(),
                          style: KartaTypography.monoBadge.copyWith(
                            fontSize: 11,
                            color: thermal.effectiveTier == lvl
                                ? palette.textPrimary
                                : palette.textSecondary,
                          ),
                        ),
                        selected: thermal.effectiveTier == lvl,
                        onSelected: (_) {
                          thermalCtrl.updateTelemetry(
                            ThermalTelemetryInput(
                              deviceThermalLevel: lvl,
                              isProjectedToHeadUnit: conn.isConnected,
                              headUnitPlatform: conn.platform.wireValue,
                              timestamp: DateTime.now().add(const Duration(seconds: 30)),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$label ',
            style: KartaTypography.captionLabel.copyWith(
              fontSize: 11,
              color: palette.textSecondary,
            ),
          ),
          Text(
            value,
            style: KartaTypography.monoBadge.copyWith(
              fontSize: 11,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
