import 'package:flutter/material.dart';

/// Displays the authentic, officially sourced flag image for a Southeast Asian
/// state, federal territory, province, district, or country bundled directly in
/// `packages/karta_design_system/assets/flags/`.
///
/// Every PNG asset is rendered from the official Wikimedia Commons SVG flag
/// (never procedurally generated) and packaged locally for 100% offline use.
class KartaStateFlag extends StatelessWidget {
  const KartaStateFlag({
    super.key,
    required this.flagId,
    this.width = 58,
    this.height = 38,
    this.borderRadius = 8,
  });

  final String flagId;
  final double width;
  final double height;
  final double borderRadius;

  static const Set<String> bundledFlagIds = <String>{
    // Malaysia: National + all 13 States + 3 Federal Territories
    'my',
    'my-penang',
    'my-perak',
    'my-kedah',
    'my-perlis',
    'my-selangor',
    'my-kl',
    'my-putrajaya',
    'my-labuan',
    'my-n9',
    'my-melaka',
    'my-johor',
    'my-pahang',
    'my-terengganu',
    'my-kelantan',
    'my-sarawak',
    'my-sabah',
    // Singapore & Brunei
    'sg',
    'bn',
    // Indonesia: National + major provincial flags
    'id',
    'id-jakarta',
    'id-bali',
    'id-diy',
    'id-jabar',
    'id-jateng',
    'id-jatim',
    'id-sumut',
    'id-kepri',
    'id-kaltim',
    // Thailand: National + major provincial flags
    'th',
    'th-bangkok',
    'th-phuket',
    'th-songkhla',
    'th-ayutthaya',
    'th-chonburi',
    'th-chiangmai',
    // Philippines: National + major city/provincial flags
    'ph',
    'ph-ncr',
    'ph-cebu',
    'ph-bohol',
    'ph-davao',
    // Myanmar: National + regional flags
    'mm',
    'mm-yangon',
    'mm-mandalay',
    // Vietnam, Laos, Cambodia, Timor-Leste
    'vn',
    'la',
    'kh',
    'tl',
  };

  /// Resolves the bundled asset path for [flagId], falling back cleanly to the
  /// 2-letter country code flag if a subdivision flag ID isn't registered.
  static String resolveAssetPath(String flagId) {
    final clean = flagId.trim().toLowerCase();
    if (bundledFlagIds.contains(clean)) {
      return 'assets/flags/$clean.png';
    }
    final prefix = clean.split('-').first;
    if (bundledFlagIds.contains(prefix)) {
      return 'assets/flags/$prefix.png';
    }
    return 'assets/flags/my.png';
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = resolveAssetPath(flagId);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: const Color(0xFF14181F),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(
              assetPath,
              package: 'karta_design_system',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
            // Subtle glass frame & hairline border for dark/light contrast
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                  width: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
