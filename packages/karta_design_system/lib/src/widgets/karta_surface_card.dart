import 'dart:ui';
import 'package:flutter/material.dart';
import '../tokens/karta_palette.dart';
import '../tokens/karta_spacing.dart';

/// Theme-aware frosted glassmorphic automotive surface adapting seamlessly between
/// Obsidian Night Mode (`#181C22`) and High-Glare Tropical Daylight Mode (`#FCFBF8`).
class KartaSurfaceCard extends StatelessWidget {
  const KartaSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(KartaSpacing.md),
    this.borderRadius = KartaSpacing.radiusMd,
    this.borderColor,
    this.backgroundColor,
    this.deepGlass = false,
    this.blurSigma = 16,
    this.highlighted = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final bool deepGlass;
  final double blurSigma;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final radius = BorderRadius.circular(borderRadius);
    final effectiveBg = backgroundColor ?? (deepGlass ? palette.hudDeepGlass : palette.hudGlass);
    final effectiveBorder =
        highlighted ? palette.accentPrimary : (borderColor ?? palette.borderSubtle);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: effectiveBg,
            borderRadius: radius,
            border: Border.all(
              color: effectiveBorder,
              width: highlighted ? 1.6 : (palette.isDaylight ? 1.2 : 1.0),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: palette.shadowColor,
                blurRadius: palette.isDaylight ? 18 : 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
