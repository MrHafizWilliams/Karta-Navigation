import 'package:flutter/material.dart';

import '../i18n/karta_l10n.dart';
import '../tokens/karta_palette.dart';
import '../tokens/karta_typography.dart';
import 'karta_pointer_shield.dart';
import 'karta_state_flag.dart';
import 'karta_surface_card.dart';

/// Sleek animated border-crossing greeting pill shown whenever the user enters
/// a new state, federal territory, province, or district across Southeast Asia.
class KartaRegionWelcomeBanner extends StatelessWidget {
  const KartaRegionWelcomeBanner({
    super.key,
    required this.flagId,
    required this.regionName,
    required this.countryName,
    this.localName,
    this.tagline,
    this.onDismiss,
  });

  final String flagId;
  final String regionName;
  final String countryName;
  final String? localName;
  final String? tagline;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final l10n = context.kartaStrings;
    final displayRegion = (l10n.language == KartaLanguage.malay &&
            localName != null &&
            localName!.isNotEmpty)
        ? localName!
        : regionName;

    final subtitleParts = <String>[
      countryName,
      if (tagline != null && tagline!.isNotEmpty) tagline!,
    ];

    return KartaPointerShield(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: KartaSurfaceCard(
          key: const ValueKey<String>('karta-region-welcome-banner'),
          deepGlass: true,
          borderRadius: 18,
          borderColor: palette.accentPrimary.withValues(alpha: 0.65),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              KartaStateFlag(
                key: ValueKey<String>('karta-region-flag-$flagId'),
                flagId: flagId,
                width: 58,
                height: 38,
                borderRadius: 8,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.formatWelcomeToRegion(displayRegion),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KartaTypography.sectionTitle.copyWith(
                        fontSize: 14.5,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KartaTypography.bodySecondary.copyWith(
                        fontSize: 11.5,
                        color: palette.accentBright,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDismiss != null) ...<Widget>[
                const SizedBox(width: 6),
                IconButton(
                  key: const ValueKey<String>('karta-region-welcome-close'),
                  tooltip: l10n.dismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 17,
                    color: palette.textSecondary,
                  ),
                  onPressed: onDismiss,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
