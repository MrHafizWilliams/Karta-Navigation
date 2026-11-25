import 'package:flutter/material.dart';
import '../tokens/karta_colors.dart';
import '../tokens/karta_palette.dart';
import '../tokens/karta_typography.dart';

/// Crisp regional toll payment chip for MY (RFID / SmartTAG / TnG / Open Payment / ANPR),
/// SG (ERP / ERP 2.0 OBU), and BN (Brunei Toll Card / Cash).
class KartaPaymentBadge extends StatelessWidget {
  const KartaPaymentBadge({
    super.key,
    required this.methodCode,
    this.active = true,
    this.compact = false,
  });

  final String methodCode;
  final bool active;
  final bool compact;

  static ({String label, Color color}) _meta(String code, KartaPalette palette) {
    return switch (code.toUpperCase()) {
      'RFID' => (label: 'RFID', color: KartaColors.tollRfid),
      'SMARTTAG' => (label: 'SmartTAG', color: palette.statusCaution),
      'TNG_CARD' => (label: 'TnG', color: palette.statusInfo),
      'OPEN_PAYMENT_CARD' => (label: 'Card/Pay', color: palette.statusClear),
      'ANPR_JUSTGO' => (label: 'ANPR', color: palette.accentBright),
      'ERP_IU' => (label: 'ERP IU', color: KartaColors.tollErp),
      'ERP2_OBU' => (label: 'ERP 2.0', color: KartaColors.tollErp),
      'BRUNEI_TOLL_CARD' => (label: 'BN Card', color: KartaColors.tollBrunei),
      'CASH' => (label: 'Cash', color: palette.textSecondary),
      _ => (label: code, color: palette.textSecondary),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final meta = _meta(methodCode, palette);
    final fg = active ? meta.color : palette.textSecondary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: active ? meta.color.withValues(alpha: palette.isDaylight ? 0.14 : 0.16) : palette.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: active ? meta.color.withValues(alpha: 0.58) : palette.borderSubtle,
        ),
      ),
      child: Text(
        meta.label,
        style: KartaTypography.monoBadge.copyWith(
          fontSize: compact ? 9.5 : 10.5,
          color: fg,
        ),
      ),
    );
  }
}
