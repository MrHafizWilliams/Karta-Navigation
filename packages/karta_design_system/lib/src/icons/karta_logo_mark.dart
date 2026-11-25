import 'package:flutter/material.dart';
import '../tokens/karta_colors.dart';
import '../tokens/karta_palette.dart';

/// Official Karta brand mark backed by the circular transparent `karta_logo.png`
/// emblem (mountain + city skyline crest with Muted Teal #5B9A94 map pin),
/// with a crisp theme-aware vector fallback for headless tests.
class KartaLogoMark extends StatelessWidget {
  const KartaLogoMark({
    super.key,
    this.size = 32,
    this.color,
    this.coreColor,
    this.showWordmark = false,
    this.useOfficialAsset = true,
  });

  final double size;
  final Color? color;
  final Color? coreColor;
  final bool showWordmark;
  final bool useOfficialAsset;

  static const String assetPath = 'assets/karta_logo.png';
  static const String packageName = 'karta_design_system';

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final resolvedAccent = color ?? palette.accentPrimary;
    final resolvedCore = coreColor ?? palette.backgroundPrimary;
    final resolvedChevron = palette.isDaylight
        ? KartaColors.textPrimary
        : palette.textPrimary;

    if (!useOfficialAsset) {
      return _vectorFallback(resolvedAccent, resolvedCore, resolvedChevron);
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image.asset(
          assetPath,
          package: packageName,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) =>
              _vectorFallback(resolvedAccent, resolvedCore, resolvedChevron),
        ),
      ),
    );
  }

  Widget _vectorFallback(
    Color accentColor,
    Color apertureColor,
    Color chevronColor,
  ) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _KartaPinPainter(
          color: accentColor,
          coreColor: apertureColor,
          chevronColor: chevronColor,
        ),
      ),
    );
  }
}

class _KartaPinPainter extends CustomPainter {
  const _KartaPinPainter({
    required this.color,
    required this.coreColor,
    required this.chevronColor,
  });

  final Color color;
  final Color coreColor;
  final Color chevronColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final pinPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final pinPath = Path()
      ..moveTo(cx, h * 0.96)
      ..cubicTo(w * 0.16, h * 0.66, w * 0.12, h * 0.45, w * 0.12, h * 0.38)
      ..arcToPoint(
        Offset(w * 0.88, h * 0.38),
        radius: Radius.circular(w * 0.38),
        clockwise: true,
      )
      ..cubicTo(w * 0.88, h * 0.45, w * 0.84, h * 0.66, cx, h * 0.96)
      ..close();

    canvas.drawPath(pinPath, pinPaint);

    final aperturePaint = Paint()
      ..color = coreColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(Offset(cx, h * 0.38), w * 0.21, aperturePaint);

    final chevronPath = Path()
      ..moveTo(cx, h * 0.23)
      ..lineTo(cx + w * 0.12, h * 0.48)
      ..lineTo(cx, h * 0.42)
      ..lineTo(cx - w * 0.12, h * 0.48)
      ..close();

    final chevronPaint = Paint()
      ..color = chevronColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(chevronPath, chevronPaint);
  }

  @override
  bool shouldRepaint(covariant _KartaPinPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.coreColor != coreColor ||
      oldDelegate.chevronColor != chevronColor;
}
