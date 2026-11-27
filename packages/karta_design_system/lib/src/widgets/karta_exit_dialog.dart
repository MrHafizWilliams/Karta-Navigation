import 'package:flutter/material.dart';

import '../i18n/karta_l10n.dart';
import '../icons/karta_logo_mark.dart';
import '../tokens/karta_palette.dart';
import '../tokens/karta_spacing.dart';
import '../tokens/karta_typography.dart';
import 'karta_pointer_shield.dart';
import 'karta_surface_card.dart';

/// Waze-inspired exit confirmation dialog asking the driver to confirm
/// before shutting down live GPS & closing Karta Navigation.
Future<bool> showKartaExitConfirmationDialog(
  BuildContext context, {
  bool isNavigating = false,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss Exit Karta dialog',
    barrierColor: Colors.black.withValues(alpha: 0.62),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return _KartaExitConfirmationModal(isNavigating: isNavigating);
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result == true;
}

class _KartaExitConfirmationModal extends StatelessWidget {
  const _KartaExitConfirmationModal({required this.isNavigating});

  final bool isNavigating;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final l10n = context.kartaStrings;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Material(
            color: Colors.transparent,
            child: KartaPointerShield(
              child: KartaSurfaceCard(
                key: const ValueKey<String>('karta-exit-dialog'),
                deepGlass: true,
                borderRadius: 22,
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Top brand + power ring badge
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: palette.accentGlow,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.accentPrimary.withValues(alpha: 0.45),
                            ),
                          ),
                          child: const KartaLogoMark(size: 46),
                        ),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: palette.statusAlert,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.surfaceCard,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.power_settings_new_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.exitDialogTitle,
                      textAlign: TextAlign.center,
                      style: KartaTypography.sectionTitle.copyWith(
                        fontSize: 19,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isNavigating
                          ? l10n.exitDialogBodyNavigating
                          : l10n.exitDialogBodyExplore,
                      textAlign: TextAlign.center,
                      style: KartaTypography.bodySecondary.copyWith(
                        fontSize: 13.5,
                        height: 1.4,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const ValueKey<String>('karta-exit-cancel-btn'),
                            onPressed: () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, KartaSpacing.minTouchTarget),
                              side: BorderSide(color: palette.borderStrong),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: Icon(
                              Icons.navigation_rounded,
                              size: 18,
                              color: palette.textPrimary,
                            ),
                            label: Text(
                              l10n.exitStay,
                              style: KartaTypography.bodyPrimary.copyWith(
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            key: const ValueKey<String>('karta-exit-confirm-btn'),
                            onPressed: () => Navigator.of(context).pop(true),
                            style: FilledButton.styleFrom(
                              backgroundColor: palette.statusAlert,
                              foregroundColor: onPrimary,
                              minimumSize: const Size(0, KartaSpacing.minTouchTarget),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(
                              Icons.power_settings_new_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            label: Text(
                              l10n.exitConfirm,
                              style: KartaTypography.bodyPrimary.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
