import 'package:flutter/material.dart';
import '../icons/karta_maneuver_icon.dart';
import '../tokens/karta_palette.dart';
import '../tokens/karta_spacing.dart';
import '../tokens/karta_typography.dart';
import 'karta_payment_badge.dart';
import 'karta_surface_card.dart';

enum KartaSignboardType {
  /// Malaysian LLM (E1–E38), Singapore LTA (CTE/PIE/AYE/ECP/BKE/SLE/KJE/TPE/MCE/KPE),
  /// and Brunei expressways -> Emerald Highway Green.
  expresswayGreen,

  /// Malaysian Federal Routes (FT1, 2, 6), municipal streets, and Singapore/Brunei arterials -> Federal Cobalt Blue.
  federalBlue,
}

/// Realistic color-coded MY / SG / BN gantry signboard modeled after LLM / LTA / JKR
/// highway signage (Emerald Green for Expressways, Cobalt Blue for Federal/Municipal roads)
/// with Malaysian hexagonal yellow route shields & Singapore expressway pills.
class KartaHighwaySignboard extends StatelessWidget {
  const KartaHighwaySignboard({
    super.key,
    required this.valhallaManeuverType,
    required this.distanceText,
    required this.primaryInstruction,
    this.roadRef,
    this.highwayClass,
    this.countryCode = 'MY',
    this.isTollRoad = false,
    this.exitLabel,
  });

  final int valhallaManeuverType;
  final String distanceText;
  final String primaryInstruction;
  final String? roadRef;
  final String? highwayClass;
  final String countryCode;
  final bool isTollRoad;
  final String? exitLabel;

  static final RegExp _myExpresswayRe = RegExp(r'\bE\d{1,2}\b', caseSensitive: false);
  static final RegExp _sgExpresswayRe =
      RegExp(r'\b(CTE|PIE|AYE|ECP|BKE|SLE|KJE|TPE|MCE|KPE|NSC)\b', caseSensitive: false);

