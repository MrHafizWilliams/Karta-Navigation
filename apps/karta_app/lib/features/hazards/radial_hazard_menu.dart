import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_design_system/karta_design_system.dart';

import '../../state/phase3_providers.dart';

class _HazardSectorSpec {
  const _HazardSectorSpec({
    required this.category,
    required this.label,
    required this.icon,
    required this.angleDeg,
  });

  final HazardCategory category;
  final String label;
  final IconData icon;
  final double angleDeg;
}

const List<_HazardSectorSpec> _fullRadialSectors = <_HazardSectorSpec>[
  _HazardSectorSpec(
    category: HazardCategory.police,
    label: 'Police',
    icon: Icons.local_police_rounded,
    angleDeg: -90,
  ),
  _HazardSectorSpec(
    category: HazardCategory.accident,
    label: 'Accident',
    icon: Icons.car_crash_rounded,
    angleDeg: -30,
  ),
  _HazardSectorSpec(
    category: HazardCategory.pothole,
    label: 'Pothole',
    icon: Icons.warning_amber_rounded,
    angleDeg: 30,
  ),
  _HazardSectorSpec(
    category: HazardCategory.hiddenVehicle,
    label: 'Stopped Car',
    icon: Icons.directions_car_filled_rounded,
    angleDeg: 90,
  ),
  _HazardSectorSpec(
    category: HazardCategory.roadDebris,
    label: 'Debris',
    icon: Icons.report_problem_rounded,
    angleDeg: 150,
  ),
  _HazardSectorSpec(
    category: HazardCategory.roadClosure,
    label: 'Closure',
    icon: Icons.block_rounded,
    angleDeg: -150,
  ),
];

/// Quick-flick 4-sector inward arc specs for zero-look tap-and-slide reporting.
class _QuickFlickTarget {
  const _QuickFlickTarget({
    required this.category,
    required this.label,
    required this.icon,
    required this.rightAnchorAngleDeg,
    required this.leftAnchorAngleDeg,
  });

  final HazardCategory category;
  final String label;
  final IconData icon;
  final double rightAnchorAngleDeg;
  final double leftAnchorAngleDeg;

  double angleForSide(bool isRightAnchored) =>
      isRightAnchored ? rightAnchorAngleDeg : leftAnchorAngleDeg;
}

const List<_QuickFlickTarget> _quickFlickTargets = <_QuickFlickTarget>[
  _QuickFlickTarget(
    category: HazardCategory.roadClosure,
    label: 'Closure',
    icon: Icons.block_rounded,
    rightAnchorAngleDeg: -100,
    leftAnchorAngleDeg: -80,
  ),
  _QuickFlickTarget(
    category: HazardCategory.police,
    label: 'Police',
    icon: Icons.local_police_rounded,
    rightAnchorAngleDeg: -140,
    leftAnchorAngleDeg: -40,
  ),
  _QuickFlickTarget(
    category: HazardCategory.accident,
    label: 'Crash',
    icon: Icons.car_crash_rounded,
    rightAnchorAngleDeg: 180,
    leftAnchorAngleDeg: 0,
  ),
  _QuickFlickTarget(
    category: HazardCategory.pothole,
    label: 'Hazard',
    icon: Icons.warning_amber_rounded,
    rightAnchorAngleDeg: 140,
    leftAnchorAngleDeg: 40,
  ),
];

Color _sectorAccentColor(HazardCategory category, KartaPalette palette) => switch (category) {
      HazardCategory.police => palette.statusInfo,
      HazardCategory.accident => palette.statusAlert,
      HazardCategory.roadClosure => palette.statusAlert,
      _ => palette.statusCaution,
    };

