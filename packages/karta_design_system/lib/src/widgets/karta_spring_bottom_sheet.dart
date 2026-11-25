import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../tokens/karta_palette.dart';
import '../tokens/karta_spacing.dart';
import 'karta_surface_card.dart';

/// Three ergonomic detents for Karta's mobile driving bottom sheet.
enum KartaSheetDetent {
  /// Collapsed ETA pill (~96dp) maximizing 3D map visibility.
  collapsed,

  /// Half-expanded action hub (~46% height): 60x60dp driving actions, media bar, fuel & stops.
  half,

  /// Full-expanded itinerary (~82% height): scrollable turn-by-turn maneuver list across legs.
  expanded,
}

/// Spring-physics 3-state draggable bottom sheet powered by [SpringSimulation].
/// Supports vertical drag with fling-velocity projection and 1-tap detent cycling.
class KartaSpringBottomSheet extends StatefulWidget {
  const KartaSpringBottomSheet({
    super.key,
    required this.collapsedChild,
    required this.halfChild,
    required this.expandedChild,
    this.initialDetent = KartaSheetDetent.collapsed,
    this.collapsedHeight = 96.0,
    this.halfFraction = 0.48,
    this.expandedFraction = 0.82,
    this.onDetentChanged,
  });

  final Widget collapsedChild;
  final Widget halfChild;
  final Widget expandedChild;
  final KartaSheetDetent initialDetent;
  final double collapsedHeight;
  final double halfFraction;
  final double expandedFraction;
  final ValueChanged<KartaSheetDetent>? onDetentChanged;

  @override
  State<KartaSpringBottomSheet> createState() => KartaSpringBottomSheetState();
}

class KartaSpringBottomSheetState extends State<KartaSpringBottomSheet>
    with SingleTickerProviderStateMixin {
  static const SpringDescription _kartaSpring = SpringDescription(
    mass: 1.0,
    stiffness: 290.0,
    damping: 29.0,
  );

  late final AnimationController _ctrl;
  late KartaSheetDetent _detent;
  double _viewportHeight = 760.0;

  KartaSheetDetent get currentDetent => _detent;

  double _fractionFor(KartaSheetDetent d) {
    final minFrac = (widget.collapsedHeight / _viewportHeight).clamp(0.11, 0.24);
    return switch (d) {
      KartaSheetDetent.collapsed => minFrac,
      KartaSheetDetent.half => widget.halfFraction,
      KartaSheetDetent.expanded => widget.expandedFraction,
    };
  }

  @override
  void initState() {
    super.initState();
    _detent = widget.initialDetent;
    _ctrl = AnimationController.unbounded(
      vsync: this,
      value: _fractionFor(_detent),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void snapTo(KartaSheetDetent target, {double velocityFractionPerSec = 0.0}) {
    _detent = target;
    final goal = _fractionFor(target);
    final sim = SpringSimulation(_kartaSpring, _ctrl.value, goal, velocityFractionPerSec);
    _ctrl.animateWith(sim);
    widget.onDetentChanged?.call(target);
    setState(() {});
  }

  void cycleDetent() {
    final next = switch (_detent) {
      KartaSheetDetent.collapsed => KartaSheetDetent.half,
      KartaSheetDetent.half => KartaSheetDetent.expanded,
      KartaSheetDetent.expanded => KartaSheetDetent.collapsed,
    };
    snapTo(next);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final minF = _fractionFor(KartaSheetDetent.collapsed);
    final maxF = _fractionFor(KartaSheetDetent.expanded);
    final delta = -details.delta.dy / _viewportHeight;
    _ctrl.value = (_ctrl.value + delta).clamp(minF * 0.92, maxF * 1.03);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocityFrac = -(details.primaryVelocity ?? 0.0) / _viewportHeight;
    final projected = _ctrl.value + velocityFrac * 0.14;

    final stops = <(KartaSheetDetent, double)>[
      (KartaSheetDetent.collapsed, _fractionFor(KartaSheetDetent.collapsed)),
      (KartaSheetDetent.half, _fractionFor(KartaSheetDetent.half)),
      (KartaSheetDetent.expanded, _fractionFor(KartaSheetDetent.expanded)),
    ];

    var nearest = stops.first.$1;
    var bestDist = double.infinity;
    for (final (detent, frac) in stops) {
      final dist = (projected - frac).abs();
      if (dist < bestDist) {
        bestDist = dist;
        nearest = detent;
      }
    }
    snapTo(nearest, velocityFractionPerSec: velocityFrac.clamp(-4.0, 4.0));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final screenH = MediaQuery.sizeOf(context).height;
    if (screenH > 200) {
      _viewportHeight = screenH;
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final height = (_ctrl.value * _viewportHeight)
            .clamp(widget.collapsedHeight, _viewportHeight * 0.88);
        final halfThreshold = (_fractionFor(KartaSheetDetent.collapsed) + widget.halfFraction) * 0.5;
        final fullThreshold = (widget.halfFraction + widget.expandedFraction) * 0.5;

        final showHalf = _ctrl.value >= halfThreshold;
        final showExpanded = _ctrl.value >= fullThreshold;

        return SizedBox(
          height: height,
          child: KartaSurfaceCard(
            padding: EdgeInsets.zero,
            borderRadius: KartaSpacing.radiusLg,
            deepGlass: true,
            highlighted: showExpanded,
            child: Column(
              children: <Widget>[
                // Interactive Spring Drag Handle & Tap-to-Cycle Bar
                GestureDetector(
                  key: const ValueKey<String>('karta-sheet-handle'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  onTap: cycleDetent,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 44,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: palette.borderStrong,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 6),
                        widget.collapsedChild,
                      ],
                    ),
                  ),
                ),

                if (showHalf) ...<Widget>[
                  Divider(height: 1, color: palette.borderSubtle),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: showExpanded
                          ? KeyedSubtree(
                              key: const ValueKey<String>('sheet-expanded'),
                              child: widget.expandedChild,
                            )
                          : KeyedSubtree(
                              key: const ValueKey<String>('sheet-half'),
                              child: widget.halfChild,
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
