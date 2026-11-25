import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../tokens/karta_palette.dart';

/// Crisp vector turn-by-turn maneuver glyphs mapped directly to Valhalla
/// maneuver type integers (1..37) for automotive HUD legibility.
class KartaManeuverIcon extends StatelessWidget {
  const KartaManeuverIcon({
    super.key,
    required this.valhallaType,
    this.size = 38,
    this.color,
  });

  final int valhallaType;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? context.kartaPalette.textPrimary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ManeuverPainter(valhallaType: valhallaType, color: resolvedColor),
      ),
    );
  }
}

class _ManeuverPainter extends CustomPainter {
  const _ManeuverPainter({required this.valhallaType, required this.color});

  final int valhallaType;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.115
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    void drawArrowHead(Offset tip, double angleRad) {
      final headLen = w * 0.24;
      final left = Offset(
        tip.dx - headLen * math.cos(angleRad - 0.55),
        tip.dy - headLen * math.sin(angleRad - 0.55),
      );
      final right = Offset(
        tip.dx - headLen * math.cos(angleRad + 0.55),
        tip.dy - headLen * math.sin(angleRad + 0.55),
      );
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(path, fill);
    }

    switch (valhallaType) {
      // Destination (4, 5, 6)
      case 4:
      case 5:
      case 6:
        canvas.drawCircle(Offset(w * 0.5, h * 0.42), w * 0.22, stroke);
        canvas.drawCircle(Offset(w * 0.5, h * 0.42), w * 0.08, fill);
        canvas.drawLine(Offset(w * 0.5, h * 0.66), Offset(w * 0.5, h * 0.88), stroke);
        return;

      // Slight right (9), Ramp right (18), Exit right (20), Stay right (23), Merge right (25)
      case 9:
      case 18:
      case 20:
      case 23:
      case 25:
        final p = Path()
          ..moveTo(w * 0.36, h * 0.86)
          ..lineTo(w * 0.36, h * 0.54)
          ..lineTo(w * 0.68, h * 0.22);
        canvas.drawPath(p, stroke);
        drawArrowHead(Offset(w * 0.72, h * 0.18), -math.pi / 4);
        return;

      // Right turn (10), Sharp right (11)
      case 10:
      case 11:
        final p = Path()
          ..moveTo(w * 0.30, h * 0.86)
          ..lineTo(w * 0.30, h * 0.42)
          ..quadraticBezierTo(w * 0.30, h * 0.30, w * 0.44, h * 0.30)
          ..lineTo(w * 0.72, h * 0.30);
        canvas.drawPath(p, stroke);
        drawArrowHead(Offset(w * 0.82, h * 0.30), 0);
        return;

      // U-turn right (12) / U-turn left (13)
      case 12:
      case 13:
        final isLeft = valhallaType == 13;
        final xStart = isLeft ? w * 0.68 : w * 0.32;
        final xEnd = isLeft ? w * 0.30 : w * 0.70;
        final p = Path()
          ..moveTo(xStart, h * 0.86)
          ..lineTo(xStart, h * 0.34)
          ..arcToPoint(
            Offset(xEnd, h * 0.34),
            radius: Radius.circular(w * 0.19),
            clockwise: !isLeft,
          )
          ..lineTo(xEnd, h * 0.62);
        canvas.drawPath(p, stroke);
        drawArrowHead(Offset(xEnd, h * 0.70), math.pi / 2);
        return;

      // Slight left (16), Ramp left (19), Exit left (21), Stay left (24), Merge left (26)
      case 16:
      case 19:
      case 21:
      case 24:
      case 26:
        final p = Path()
          ..moveTo(w * 0.64, h * 0.86)
          ..lineTo(w * 0.64, h * 0.54)
          ..lineTo(w * 0.32, h * 0.22);
        canvas.drawPath(p, stroke);
        drawArrowHead(Offset(w * 0.28, h * 0.18), -3 * math.pi / 4);
        return;

      // Left turn (15), Sharp left (14)
      case 14:
      case 15:
        final p = Path()
          ..moveTo(w * 0.70, h * 0.86)
          ..lineTo(w * 0.70, h * 0.42)
          ..quadraticBezierTo(w * 0.70, h * 0.30, w * 0.56, h * 0.30)
          ..lineTo(w * 0.28, h * 0.30);
        canvas.drawPath(p, stroke);
        drawArrowHead(Offset(w * 0.18, h * 0.30), math.pi);
        return;

      // Roundabout (26, 27)
      case 27:
        canvas.drawCircle(Offset(w * 0.5, h * 0.46), w * 0.19, stroke);
        canvas.drawLine(Offset(w * 0.5, h * 0.88), Offset(w * 0.5, h * 0.66), stroke);
        canvas.drawLine(Offset(w * 0.5, h * 0.26), Offset(w * 0.5, h * 0.15), stroke);
        drawArrowHead(Offset(w * 0.5, h * 0.12), -math.pi / 2);
        return;

      // Straight / Continue / Start (1, 2, 3, 7, 8, 17, 22, default)
      default:
        canvas.drawLine(Offset(w * 0.5, h * 0.86), Offset(w * 0.5, h * 0.24), stroke);
        drawArrowHead(Offset(w * 0.5, h * 0.16), -math.pi / 2);
        return;
    }
  }

  @override
  bool shouldRepaint(covariant _ManeuverPainter oldDelegate) =>
      oldDelegate.valhallaType != valhallaType || oldDelegate.color != color;
}

