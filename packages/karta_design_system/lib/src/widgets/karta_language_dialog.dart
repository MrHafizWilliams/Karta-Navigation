import 'package:flutter/material.dart';

import '../i18n/karta_l10n.dart';
import '../tokens/karta_palette.dart';
import '../tokens/karta_spacing.dart';
import '../tokens/karta_typography.dart';
import 'karta_pointer_shield.dart';
import 'karta_surface_card.dart';

/// Shows Karta's sleek 11-language Southeast Asia selector modal.
Future<KartaLanguage?> showKartaLanguageDialog(
  BuildContext context, {
  required KartaLanguage currentLanguage,
}) {
  return showGeneralDialog<KartaLanguage>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss Language Selector',
    barrierColor: Colors.black.withValues(alpha: 0.62),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return _KartaLanguagePickerModal(currentLanguage: currentLanguage);
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _KartaLanguagePickerModal extends StatelessWidget {
  const _KartaLanguagePickerModal({required this.currentLanguage});

  final KartaLanguage currentLanguage;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final l10n = KartaStrings.of(currentLanguage);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620),
          child: Material(
            color: Colors.transparent,
            child: KartaPointerShield(
              child: KartaSurfaceCard(
                key: const ValueKey<String>('karta-language-dialog'),
                deepGlass: true,
                borderRadius: 22,
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: palette.accentGlow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: palette.accentPrimary.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Icon(
                              Icons.translate_rounded,
                              size: 20,
                              color: palette.accentBright,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  l10n.selectLanguageTitle,
                                  style: KartaTypography.sectionTitle.copyWith(
                                    fontSize: 17,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l10n.selectLanguageSubtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: KartaTypography.bodySecondary.copyWith(
                                    fontSize: 12,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.dismiss,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.close_rounded,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: palette.borderSubtle),
                    // Scrollable 11-Language List
                    Flexible(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        shrinkWrap: true,
                        itemCount: KartaLanguage.values.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, idx) {
                          final lang = KartaLanguage.values[idx];
                          final selected = lang == currentLanguage;
                          return InkWell(
                            key: ValueKey<String>('karta-lang-option-${lang.code}'),
                            onTap: () => Navigator.of(context).pop(lang),
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? palette.accentGlow
                                    : palette.surfaceElevated.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? palette.accentPrimary
                                      : palette.borderSubtle,
                                  width: selected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 40,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? palette.accentPrimary
                                          : palette.surfaceCard,
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: selected
                                            ? palette.accentBright
                                            : palette.borderStrong,
                                      ),
                                    ),
                                    child: Text(
                                      lang.shortBadge,
                                      style: KartaTypography.monoBadge.copyWith(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: selected
                                            ? Colors.white
                                            : palette.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          lang.nativeName,
                                          style: KartaTypography.bodyPrimary.copyWith(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: palette.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          '${lang.englishName} · ${lang.regionHint}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: KartaTypography.bodySecondary.copyWith(
                                            fontSize: 11.5,
                                            color: palette.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 20,
                                      color: palette.accentBright,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: KartaSpacing.xs),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
