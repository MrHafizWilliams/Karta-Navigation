import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_design_system/karta_design_system.dart';

import '../../state/karta_app_state.dart';
import '../../state/phase3_providers.dart';

/// Non-blocking translucent corner overlay hosting:
/// 1. Compact Spatial Hazard Pill with a 12-second radial countdown ring and
///    large >=48dp "Still There / Not There" thumb buttons.
/// 2. Compact live Valhalla reroute proposal & urgent Time-to-Leave chips.
/// 3. Subtle confirmation toast chip.
///
/// Anchored in [KartaAdaptiveScaffold.cornerHazardOverlay] so it NEVER covers
/// [TopManeuverHudBanner] or the central 3D road horizon.
class SpatialHazardCornerPill extends ConsumerWidget {
  const SpatialHazardCornerPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final realtime = ref.watch(realtimeCrowdsourcingProvider);
    final hazard = realtime.highlightedHazard;
    final reroute = realtime.activeRerouteProposal;
    final ttl = realtime.urgentTimeToLeaveBanner;
    final toast = realtime.lastToastMessage;

    if (hazard == null && reroute == null && ttl == null && toast == null) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (reroute != null) ...<Widget>[
          _CompactRerouteCornerCard(proposal: reroute),
          const SizedBox(height: 8),
        ],
        if (ttl != null) ...<Widget>[
          _CompactTimeToLeaveCornerChip(payload: ttl),
          const SizedBox(height: 8),
        ],
        _AnimatedSpatialHazardCard(hazard: hazard),
        if (toast != null) ...<Widget>[
          const SizedBox(height: 6),
          _SubtleCornerToastPill(message: toast),
        ],
      ],
    );
  }
}

class _AnimatedSpatialHazardCard extends ConsumerStatefulWidget {
  const _AnimatedSpatialHazardCard({required this.hazard});

  final HazardRecord? hazard;

  @override
  ConsumerState<_AnimatedSpatialHazardCard> createState() => _AnimatedSpatialHazardCardState();
}