/// Floating driver trigger cluster on the right edge:
/// - Fuel Finder pill (with live emerald indicator when inline route pins are hydrated)
/// - Hands-Free Voice Mic button (opens minimal bottom audio waveform pill)
/// - [QuickFlickRadialFab] supporting tap-and-slide quick-flick OR single-tap full 6-sector wheel.
class FloatingCrowdsourcingTriggerCluster extends ConsumerWidget {
  const FloatingCrowdsourcingTriggerCluster({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final realtime = ref.watch(realtimeCrowdsourcingProvider);
    final voice = ref.watch(handsFreeVoiceProvider);
    final fuel = ref.watch(fuelComparisonProvider);
    final palette = context.kartaPalette;
    final hasCheapestInline = fuel.response?.cheapestFormattedPrice != null;

    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Fuel Finder Quick Toggle (60x60dp active-driving target)
        Tooltip(
          message: hasCheapestInline
              ? 'Fuel Prices · Best ${fuel.selectedGrade.shortLabel}: ${fuel.response!.cheapestFormattedPrice}'
              : 'Fuel Prices Along Route',
          child: InkWell(
            onTap: () => ref.read(realtimeCrowdsourcingProvider.notifier).toggleFuelOverlay(),
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: KartaSpacing.minDrivingTouchTarget,
              height: KartaSpacing.minDrivingTouchTarget,
              decoration: BoxDecoration(
                color: realtime.activeFuelOverlayOpen ? palette.accentPrimary : palette.hudGlass,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: realtime.activeFuelOverlayOpen
                      ? palette.accentBright
                      : (hasCheapestInline
                          ? palette.statusClear.withValues(alpha: 0.8)
                          : palette.borderStrong),
                  width: 1.3,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: palette.shadowColor, blurRadius: 14, offset: const Offset(0, 6)),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.local_gas_station_rounded,
                        size: 21,
                        color: realtime.activeFuelOverlayOpen ? onPrimary : palette.accentBright,
                      ),
                      Text(
                        'FUEL',
                        style: KartaTypography.monoBadge.copyWith(
                          fontSize: 11,
                          color:
                              realtime.activeFuelOverlayOpen ? onPrimary : palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (hasCheapestInline && !realtime.activeFuelOverlayOpen)
                    Positioned(
                      top: 6,
                      right: 7,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.statusClear,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Hands-Free Voice Reporting Trigger (60x60dp active-driving target)
        Tooltip(
          message: 'Hands-Free Voice Hazard Report (EN · BM · Manglish · Singlish)',
          child: InkWell(
            key: const ValueKey<String>('karta-voice-trigger-btn'),
            onTap: () {
              if (voice.isListening) {
                ref.read(handsFreeVoiceProvider.notifier).stopListening();
              } else {
                ref.read(handsFreeVoiceProvider.notifier).startListening();
              }
            },
            borderRadius: BorderRadius.circular(30),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: KartaSpacing.minDrivingTouchTarget,
              height: KartaSpacing.minDrivingTouchTarget,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: voice.isListening ? palette.statusAlert : palette.hudGlass,
                border: Border.all(
                  color: voice.isListening
                      ? palette.statusAlert
                      : palette.accentPrimary.withValues(alpha: 0.85),
                  width: 1.8,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: (voice.isListening ? palette.statusAlert : palette.accentPrimary)
                        .withValues(alpha: 0.34),
                    blurRadius: voice.isListening ? 20 : 12,
                  ),
                ],
              ),
              child: Icon(
                voice.isListening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                size: 25,
                color: voice.isListening ? onPrimary : palette.accentBright,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Tactile Quick-Flick Radial Hazard Trigger (Tap-and-Slide OR Single Tap)
        const QuickFlickRadialFab(),
      ],
    );
  }
}

/// Dual-mode ergonomic hazard reporting trigger:
/// - **Quick-Flick (Tap-and-Slide or Hold >= 180ms)**: Blooms an edge-aware 4-sector
///   radial arc around the driver's thumb (*Closure, Police, Crash, Hazard*) with
///   magnetic snap (`HapticFeedback.selectionClick`) and release-to-report
///   (`HapticFeedback.heavyImpact` + Web Audio chime).
/// - **Quick Single Tap (< 180ms, < 10dp drag)**: Opens the full 6-sector
///   [RadialHazardMenuOverlay] with modifiers, severity, and center voice mic.
class QuickFlickRadialFab extends ConsumerStatefulWidget {
  const QuickFlickRadialFab({super.key});

  @override
  ConsumerState<QuickFlickRadialFab> createState() => _QuickFlickRadialFabState();
}

class _QuickFlickRadialFabState extends ConsumerState<QuickFlickRadialFab> {
  static const double _arcRadius = 104.0;
  static const double _engageRadius = 32.0;
  static const double _deadzoneReleaseRadius = 28.0;

  OverlayEntry? _flickOverlay;
  Timer? _holdTimer;
  Timer? _commitFlashTimer;

  Offset _downGlobalPos = Offset.zero;
  Offset _fabGlobalCenter = Offset.zero;
  Offset _currentDragVector = Offset.zero;
  bool _isRightAnchored = true;
  bool _flickActive = false;
  int? _lockedSectorIndex;
  int? _committedSectorIndex;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _commitFlashTimer?.cancel();
    _removeFlickOverlay();
    super.dispose();
  }

  void _removeFlickOverlay() {
    _flickOverlay?.remove();
    _flickOverlay = null;
  }

  void _openFlickOverlay() {
    if (_flickActive || !mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _flickActive = true;
      _committedSectorIndex = null;
    });

    _removeFlickOverlay();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _flickOverlay = OverlayEntry(
      builder: (ctx) => _QuickFlickPortalOverlay(
        fabCenter: _fabGlobalCenter,
        dragVector: _currentDragVector,
        arcRadius: _arcRadius,
        isRightAnchored: _isRightAnchored,
        lockedIndex: _lockedSectorIndex,
        committedIndex: _committedSectorIndex,
      ),
    );
    overlay.insert(_flickOverlay!);
  }

  int? _resolveSectorIndex(Offset vector) {
    final dist = vector.distance;
    if (_lockedSectorIndex == null && dist < _engageRadius) return null;
    if (_lockedSectorIndex != null && dist < _deadzoneReleaseRadius) return null;

    final dragAngleDeg = math.atan2(vector.dy, vector.dx) * 180.0 / math.pi;

    int? bestIdx;
    double bestDiff = double.infinity;

    for (var i = 0; i < _quickFlickTargets.length; i++) {
      final targetDeg = _quickFlickTargets[i].angleForSide(_isRightAnchored);
      var diff = (dragAngleDeg - targetDeg + 180.0) % 360.0 - 180.0;
      if (diff < -180.0) diff += 360.0;
      final absDiff = diff.abs();
      // 6-degree hysteresis favoring currently locked sector to prevent finger chatter
      final effectiveThreshold = i == _lockedSectorIndex ? 30.0 : 24.0;
      if (absDiff <= effectiveThreshold && absDiff < bestDiff) {
        bestDiff = absDiff;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _commitFlashTimer?.cancel();
    _removeFlickOverlay();

    final box = context.findRenderObject() as RenderBox?;
    final screenW = MediaQuery.sizeOf(context).width;
    final center = box != null
        ? box.localToGlobal(box.size.center(Offset.zero))
        : event.position;

    _downGlobalPos = event.position;
    _fabGlobalCenter = center;
    _currentDragVector = Offset.zero;
    _isRightAnchored = center.dx >= screenW * 0.5;
    _flickActive = false;
    _lockedSectorIndex = null;
    _committedSectorIndex = null;

    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted && !_flickActive) {
        _openFlickOverlay();
      }
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final travel = (event.position - _downGlobalPos).distance;
    final vector = event.position - _fabGlobalCenter;

    if (!_flickActive && travel >= 10.0) {
      _holdTimer?.cancel();
      _openFlickOverlay();
    }

    if (_flickActive) {
      _currentDragVector = vector;
      final nextIdx = _resolveSectorIndex(vector);
      if (nextIdx != _lockedSectorIndex) {
        _lockedSectorIndex = nextIdx;
        if (nextIdx != null) {
          HapticFeedback.selectionClick();
        }
      }
      _flickOverlay?.markNeedsBuild();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _holdTimer?.cancel();

    if (!_flickActive) {
      // Quick single tap -> open full 6-sector radial wheel modal
      ref.read(realtimeCrowdsourcingProvider.notifier).toggleRadialMenu(true);
      return;
    }

    final locked = _lockedSectorIndex;
    if (locked != null) {
      final target = _quickFlickTargets[locked];
      HapticFeedback.heavyImpact();
      ref.read(realtimeCrowdsourcingProvider.notifier).reportHazard(
            category: target.category,
            source: 'quick_flick',
          );
      setState(() {
        _committedSectorIndex = locked;
        _flickActive = false;
      });
      _flickOverlay?.markNeedsBuild();
      _commitFlashTimer?.cancel();
      _commitFlashTimer = Timer(const Duration(milliseconds: 280), () {
        _removeFlickOverlay();
        if (mounted) {
          setState(() {
            _lockedSectorIndex = null;
            _committedSectorIndex = null;
          });
        }
      });
    } else {
      // Released inside neutral deadzone -> cancel cleanly
      _removeFlickOverlay();
      setState(() {
        _flickActive = false;
        _lockedSectorIndex = null;
      });
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _holdTimer?.cancel();
    _removeFlickOverlay();
    if (mounted) {
      setState(() {
        _flickActive = false;
        _lockedSectorIndex = null;
        _committedSectorIndex = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final realtime = ref.watch(realtimeCrowdsourcingProvider);
    final palette = context.kartaPalette;
    final activeColor = _flickActive ? palette.accentPrimary : palette.statusCaution;

    return Tooltip(
      message: 'Tap for full hazard menu · Slide to quick-report (Police, Crash, Hazard, Closure)',
      child: Listener(
        key: const ValueKey<String>('karta-quick-flick-fab'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: AnimatedScale(
          scale: _flickActive ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: <Color>[
                  activeColor,
                  _flickActive ? palette.accentBright : palette.statusAlert,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: _flickActive ? 0.85 : 0.35),
                width: 1.8,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.48),
                  blurRadius: _flickActive ? 24 : 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Icon(
                  realtime.radialMenuOpen
                      ? Icons.close_rounded
                      : (_flickActive ? Icons.open_with_rounded : Icons.add_alert_rounded),
                  size: 26,
                  color: Colors.white,
                ),
                if (realtime.hazards.isNotEmpty && !_flickActive)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: palette.backgroundPrimary,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: palette.borderSubtle, width: 0.8),
                      ),
                      child: Text(
                        '${realtime.hazards.length}',
                        style: KartaTypography.monoBadge.copyWith(
                          fontSize: 11,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickFlickPortalOverlay extends StatelessWidget {
  const _QuickFlickPortalOverlay({
    required this.fabCenter,
    required this.dragVector,
    required this.arcRadius,
    required this.isRightAnchored,
    required this.lockedIndex,
    required this.committedIndex,
  });

  final Offset fabCenter;
  final Offset dragVector;
  final double arcRadius;
  final bool isRightAnchored;
  final int? lockedIndex;
  final int? committedIndex;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final activeIdx = committedIndex ?? lockedIndex;
    final activeTarget = activeIdx != null ? _quickFlickTargets[activeIdx] : null;
    final activeColor = activeTarget != null
        ? _sectorAccentColor(activeTarget.category, palette)
        : palette.accentBright;

    final clampedVector = dragVector.distance > arcRadius
        ? Offset.fromDirection(dragVector.direction, arcRadius)
        : dragVector;

    Offset? snappedPos;
    if (activeTarget != null) {
      final rad = activeTarget.angleForSide(isRightAnchored) * math.pi / 180.0;
      snappedPos = fabCenter + Offset(math.cos(rad) * arcRadius, math.sin(rad) * arcRadius);
    }

    final screenSize = MediaQuery.sizeOf(context);
    final labelLeft = (fabCenter.dx + (isRightAnchored ? -156.0 : -24.0))
        .clamp(12.0, math.max(12.0, screenSize.width - 196.0))
        .toDouble();
    final labelTop = (fabCenter.dy - arcRadius - 62.0)
        .clamp(16.0, screenSize.height - 60.0)
        .toDouble();

    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          key: const ValueKey<String>('karta-quick-flick-arc-overlay'),
          children: <Widget>[
            // Subtle directional tether & deadzone guide ring
            Positioned.fill(
              child: CustomPaint(
                painter: _QuickFlickArcPainter(
                  origin: fabCenter,
                  dragTip: snappedPos ?? (fabCenter + clampedVector),
                  arcRadius: arcRadius,
                  isRightAnchored: isRightAnchored,
                  tetherColor: activeColor,
                  ringColor: palette.borderStrong.withValues(alpha: 0.7),
                  isLocked: activeIdx != null,
                  isCommitted: committedIndex != null,
                ),
              ),
            ),

            // Peripheral floating readout pill above thumb
            Positioned(
              left: labelLeft,
              top: labelTop,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: palette.hudDeepGlass,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: activeColor.withValues(alpha: 0.85),
                        width: 1.25,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: palette.shadowColor,
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          committedIndex != null
                              ? Icons.check_circle_rounded
                              : (activeTarget?.icon ?? Icons.swipe_rounded),
                          size: 15,
                          color: committedIndex != null ? palette.statusClear : activeColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          committedIndex != null
                              ? '${activeTarget!.label} Reported!'
                              : (activeTarget != null
                                  ? 'Release → ${activeTarget.label}'
                                  : 'Slide to report'),
                          style: KartaTypography.bodyPrimary.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: committedIndex != null
                                ? palette.statusClear
                                : palette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 4 Quick-Flick Radial Sector Targets
            for (var i = 0; i < _quickFlickTargets.length; i++) ...<Widget>[
              Builder(
                builder: (_) {
                  final t = _quickFlickTargets[i];
                  final rad = t.angleForSide(isRightAnchored) * math.pi / 180.0;
                  final cx = fabCenter.dx + math.cos(rad) * arcRadius;
                  final cy = fabCenter.dy + math.sin(rad) * arcRadius;
                  final isLocked = i == activeIdx;
                  final isCommitted = i == committedIndex;
                  final color = _sectorAccentColor(t.category, palette);

                  return Positioned(
                    left: cx - 32,
                    top: cy - 32,
                    child: AnimatedScale(
                      scale: isCommitted ? 1.32 : (isLocked ? 1.22 : 1.0),
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutBack,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isLocked ? color : palette.hudDeepGlass,
                          border: Border.all(
                            color: isLocked ? Colors.white : color.withValues(alpha: 0.85),
                            width: isLocked ? 2.4 : 1.6,
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: color.withValues(alpha: isLocked ? 0.52 : 0.22),
                              blurRadius: isLocked ? 22 : 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              isCommitted ? Icons.check_rounded : t.icon,
                              size: 22,
                              color: isLocked ? Colors.white : color,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              t.label,
                              style: KartaTypography.captionLabel.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isLocked ? Colors.white : palette.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickFlickArcPainter extends CustomPainter {
  const _QuickFlickArcPainter({
    required this.origin,
    required this.dragTip,
    required this.arcRadius,
    required this.isRightAnchored,
    required this.tetherColor,
    required this.ringColor,
    required this.isLocked,
    required this.isCommitted,
  });

  final Offset origin;
  final Offset dragTip;
  final double arcRadius;
  final bool isRightAnchored;
  final Color tetherColor;
  final Color ringColor;
  final bool isLocked;
  final bool isCommitted;

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle neutral deadzone circle around FAB
    canvas.drawCircle(
      origin,
      30,
      Paint()
        ..color = ringColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Subtle inward arc track connecting the 4 quick-flick targets
    final startDeg = isRightAnchored ? -105.0 : -85.0;
    final sweepDeg = isRightAnchored ? -125.0 : 125.0;
    canvas.drawArc(
      Rect.fromCircle(center: origin, radius: arcRadius),
      startDeg * math.pi / 180.0,
      sweepDeg * math.pi / 180.0,
      false,
      Paint()
        ..color = ringColor.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // Directional tether beam from FAB origin to current finger / snapped sector
    if ((dragTip - origin).distance > 8.0) {
      canvas.drawLine(
        origin,
        dragTip,
        Paint()
          ..color = tetherColor.withValues(alpha: isLocked ? 0.85 : 0.42)
          ..strokeWidth = isLocked ? 4.5 : 2.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        dragTip,
        isCommitted ? 16 : (isLocked ? 8 : 5),
        Paint()..color = tetherColor.withValues(alpha: isCommitted ? 0.32 : 0.78),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _QuickFlickArcPainter old) =>
      old.dragTip != dragTip ||
      old.isLocked != isLocked ||
      old.isCommitted != isCommitted ||
      old.tetherColor != tetherColor;
}

/// Full 6-sector radial hazard reporting wheel (opened on quick single tap of the FAB).
/// Fully dual-lighting aware via `context.kartaPalette`, with quick modifiers,
/// severity selector, center hands-free voice mic, and 3-second auto-submit confirmation.
class RadialHazardMenuOverlay extends ConsumerStatefulWidget {
  const RadialHazardMenuOverlay({super.key});

  @override
  ConsumerState<RadialHazardMenuOverlay> createState() => _RadialHazardMenuOverlayState();
}

class _RadialHazardMenuOverlayState extends ConsumerState<RadialHazardMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  HazardCategory? _pendingCategory;
  bool _oppositeSide = false;
  HazardSeverity _severity = HazardSeverity.medium;
  Timer? _autoSubmitTimer;
  int _countdown = 3;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..forward();
  }

  @override
  void dispose() {
    _autoSubmitTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _selectCategory(HazardCategory category) {
    _autoSubmitTimer?.cancel();
    HapticFeedback.selectionClick();
    setState(() {
      _pendingCategory = category;
      _countdown = 3;
      _severity = category == HazardCategory.accident || category == HazardCategory.roadClosure
          ? HazardSeverity.high
          : HazardSeverity.medium;
    });
    _autoSubmitTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown -= 1);
      if (_countdown <= 0) {
        t.cancel();
        _commitReport();
      }
    });
  }

  Future<void> _commitReport() async {
    _autoSubmitTimer?.cancel();
    final cat = _pendingCategory;
    if (cat == null) return;
    HapticFeedback.heavyImpact();
    await ref.read(realtimeCrowdsourcingProvider.notifier).reportHazard(
          category: cat,
          severity: _severity,
          oppositeSide: _oppositeSide,
          source: 'radial',
        );
    if (mounted) {
      ref.read(realtimeCrowdsourcingProvider.notifier).toggleRadialMenu(false);
    }
  }

  void _close() {
    _autoSubmitTimer?.cancel();
    ref.read(realtimeCrowdsourcingProvider.notifier).toggleRadialMenu(false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutBack);

    return Material(
      color: Colors.black.withValues(alpha: 0.62),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(onTap: _close),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: palette.hudDeepGlass,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: palette.borderStrong),
                    ),
                    child: Text(
                      _pendingCategory == null
                          ? 'REPORT LIVE HAZARD · TAP SECTOR OR SPEAK'
                          : '${_pendingCategory!.label.toUpperCase()} · AUTO-SENDING IN ${_countdown}s',
                      style: KartaTypography.monoBadge.copyWith(
                        fontSize: 11,
                        color: palette.accentBright,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 6-sector radial wheel
                  AnimatedBuilder(
                    animation: curve,
                    builder: (context, _) {
                      final radius = 122.0 * curve.value.clamp(0.0, 1.05);
                      return SizedBox(
                        width: 340,
                        height: 340,
                        child: Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            Container(
                              width: 266,
                              height: 266,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.hudGlass,
                                border: Border.all(color: palette.borderSubtle, width: 1.5),
                              ),
                            ),

                            for (final sector in _fullRadialSectors)
                              _buildRadialButton(sector, radius, palette),

                            // Center Hands-Free Voice Mic button
                            InkWell(
                              onTap: () {
                                _close();
                                ref.read(handsFreeVoiceProvider.notifier).startListening();
                              },
                              borderRadius: BorderRadius.circular(44),
                              child: Container(
                                width: 82,
                                height: 82,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: palette.accentPrimary,
                                  border: Border.all(color: palette.accentBright, width: 2),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: palette.accentPrimary.withValues(alpha: 0.45),
                                      blurRadius: 20,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    Icon(Icons.mic_rounded, color: onPrimary, size: 28),
                                    const SizedBox(height: 2),
                                    Text(
                                      'SPEAK',
                                      style: KartaTypography.monoBadge.copyWith(
                                        fontSize: 11,
                                        color: onPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Quick modifiers + confirmation bar
                  if (_pendingCategory != null)
                    Container(
                      width: 340,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.hudDeepGlass,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: palette.accentPrimary.withValues(alpha: 0.72)),
                      ),
                      child: Column(
                        children: <Widget>[
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: <Widget>[
                              FilterChip(
                                label: const Text('Opposite Side'),
                                selected: _oppositeSide,
                                onSelected: (v) => setState(() => _oppositeSide = v),
                              ),
                              ChoiceChip(
                                label: const Text('Medium'),
                                selected: _severity == HazardSeverity.medium,
                                onSelected: (_) => setState(() => _severity = HazardSeverity.medium),
                              ),
                              ChoiceChip(
                                label: const Text('High'),
                                selected: _severity == HazardSeverity.high,
                                onSelected: (_) => setState(() => _severity = HazardSeverity.high),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _close,
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _commitReport,
                                  icon: const Icon(Icons.send_rounded, size: 16),
                                  label: const Text('Report Now'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    Material(
                      color: palette.hudDeepGlass,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide(color: palette.borderStrong),
                      ),
                      child: InkWell(
                        onTap: _close,
                        borderRadius: BorderRadius.circular(999),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 112,
                            minHeight: KartaSpacing.minTouchTarget,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(Icons.close_rounded, size: 18, color: palette.textPrimary),
                                const SizedBox(width: 6),
                                Text(
                                  'Dismiss',
                                  style: KartaTypography.bodyPrimary.copyWith(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadialButton(_HazardSectorSpec sector, double radius, KartaPalette palette) {
    final rad = sector.angleDeg * math.pi / 180.0;
    final dx = math.cos(rad) * radius;
    final dy = math.sin(rad) * radius;
    final isSelected = _pendingCategory == sector.category;
    final color = _sectorAccentColor(sector.category, palette);

    const double center = 170.0;
    const double halfW = 46.0;
    const double halfH = 40.0;

    return Positioned(
      left: center + dx - halfW,
      top: center + dy - halfH,
      child: InkWell(
        onTap: () => _selectCategory(sector.category),
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 92,
          height: 80,
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.24) : palette.surfaceCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color : palette.borderStrong,
              width: isSelected ? 2.2 : 1.2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: (isSelected ? color : palette.shadowColor).withValues(alpha: 0.42),
                blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(sector.icon, size: 25, color: color),
              const SizedBox(height: 5),
              Text(
                sector.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KartaTypography.captionLabel.copyWith(
                  fontSize: 10.5,
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