/// Vector lane arrow widget used inside Karta's Turn-Lane Guidance Banner.
class KartaLaneArrow extends StatelessWidget {
  const KartaLaneArrow({
    super.key,
    required this.laneSpec,
    required this.isRecommended,
    this.size = 24,
  });

  /// OSM/Valhalla turn lane token, e.g. 'left', 'through', 'through;right', 'slight_left'
  final String laneSpec;
  final bool isRecommended;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final activeColor = isRecommended
        ? palette.accentBright
        : palette.textSecondary.withValues(alpha: 0.55);
    final tokens = laneSpec.toLowerCase().split(';').where((e) => e.isNotEmpty).toList();
    if (tokens.isEmpty) tokens.add('through');

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LaneArrowPainter(tokens: tokens, color: activeColor),
      ),
    );
  }
}

class _LaneArrowPainter extends CustomPainter {
  const _LaneArrowPainter({required this.tokens, required this.color});

  final List<String> tokens;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    for (final raw in tokens) {
      final token = raw.trim();
      if (token.contains('left')) {
        final slight = token.contains('slight');
        final path = Path()
          ..moveTo(w * 0.5, h * 0.88)
          ..lineTo(w * 0.5, h * 0.48)
          ..lineTo(slight ? w * 0.30 : w * 0.18, slight ? h * 0.22 : h * 0.40);
        canvas.drawPath(path, paint);
      } else if (token.contains('right')) {
        final slight = token.contains('slight');
        final path = Path()
          ..moveTo(w * 0.5, h * 0.88)
          ..lineTo(w * 0.5, h * 0.48)
          ..lineTo(slight ? w * 0.70 : w * 0.82, slight ? h * 0.22 : h * 0.40);
        canvas.drawPath(path, paint);
      } else if (token.contains('reverse')) {
        final path = Path()
          ..moveTo(w * 0.62, h * 0.88)
          ..lineTo(w * 0.62, h * 0.35)
          ..arcToPoint(Offset(w * 0.32, h * 0.35), radius: Radius.circular(w * 0.15), clockwise: false)
          ..lineTo(w * 0.32, h * 0.64);
        canvas.drawPath(path, paint);
      } else {
        // through / none
        canvas.drawLine(Offset(w * 0.5, h * 0.88), Offset(w * 0.5, h * 0.16), paint);
        canvas.drawLine(Offset(w * 0.34, h * 0.32), Offset(w * 0.5, h * 0.16), paint);
        canvas.drawLine(Offset(w * 0.66, h * 0.32), Offset(w * 0.5, h * 0.16), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LaneArrowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.tokens.join(';') != tokens.join(';');
}