class _AnimatedSpatialHazardCardState extends ConsumerState<_AnimatedSpatialHazardCard>
    with TickerProviderStateMixin {
  static const Duration _countdownDuration = Duration(seconds: 12);

  late final AnimationController _enterCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _scaleAnim;
  late final AnimationController _countdownCtrl;

  String? _activeHazardId;
  bool _isPausedByTouch = false;
  HazardRecord? _ackSnapshot;
  String? _ackMessage;
  bool _ackConfirmed = true;
  Timer? _ackTimer;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _fadeAnim = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic);
    _slideAnim = Tween<Offset>(
      begin: const Offset(-0.22, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutBack));
    _scaleAnim = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutBack),
    );

    _countdownCtrl = AnimationController(vsync: this, duration: _countdownDuration)
      ..addStatusListener(_onCountdownStatus);

    if (widget.hazard != null) {
      _bindHazard(widget.hazard!);
    }
  }

  void _onCountdownStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _activeHazardId != null && _ackMessage == null) {
      final expiredId = _activeHazardId!;
      ref.read(realtimeCrowdsourcingProvider.notifier).dismissHazardCard(expiredId);
    }
  }

  void _bindHazard(HazardRecord hazard) {
    _ackTimer?.cancel();
    _ackSnapshot = null;
    _ackMessage = null;
    _activeHazardId = hazard.id;
    _isPausedByTouch = false;
    _enterCtrl.forward(from: 0.0);
    _countdownCtrl.forward(from: 0.0);
  }

  @override
  void didUpdateWidget(covariant _AnimatedSpatialHazardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.hazard;
    if (next == null) {
      if (_ackMessage == null) {
        _activeHazardId = null;
        _countdownCtrl.stop();
        _enterCtrl.reverse();
      }
      return;
    }
    if (next.id != _activeHazardId && _ackMessage == null) {
      _bindHazard(next);
    }
  }

  @override
  void dispose() {
    _ackTimer?.cancel();
    _countdownCtrl.removeStatusListener(_onCountdownStatus);
    _countdownCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  void _pauseCountdown() {
    if (!_isPausedByTouch && _countdownCtrl.isAnimating) {
      setState(() => _isPausedByTouch = true);
      _countdownCtrl.stop(canceled: false);
    }
  }

  void _resumeCountdown() {
    if (_isPausedByTouch && _ackMessage == null && _activeHazardId != null) {
      setState(() => _isPausedByTouch = false);
      if (_countdownCtrl.value < 1.0) {
        _countdownCtrl.forward();
      }
    }
  }

  void _handleVote(HazardRecord hazard, String vote) {
    final isConfirm = vote == 'confirm';
    if (isConfirm) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    _countdownCtrl.stop();
    setState(() {
      _ackSnapshot = hazard;
      _ackConfirmed = isConfirm;
      _ackMessage = isConfirm ? 'Confirmed · +1' : 'Marked Cleared';
    });

    ref.read(realtimeCrowdsourcingProvider.notifier).voteHazard(hazard.id, vote);

    _ackTimer?.cancel();
    _ackTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      final votedId = hazard.id;
      setState(() {
        _ackSnapshot = null;
        _ackMessage = null;
        _activeHazardId = null;
      });
      ref.read(realtimeCrowdsourcingProvider.notifier).dismissHazardCard(votedId);
    });
  }

  void _handleDismiss(HazardRecord hazard) {
    HapticFeedback.selectionClick();
    _countdownCtrl.stop();
    _ackTimer?.cancel();
    setState(() {
      _ackSnapshot = null;
      _ackMessage = null;
      _activeHazardId = null;
    });
    ref.read(realtimeCrowdsourcingProvider.notifier).dismissHazardCard(hazard.id);
  }

  @override
  Widget build(BuildContext context) {
    final displayHazard = _ackSnapshot ?? widget.hazard;
    if (displayHazard == null) return const SizedBox.shrink();

    final palette = context.kartaPalette;
    final accent = _hazardColorForPalette(displayHazard.category, palette);
    final distText = displayHazard.distanceMeters != null
        ? (displayHazard.distanceMeters! >= 1000
            ? '${(displayHazard.distanceMeters! / 1000).toStringAsFixed(1)} km ahead'
            : '${displayHazard.distanceMeters!.round()} m ahead')
        : (displayHazard.roadRef ?? 'Ahead on route');

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Dismissible(
            key: ValueKey<String>('hazard-dismiss-${displayHazard.id}'),
            direction: DismissDirection.endToStart,
            dismissThresholds: const <DismissDirection, double>{
              DismissDirection.endToStart: 0.25,
            },
            onDismissed: (_) => _handleDismiss(displayHazard),
            child: MouseRegion(
              onEnter: (_) => _pauseCountdown(),
              onExit: (_) => _resumeCountdown(),
              child: Listener(
                onPointerDown: (_) => _pauseCountdown(),
                onPointerUp: (_) => _resumeCountdown(),
                onPointerCancel: (_) => _resumeCountdown(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      key: const ValueKey<String>('karta-spatial-hazard-pill'),
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: palette.hudGlass,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: accent.withValues(alpha: palette.isDaylight ? 0.72 : 0.65),
                          width: 1.25,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: palette.shadowColor,
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // Top row: countdown ring + hazard summary + compact close
                          Row(
                            children: <Widget>[
                              AnimatedBuilder(
                                animation: _countdownCtrl,
                                builder: (context, child) {
                                  final remaining = (1.0 - _countdownCtrl.value).clamp(0.0, 1.0);
                                  return SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: CustomPaint(
                                      painter: _RadialCountdownRingPainter(
                                        progress: _ackMessage != null ? 1.0 : remaining,
                                        color: _ackMessage != null
                                            ? (_ackConfirmed
                                                ? palette.statusClear
                                                : palette.textSecondary)
                                            : accent,
                                        trackColor: palette.borderSubtle.withValues(alpha: 0.65),
                                        strokeWidth: 3.2,
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: accent.withValues(alpha: 0.16),
                                          ),
                                          child: Icon(
                                            _iconForHazard(displayHazard.category),
                                            size: 18,
                                            color: accent,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Flexible(
                                          child: Text(
                                            displayHazard.category.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: KartaTypography.bodyPrimary.copyWith(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: palette.textPrimary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: accent.withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(
                                            '${displayHazard.confirmations}x',
                                            style: KartaTypography.monoBadge.copyWith(
                                              fontSize: 11,
                                              color: accent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      distText,
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
                              IconButton(
                                constraints: const BoxConstraints(
                                  minWidth: KartaSpacing.minTouchTarget,
                                  minHeight: KartaSpacing.minTouchTarget,
                                ),
                                tooltip: 'Dismiss alert',
                                onPressed: () => _handleDismiss(displayHazard),
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Bottom row: >=48dp thumb buttons or 650ms voted confirmation pulse
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _ackMessage != null
                                ? Container(
                                    key: const ValueKey<String>('hazard-vote-ack'),
                                    height: 48,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: (_ackConfirmed
                                              ? palette.statusClear
                                              : palette.surfaceInteractive)
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _ackConfirmed
                                            ? palette.statusClear
                                            : palette.borderStrong,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: <Widget>[
                                        Icon(
                                          _ackConfirmed
                                              ? Icons.check_circle_rounded
                                              : Icons.done_all_rounded,
                                          size: 18,
                                          color: _ackConfirmed
                                              ? palette.statusClear
                                              : palette.textPrimary,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _ackMessage!,
                                          style: KartaTypography.bodyPrimary.copyWith(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: _ackConfirmed
                                                ? palette.statusClear
                                                : palette.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Row(
                                    key: const ValueKey<String>('hazard-vote-buttons'),
                                    children: <Widget>[
                                      Expanded(
                                        child: _ThumbVoteButton(
                                          key: const ValueKey<String>('hazard-vote-still-there'),
                                          label: 'Still There',
                                          icon: Icons.thumb_up_alt_rounded,
                                          backgroundColor: palette.accentGlow,
                                          borderColor: palette.accentPrimary.withValues(alpha: 0.78),
                                          foregroundColor: palette.accentBright,
                                          onTap: () => _handleVote(displayHazard, 'confirm'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _ThumbVoteButton(
                                          key: const ValueKey<String>('hazard-vote-not-there'),
                                          label: 'Not There',
                                          icon: Icons.close_rounded,
                                          backgroundColor:
                                              palette.surfaceInteractive.withValues(alpha: 0.85),
                                          borderColor: palette.borderStrong,
                                          foregroundColor: palette.textPrimary,
                                          onTap: () => _handleVote(displayHazard, 'cleared'),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbVoteButton extends StatefulWidget {
  const _ThumbVoteButton({
    super.key,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  State<_ThumbVoteButton> createState() => _ThumbVoteButtonState();
}

class _ThumbVoteButtonState extends State<_ThumbVoteButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.borderColor, width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(widget.icon, size: 16, color: widget.foregroundColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KartaTypography.bodyPrimary.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: widget.foregroundColor,
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

class _CompactRerouteCornerCard extends ConsumerWidget {
  const _CompactRerouteCornerCard({required this.proposal});

  final RerouteProposal proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final minsSaved = (proposal.timeSavedSeconds / 60).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: palette.hudGlass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.statusClear.withValues(alpha: 0.78), width: 1.25),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: palette.shadowColor,
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.alt_route_rounded, size: 17, color: palette.statusClear),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Faster Route · Save $minsSaved min',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KartaTypography.bodyPrimary.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: palette.statusClear,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                proposal.reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: KartaTypography.bodySecondary.copyWith(
                  fontSize: 11.5,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, KartaSpacing.minTouchTarget),
                        backgroundColor: palette.statusClear,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                      onPressed: () =>
                          ref.read(realtimeCrowdsourcingProvider.notifier).acceptRerouteProposal(),
                      child: Text(
                        'Switch Route',
                        style: KartaTypography.bodySecondary.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(KartaSpacing.minTouchTarget, KartaSpacing.minTouchTarget),
                      foregroundColor: palette.textPrimary,
                      side: BorderSide(color: palette.borderStrong),
                    ),
                    onPressed: () =>
                        ref.read(realtimeCrowdsourcingProvider.notifier).dismissRerouteProposal(),
                    child: Text(
                      'Stay',
                      style: KartaTypography.bodySecondary.copyWith(color: palette.textPrimary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactTimeToLeaveCornerChip extends ConsumerWidget {
  const _CompactTimeToLeaveCornerChip({required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final title = (payload['title'] as String?) ?? 'Upcoming Event';
    final msg = (payload['advisory_message'] as String?) ?? 'Time to leave based on live traffic';

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: palette.hudGlass,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.statusCaution.withValues(alpha: 0.72)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.event_available_rounded, size: 17, color: palette.statusCaution),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KartaTypography.bodyPrimary.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      msg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KartaTypography.bodySecondary.copyWith(
                        fontSize: 10.5,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: palette.accentBright,
                ),
                onPressed: () {
                  ref.read(activeNavTabProvider.notifier).state = 'commute';
                  ref.read(realtimeCrowdsourcingProvider.notifier).dismissTtlBanner();
                },
                child: Text(
                  'Open',
                  style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(
                  minWidth: KartaSpacing.minTouchTarget,
                  minHeight: KartaSpacing.minTouchTarget,
                ),
                onPressed: () =>
                    ref.read(realtimeCrowdsourcingProvider.notifier).dismissTtlBanner(),
                icon: Icon(Icons.close_rounded, size: 18, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtleCornerToastPill extends StatelessWidget {
  const _SubtleCornerToastPill({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: palette.hudDeepGlass,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.accentPrimary.withValues(alpha: 0.65)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: palette.shadowColor, blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.bolt_rounded, size: 14, color: palette.accentBright),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: KartaTypography.bodySecondary.copyWith(
                fontSize: 11,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MINIMAL BOTTOM AUDIO WAVEFORM PILL (HANDS-FREE VOICE REPORTING)
// ============================================================================

/// Sleek, minimal bottom-docked audio waveform pill displaying real-time speech
/// bars, live EN/BM/Manglish/Singlish transcription with keyword highlights,
/// 3-second zero-touch countdown ring, and Web Audio confirmation chimes.
class BottomVoiceWaveformPill extends ConsumerStatefulWidget {
  const BottomVoiceWaveformPill({super.key});

  @override
  ConsumerState<BottomVoiceWaveformPill> createState() => _BottomVoiceWaveformPillState();
}

class _BottomVoiceWaveformPillState extends ConsumerState<BottomVoiceWaveformPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveCtrl;
  final TextEditingController _fallbackCtrl = TextEditingController();
  bool _showManualInput = false;
  DateTime? _lastBoostTick;

  static const Set<String> _highlightKeywords = <String>{
    'police',
    'polis',
    'roadblock',
    'sekatan',
    'speed',
    'camera',
    'accident',
    'crash',
    'kemalangan',
    'eksiden',
    'pothole',
    'lubang',
    'flood',
    'banjir',
    'debris',
    'tree',
    'pokok',
    'closure',
    'closed',
    'tutup',
    'stopped',
    'breakdown',
    'rosak',
    'opposite',
    'sebelah',
    'kiri',
    'kanan',
    'left',
    'right',
  };

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _fallbackCtrl.dispose();
    super.dispose();
  }

  void _syncWaveAnimation(bool isListening) {
    if (isListening && !_waveCtrl.isAnimating) {
      _waveCtrl.repeat();
    } else if (!isListening && _waveCtrl.isAnimating) {
      _waveCtrl.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(handsFreeVoiceProvider);
    final notifier = ref.read(handsFreeVoiceProvider.notifier);
    _syncWaveAnimation(voice.isListening);

    if (voice.lastTranscriptTickAt != null && voice.lastTranscriptTickAt != _lastBoostTick) {
      _lastBoostTick = voice.lastTranscriptTickAt;
    }

    if (!voice.isVisible) {
      _showManualInput = false;
      return const SizedBox.shrink();
    }

    final palette = context.kartaPalette;
    final hasPending = voice.pendingIntent != null;
    final Color borderColor;
    if (voice.isConfirmedFlash) {
      borderColor = palette.statusClear;
    } else if (voice.isCancelledFlash) {
      borderColor = palette.borderStrong;
    } else if (hasPending) {
      borderColor = palette.statusCaution;
    } else if (voice.isListening) {
      borderColor = palette.accentPrimary;
    } else {
      borderColor = palette.borderStrong;
    }

    final liveText = voice.interimTranscript.trim();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Column(
        key: ValueKey<String>(
          'voice-pill-${voice.isListening}-$hasPending-${voice.isConfirmedFlash}-${voice.isCancelledFlash}',
        ),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                key: const ValueKey<String>('karta-voice-waveform-pill'),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.hudDeepGlass,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: borderColor.withValues(alpha: 0.85), width: 1.5),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: borderColor.withValues(alpha: palette.isDaylight ? 0.16 : 0.28),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    // Left visual state indicator: live waveform / countdown ring / confirmation badge
                    _buildLeadingVisual(voice, palette, notifier),
                    const SizedBox(width: 12),

                    // Center live transcription & recognized regional intent badge
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (hasPending) ...<Widget>[
                            Row(
                              children: <Widget>[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: palette.statusCaution.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    voice.pendingIntent!.hazardCategory!.label.toUpperCase(),
                                    style: KartaTypography.monoBadge.copyWith(
                                      fontSize: 11,
                                      color: palette.statusCaution,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Sending in ${voice.countdownSeconds}s',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: KartaTypography.monoBadge.copyWith(
                                      fontSize: 11,
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            _buildHighlightedTranscript(
                              liveText.isNotEmpty
                                  ? '"$liveText"'
                                  : voice.pendingIntent!.confirmationSpeech,
                              palette,
                            ),
                          ] else if (voice.isConfirmedFlash) ...<Widget>[
                            Text(
                              voice.statusMessage ?? 'Report sent',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KartaTypography.bodyPrimary.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: palette.statusClear,
                              ),
                            ),
                          ] else if (voice.isCancelledFlash) ...<Widget>[
                            Text(
                              voice.statusMessage ?? 'Cancelled',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KartaTypography.bodySecondary.copyWith(
                                fontSize: 12.5,
                                color: palette.textSecondary,
                              ),
                            ),
                          ] else ...<Widget>[
                            if (liveText.isNotEmpty)
                              _buildHighlightedTranscript('"$liveText"', palette)
                            else
                              Text(
                                voice.isListening
                                    ? 'Speak hazard (EN · BM · Manglish · SG)'
                                    : (voice.statusMessage ?? 'Tap mic to report hands-free'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: KartaTypography.bodyPrimary.copyWith(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textPrimary,
                                ),
                              ),
                            const SizedBox(height: 1),
                            Text(
                              voice.isListening
                                  ? '${voice.localeTag} · Live voice capture'
                                  : 'Hands-Free Voice Report',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KartaTypography.monoBadge.copyWith(
                                fontSize: 11,
                                color: palette.accentBright,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Right action controls (>=48dp touch targets & theme onPrimary contrast)
                    if (hasPending) ...<Widget>[
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(56, KartaSpacing.minTouchTarget),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: palette.accentPrimary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        ),
                        onPressed: notifier.submitPendingNow,
                        child: Text(
                          'Send',
                          style: KartaTypography.captionLabel.copyWith(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(56, KartaSpacing.minTouchTarget),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          foregroundColor: palette.statusAlert,
                          side: BorderSide(color: palette.statusAlert.withValues(alpha: 0.7)),
                        ),
                        onPressed: notifier.cancelPendingReport,
                        child: Text(
                          'Cancel',
                          style: KartaTypography.captionLabel.copyWith(
                            fontSize: 12,
                            color: palette.statusAlert,
                          ),
                        ),
                      ),
                    ] else if (voice.isListening) ...<Widget>[
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: KartaSpacing.minTouchTarget,
                          minHeight: KartaSpacing.minTouchTarget,
                        ),
                        tooltip: 'Type voice phrase',
                        onPressed: () => setState(() => _showManualInput = !_showManualInput),
                        icon: Icon(
                          _showManualInput ? Icons.keyboard_hide_rounded : Icons.keyboard_rounded,
                          size: 20,
                          color: _showManualInput ? palette.accentBright : palette.textSecondary,
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: KartaSpacing.minTouchTarget,
                          minHeight: KartaSpacing.minTouchTarget,
                        ),
                        tooltip: 'Stop listening',
                        onPressed: notifier.clearBanner,
                        icon: Icon(Icons.close_rounded, size: 20, color: palette.textSecondary),
                      ),
                    ] else ...<Widget>[
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: KartaSpacing.minTouchTarget,
                          minHeight: KartaSpacing.minTouchTarget,
                        ),
                        tooltip: 'Dismiss',
                        onPressed: notifier.clearBanner,
                        icon: Icon(Icons.close_rounded, size: 20, color: palette.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Collapsible keyboard fallback chip (only shown if explicitly toggled)
          if (_showManualInput && voice.isListening) ...<Widget>[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: palette.hudDeepGlass,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.borderSubtle),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _fallbackCtrl,
                      style: KartaTypography.bodyPrimary.copyWith(
                        fontSize: 12.5,
                        color: palette.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'e.g. "Ada polis depan exit" or "Crash left lane"',
                        hintStyle: KartaTypography.bodySecondary.copyWith(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                      onSubmitted: (val) {
                        notifier.processTranscript(val);
                        _fallbackCtrl.clear();
                        setState(() => _showManualInput = false);
                      },
                    ),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(56, 48),
                      backgroundColor: palette.accentGlow,
                      foregroundColor: palette.accentBright,
                    ),
                    onPressed: () {
                      notifier.processTranscript(_fallbackCtrl.text);
                      _fallbackCtrl.clear();
                      setState(() => _showManualInput = false);
                    },
                    child: Text(
                      'Parse',
                      style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLeadingVisual(
    HandsFreeVoiceState voice,
    KartaPalette palette,
    HandsFreeVoiceNotifier notifier,
  ) {
    if (voice.isConfirmedFlash) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.statusClear.withValues(alpha: 0.2),
          border: Border.all(color: palette.statusClear, width: 1.5),
        ),
        child: Icon(Icons.check_rounded, size: 20, color: palette.statusClear),
      );
    }
    if (voice.isCancelledFlash) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.surfaceInteractive,
          border: Border.all(color: palette.borderStrong),
        ),
        child: Icon(Icons.close_rounded, size: 18, color: palette.textSecondary),
      );
    }
    if (voice.pendingIntent != null) {
      final frac = (voice.countdownSeconds / 3.0).clamp(0.0, 1.0);
      return GestureDetector(
        onTap: notifier.submitPendingNow,
        child: SizedBox(
          width: 38,
          height: 38,
          child: CustomPaint(
            painter: _RadialCountdownRingPainter(
              progress: frac,
              color: palette.statusCaution,
              trackColor: palette.borderSubtle,
              strokeWidth: 3.0,
            ),
            child: Center(
              child: Text(
                '${voice.countdownSeconds}',
                style: KartaTypography.monoBadge.copyWith(
                  fontSize: 12,
                  color: palette.statusCaution,
                ),
              ),
            ),
          ),
        ),
      );
    }
    // Real-time 9-bar animated equalizer waveform
    return SizedBox(
      key: const ValueKey<String>('karta-audio-waveform-bars'),
      width: 44,
      height: 26,
      child: AnimatedBuilder(
        animation: _waveCtrl,
        builder: (context, _) {
          final hasSpeechBoost = _lastBoostTick != null &&
              DateTime.now().difference(_lastBoostTick!).inMilliseconds < 500;
          return CustomPaint(
            painter: _AudioWaveformPainter(
              phase: _waveCtrl.value * math.pi * 2,
              energy: voice.isListening ? (hasSpeechBoost ? 1.0 : 0.62) : 0.12,
              primaryColor: palette.accentBright,
              secondaryColor: palette.accentPrimary,
            ),
          );
        },
      ),
    );
  }

  Widget _buildHighlightedTranscript(String text, KartaPalette palette) {
    final words = text.split(' ');
    final spans = <InlineSpan>[];
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final cleaned = w.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final isKey = _highlightKeywords.contains(cleaned);
      spans.add(
        TextSpan(
          text: i == words.length - 1 ? w : '$w ',
          style: KartaTypography.bodyPrimary.copyWith(
            fontSize: 12.5,
            fontWeight: isKey ? FontWeight.w800 : FontWeight.w500,
            color: isKey ? palette.accentBright : palette.textPrimary,
          ),
        ),
      );
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }
}

class _RadialCountdownRingPainter extends CustomPainter {
  const _RadialCountdownRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadialCountdownRingPainter old) =>
      old.progress != progress || old.color != color || old.trackColor != trackColor;
}

class _AudioWaveformPainter extends CustomPainter {
  const _AudioWaveformPainter({
    required this.phase,
    required this.energy,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final double phase;
  final double energy;
  final Color primaryColor;
  final Color secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 9;
    final spacing = size.width / barCount;
    final midY = size.height / 2;
    final maxHalfH = (size.height / 2) - 2.0;

    for (var i = 0; i < barCount; i++) {
      final norm = (i - (barCount - 1) / 2).abs() / ((barCount - 1) / 2);
      final envelope = 1.0 - (norm * 0.48);
      final wave = 0.5 +
          0.32 * math.sin(phase + i * 0.85) +
          0.18 * math.cos(phase * 1.7 - i * 1.15);
      final halfH = (2.2 + (maxHalfH - 2.2) * wave.clamp(0.1, 1.0) * energy * envelope);
      final x = spacing * (i + 0.5);
      final paint = Paint()
        ..color = Color.lerp(primaryColor, secondaryColor, norm) ?? primaryColor
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, midY - halfH), Offset(x, midY + halfH), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveformPainter old) =>
      old.phase != phase || old.energy != energy || old.primaryColor != primaryColor;
}

Color _hazardColorForPalette(HazardCategory cat, KartaPalette palette) => switch (cat) {
      HazardCategory.police => palette.statusInfo,
      HazardCategory.accident => palette.statusAlert,
      HazardCategory.roadClosure => palette.statusAlert,
      _ => palette.statusCaution,
    };

IconData _iconForHazard(HazardCategory cat) => switch (cat) {
      HazardCategory.police => Icons.local_police_rounded,
      HazardCategory.accident => Icons.car_crash_rounded,
      HazardCategory.pothole => Icons.warning_amber_rounded,
      HazardCategory.hiddenVehicle => Icons.directions_car_filled_rounded,
      HazardCategory.roadDebris => Icons.report_problem_rounded,
      HazardCategory.roadClosure => Icons.block_rounded,
    };
