import 'package:flutter/material.dart';
import '../tokens/karta_colors.dart';
import '../tokens/karta_palette.dart';
import '../tokens/karta_typography.dart';

/// Compact scannable toll gantry badge for route comparison cards (e.g.
/// "PLUS Highway · RM 34.44 · Touch 'n Go RFID", "Penang Bridge · RM 5.74",
/// "Singapore ERP · $3.00").
class KartaTollGantryBadge extends StatelessWidget {
  const KartaTollGantryBadge({
    super.key,
    required this.label,
    required this.formattedCharge,
    required this.badgeKind,
    this.paymentLabel,
    this.crossingTimeLocal,
  });

  final String label;
  final String formattedCharge;
  final String badgeKind;
  final String? paymentLabel;
  final String? crossingTimeLocal;

  static ({IconData icon, Color accent}) _visual(String kind, KartaPalette palette) {
    return switch (kind) {
      'plus_highway' => (icon: Icons.add_road_rounded, accent: palette.accentBright),
      'bridge' => (icon: Icons.architecture_rounded, accent: palette.statusInfo),
      'sg_erp' => (icon: Icons.sensors_rounded, accent: KartaColors.tollErp),
      'border_ciq' => (icon: Icons.public_rounded, accent: palette.statusCaution),
      'brunei_bridge' => (icon: Icons.directions_car_rounded, accent: KartaColors.tollBrunei),
      _ => (icon: Icons.toll_rounded, accent: palette.statusCaution),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final vis = _visual(badgeKind, palette);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.backgroundPrimary.withValues(alpha: palette.isDaylight ? 0.88 : 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: vis.accent.withValues(alpha: palette.isDaylight ? 0.6 : 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(vis.icon, size: 12.5, color: vis.accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: KartaTypography.bodyPrimary.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            formattedCharge,
            style: KartaTypography.monoBadge.copyWith(
              fontSize: 10.5,
              color: vis.accent,
            ),
          ),
          if (paymentLabel != null && paymentLabel!.isNotEmpty) ...<Widget>[
            const SizedBox(width: 5),
            Text(
              '· $paymentLabel',
              style: KartaTypography.bodySecondary.copyWith(
                fontSize: 9.5,
                color: palette.textSecondary,
              ),
            ),
          ],
          if (crossingTimeLocal != null && badgeKind == 'sg_erp') ...<Widget>[
            const SizedBox(width: 4),
            Text(
              '($crossingTimeLocal)',
              style: KartaTypography.monoBadge.copyWith(
                fontSize: 9,
                color: palette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