  /// Classifies whether the current/upcoming road merits Expressway Green or Federal Blue signage.
  static KartaSignboardType classifyRoad({
    String? roadRef,
    String? highwayClass,
    String? instruction,
    bool isTollRoad = false,
  }) {
    final hw = (highwayClass ?? '').toLowerCase();
    final ref = roadRef ?? '';
    final inst = (instruction ?? '').toLowerCase();
    if (isTollRoad ||
        hw == 'motorway' ||
        hw == 'motorway_link' ||
        _myExpresswayRe.hasMatch(ref) ||
        _sgExpresswayRe.hasMatch(ref) ||
        _myExpresswayRe.hasMatch(instruction ?? '') ||
        _sgExpresswayRe.hasMatch(instruction ?? '') ||
        inst.contains('expressway') ||
        inst.contains('lebuhraya') ||
        inst.contains('plus') ||
        inst.contains('highway')) {
      return KartaSignboardType.expresswayGreen;
    }
    return KartaSignboardType.federalBlue;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final signType = classifyRoad(
      roadRef: roadRef,
      highwayClass: highwayClass,
      instruction: primaryInstruction,
      isTollRoad: isTollRoad,
    );
    final isExpressway = signType == KartaSignboardType.expresswayGreen;
    final bgColor = isExpressway ? palette.signExpresswayBg : palette.signFederalBg;
    final borderColor = isExpressway ? palette.signExpresswayBorder : palette.signFederalBorder;
    final cleanRef = roadRef?.trim();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(KartaSpacing.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92), width: 2.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.shadowColor,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(2.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(KartaSpacing.radiusLg - 3),
          border: Border.all(color: borderColor.withValues(alpha: 0.45), width: 1),
        ),
        child: Row(
          children: <Widget>[
            // 60x60dp high-contrast directional maneuver glyph plate
            Container(
              width: KartaSpacing.minDrivingTouchTarget,
              height: KartaSpacing.minDrivingTouchTarget,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
              ),
              child: KartaManeuverIcon(
                valhallaType: valhallaManeuverType,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(
                              distanceText,
                              style: KartaTypography.hudHero.copyWith(
                                fontSize: 28,
                                color: Colors.white,
                              ),
                            ),
                            if (cleanRef != null && cleanRef.isNotEmpty)
                              _RegionalRouteShield(
                                roadRef: cleanRef,
                                countryCode: countryCode,
                                isExpressway: isExpressway,
                                yellowFill: palette.signShieldYellow,
                                inkColor: palette.signShieldInk,
                              ),
                            if (exitLabel != null && exitLabel!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  exitLabel!.toUpperCase(),
                                  style: KartaTypography.monoBadge.copyWith(
                                    color: bgColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
                        ),
                        child: Text(
                          isExpressway ? 'EXPRESSWAY' : 'FEDERAL',
                          style: KartaTypography.monoBadge.copyWith(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    primaryInstruction,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: KartaTypography.hudTitle.copyWith(
                      fontSize: 17,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Authentic official Southeast Asian route shields for Turn-by-Turn HUD:
/// - Malaysia (`MY`) & Brunei (`BN`): JKR yellow pointed hexagon (`E1`, `E36`, `6`, `P15`)
/// - Singapore (`SG`): LTA emerald green rounded shield (`CTE`, `PIE`, `AYE`)
/// - Indonesia (`ID`): PM 13/2014 red-and-white Jalan Nasional hexagon / green Jalan Tol hexagon
/// - Thailand (`TH`): DOH white Garuda-crest highway shield / blue tricolor motorway shield
/// - Philippines (`PH`): DPWH white pointed pentagon (`N1`) / yellow expressway shield (`E1`, `NLEX`)
/// - Vietnam (`VN`): QCVN 41 fluorescent yellow expressway (`CT.01`) / white national (`QL.1A`)
/// - Myanmar (`MM`): RTAD emerald green highway shield (`E1`, `NH1`)
/// - ASEAN Highway (`AH*`): Royal blue white-bordered shield (`AH1`, `AH2`, `AH26`)
class _RegionalRouteShield extends StatelessWidget {
  const _RegionalRouteShield({
    required this.roadRef,
    required this.countryCode,
    required this.isExpressway,
    required this.yellowFill,
    required this.inkColor,
  });

  final String roadRef;
  final String countryCode;
  final bool isExpressway;
  final Color yellowFill;
  final Color inkColor;

  @override
  Widget build(BuildContext context) {
    final normalized = roadRef.trim().toUpperCase();
    final cc = countryCode.toUpperCase();

    if (normalized.startsWith('AH')) {
      return _rectShield(
        label: normalized,
        bg: const Color(0xFF003DA5),
        border: Colors.white,
        textColor: Colors.white,
      );
    }

    if (cc == 'SG') {
      return _rectShield(
        label: normalized,
        bg: isExpressway ? const Color(0xFF006B44) : Colors.white,
        border: isExpressway ? Colors.white : inkColor,
        textColor: isExpressway ? Colors.white : inkColor,
      );
    }

    if (cc == 'VN' || normalized.startsWith('CT') || normalized.startsWith('QL')) {
      final isVnExp = isExpressway || normalized.startsWith('CT') || normalized.startsWith('ĐCT');
      return _rectShield(
        label: normalized,
        bg: isVnExp ? const Color(0xFFF5E600) : Colors.white,
        border: inkColor,
        textColor: inkColor,
      );
    }

    if (cc == 'MM' || normalized.startsWith('NH')) {
      return _rectShield(
        label: normalized,
        bg: const Color(0xFF006B3F),
        border: Colors.white,
        textColor: Colors.white,
      );
    }

    if (cc == 'TL') {
      final isSec = normalized.startsWith('B');
      return _rectShield(
        label: normalized,
        bg: isSec ? const Color(0xFF004B8D) : const Color(0xFF006B44),
        border: Colors.white,
        textColor: Colors.white,
      );
    }

    if (cc == 'LA') {
      if (isExpressway || normalized.startsWith('E')) {
        return _rectShield(
          label: normalized,
          bg: const Color(0xFF007A3D),
          border: Colors.white,
          textColor: Colors.white,
        );
      }
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFCE1126), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(height: 4, width: 32, color: const Color(0xFFCE1126)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                normalized,
                style: KartaTypography.monoBadge.copyWith(
                  color: inkColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (cc == 'KH') {
      if (isExpressway || normalized.startsWith('E')) {
        return _rectShield(
          label: normalized,
          bg: const Color(0xFF006B3F),
          border: const Color(0xFFFFD100),
          textColor: Colors.white,
        );
      }
      return CustomPaint(
        painter: const _CambodiaShieldPainter(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
          child: Text(
            normalized,
            style: KartaTypography.monoBadge.copyWith(
              color: const Color(0xFF032EA1),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ),
      );
    }

    if (cc == 'PH') {
      final isPhExp = isExpressway || normalized.startsWith('E');
      if (isPhExp) {
        return _rectShield(
          label: normalized,
          bg: const Color(0xFFFFD100),
          border: inkColor,
          textColor: inkColor,
        );
      }
      return CustomPaint(
        painter: _PhilippinesPentagonPainter(inkColor: inkColor),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 5),
          child: Text(
            normalized,
            style: KartaTypography.monoBadge.copyWith(
              color: inkColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ),
      );
    }

    if (cc == 'TH') {
      if (isExpressway || normalized.startsWith('M')) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0047AB),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white, width: 1.4),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(height: 3.5, width: 32, color: const Color(0xFFCE1126)),
              Container(height: 1.5, width: 32, color: Colors.white),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  normalized,
                  style: KartaTypography.monoBadge.copyWith(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 3, 8, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: inkColor, width: 1.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 12,
              height: 3.5,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFB91C1C),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Text(
              normalized,
              style: KartaTypography.monoBadge.copyWith(
                color: inkColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
          ],
        ),
      );
    }

    if (cc == 'ID') {
      final isTol = isExpressway || normalized.startsWith('TOL');
      return CustomPaint(
        painter: _MalaysianJkrHexagonPainter(
          fillColor: isTol ? const Color(0xFF006B44) : Colors.white,
          innerBorderColor: isTol ? const Color(0xFFFFD100) : inkColor,
          outerRimColor: isTol ? Colors.white : const Color(0xFFD61F26),
          outerRimWidth: 1.7,
          topBannerColor: isTol ? null : const Color(0xFFD61F26),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(11, isTol ? 6 : 8, 11, 5),
          child: Text(
            normalized,
            style: KartaTypography.monoBadge.copyWith(
              color: isTol ? Colors.white : inkColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ),
      );
    }

    // Authentic Malaysian JKR / LLM & Brunei vertical-walled pointed-top-and-bottom hexagon:
    final isMyExpressway = isExpressway || normalized.startsWith('E');
    return CustomPaint(
      painter: _MalaysianJkrHexagonPainter(
        fillColor: yellowFill,
        innerBorderColor: inkColor,
        outerRimColor: isMyExpressway
            ? const Color(0xFF006B44)
            : const Color(0xFF0B3D6B),
        outerRimWidth: isMyExpressway ? 1.6 : 1.0,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Text(
          normalized,
          style: KartaTypography.monoBadge.copyWith(
            color: inkColor,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _rectShield({
    required String label,
    required Color bg,
    required Color border,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Text(
        label,
        style: KartaTypography.monoBadge.copyWith(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}

class _PhilippinesPentagonPainter extends CustomPainter {
  const _PhilippinesPentagonPainter({required this.inkColor});

  final Color inkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.8);
    final roofY = rect.top + rect.height * 0.28;
    final path = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right, roofY)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, roofY)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..color = inkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _PhilippinesPentagonPainter oldDelegate) =>
      oldDelegate.inkColor != inkColor;
}

class _CambodiaShieldPainter extends CustomPainter {
  const _CambodiaShieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.8);
    final shoulderY = rect.bottom - rect.height * 0.28;
    final path = Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, shoulderY)
      ..lineTo(rect.center.dx, rect.bottom)
      ..lineTo(rect.left, shoulderY)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 3.5),
      Paint()..color = const Color(0xFF032EA1),
    );
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF032EA1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CambodiaShieldPainter oldDelegate) => false;
}

class _MalaysianJkrHexagonPainter extends CustomPainter {
  const _MalaysianJkrHexagonPainter({
    required this.fillColor,
    required this.innerBorderColor,
    required this.outerRimColor,
    this.outerRimWidth = 1.4,
    this.topBannerColor,
  });

  final Color fillColor;
  final Color innerBorderColor;
  final Color outerRimColor;
  final double outerRimWidth;
  final Color? topBannerColor;

  Path _buildRoundedJkrHexPath(Rect rect, double cornerRadius) {
    final cx = rect.center.dx;
    final roofDrop = (rect.height * 0.22).clamp(3.0, 7.0);
    final pts = <Offset>[
      Offset(cx, rect.top),
      Offset(rect.right, rect.top + roofDrop),
      Offset(rect.right, rect.bottom - roofDrop),
      Offset(cx, rect.bottom),
      Offset(rect.left, rect.bottom - roofDrop),
      Offset(rect.left, rect.top + roofDrop),
    ];

    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      final prev = pts[(i - 1 + pts.length) % pts.length];
      final curr = pts[i];
      final next = pts[(i + 1) % pts.length];
      final v1 = prev - curr;
      final v2 = next - curr;
      final len1 = v1.distance == 0 ? 1.0 : v1.distance;
      final len2 = v2.distance == 0 ? 1.0 : v2.distance;
      final r = cornerRadius.clamp(0.0, (len1 < len2 ? len1 : len2) * 0.34);
      final start = curr + (v1 / len1) * r;
      final end = curr + (v2 / len2) * r;
      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      path.quadraticBezierTo(curr.dx, curr.dy, end.dx, end.dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final outerRect = Offset.zero & size;
    final outerPath = _buildRoundedJkrHexPath(outerRect.deflate(0.8), 2.2);

    canvas.drawPath(
      outerPath,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );
    if (topBannerColor != null) {
      canvas.save();
      canvas.clipPath(outerPath);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height * 0.30),
        Paint()..color = topBannerColor!,
      );
      canvas.restore();
    }
    canvas.drawPath(
      outerPath,
      Paint()
        ..color = outerRimColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerRimWidth,
    );

    final innerRect = outerRect.deflate(2.8);
    if (innerRect.width > 6 && innerRect.height > 6) {
      final innerPath = _buildRoundedJkrHexPath(innerRect, 1.4);
      canvas.drawPath(
        innerPath,
        Paint()
          ..color = innerBorderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MalaysianJkrHexagonPainter oldDelegate) =>
      oldDelegate.fillColor != fillColor ||
      oldDelegate.innerBorderColor != innerBorderColor ||
      oldDelegate.outerRimColor != outerRimColor ||
      oldDelegate.outerRimWidth != outerRimWidth;
}

class KartaAnimatedLaneSpec {
  const KartaAnimatedLaneSpec({
    required this.laneSpec,
    required this.isRecommended,
  });

  final String laneSpec;
  final bool isRecommended;
}

/// Animated lane-guidance strip featuring forward-pulsing recommended lane arrows
/// paired seamlessly with approaching MY RFID / SmartTAG / TnG / SG ERP 2.0 toll lanes.
class KartaAnimatedLaneGuidanceStrip extends StatefulWidget {
  const KartaAnimatedLaneGuidanceStrip({
    super.key,
    required this.lanes,
    this.tollBannerText,
    this.tollPaymentCodes = const <String>[],
  });

  final List<KartaAnimatedLaneSpec> lanes;
  final String? tollBannerText;
  final List<String> tollPaymentCodes;

  @override
  State<KartaAnimatedLaneGuidanceStrip> createState() =>
      _KartaAnimatedLaneGuidanceStripState();
}

class _KartaAnimatedLaneGuidanceStripState extends State<KartaAnimatedLaneGuidanceStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final hasToll = widget.tollBannerText != null && widget.tollBannerText!.isNotEmpty;

    return KartaSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderRadius: 12,
      deepGlass: true,
      borderColor: hasToll ? palette.statusCaution : palette.accentPrimary.withValues(alpha: 0.7),
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, _) {
          final wave = _pulseCtrl.value;
          // Subtle upward lift (-2.5dp -> 0dp) + luminous glow pulse for active lanes
          final dy = -2.8 * (0.5 - (wave - 0.5).abs()) * 2.0;
          final glowAlpha = 0.16 + 0.22 * (1.0 - (wave - 0.5).abs() * 2.0);

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.lanes.isNotEmpty)
                for (var i = 0; i < widget.lanes.length; i++) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.lanes[i].isRecommended
                          ? palette.accentPrimary.withValues(alpha: glowAlpha)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.lanes[i].isRecommended
                            ? palette.accentPrimary
                            : palette.borderSubtle,
                        width: widget.lanes[i].isRecommended ? 1.5 : 1.0,
                      ),
                    ),
                    child: Transform.translate(
                      offset: widget.lanes[i].isRecommended ? Offset(0, dy) : Offset.zero,
                      child: KartaLaneArrow(
                        laneSpec: widget.lanes[i].laneSpec,
                        isRecommended: widget.lanes[i].isRecommended,
                        size: 22,
                      ),
                    ),
                  ),
                  if (i < widget.lanes.length - 1) const SizedBox(width: 5),
                ],
              if (hasToll) ...<Widget>[
                if (widget.lanes.isNotEmpty) const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        widget.tollBannerText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KartaTypography.monoBadge.copyWith(
                          fontSize: 11,
                          color: palette.statusCaution,
                        ),
                      ),
                      if (widget.tollPaymentCodes.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 4,
                          runSpacing: 3,
                          children: <Widget>[
                            for (final code in widget.tollPaymentCodes.take(4))
                              KartaPaymentBadge(methodCode: code, compact: true),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
