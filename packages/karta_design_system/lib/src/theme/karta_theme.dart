import 'package:flutter/material.dart';
import '../tokens/karta_palette.dart';
import '../tokens/karta_spacing.dart';
import '../tokens/karta_typography.dart';

/// Dual-lighting Karta Material 3 themes:
/// - [KartaTheme.dark] (`Obsidian Night Mode`) for low-glare night & tunnel driving
/// - [KartaTheme.tropicalDaylight] / [KartaTheme.light] (`High-Glare Tropical Daylight Mode`)
///   engineered for bright equatorial noon sunlight (e.g., Penang Bridge at 12:30 PM).
abstract final class KartaTheme {
  static ThemeData dark() => _build(KartaPalette.obsidianNight, Brightness.dark);

  static ThemeData tropicalDaylight() =>
      _build(KartaPalette.tropicalDaylight, Brightness.light);

  static ThemeData light() => tropicalDaylight();

  static ThemeData _build(KartaPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: p.accentPrimary,
      onPrimary: isDark ? p.backgroundPrimary : const Color(0xFFFFFFFF),
      primaryContainer: p.accentMuted,
      onPrimaryContainer: p.textPrimary,
      secondary: p.accentBright,
      onSecondary: isDark ? p.backgroundPrimary : const Color(0xFFFFFFFF),
      surface: p.surfaceCard,
      onSurface: p.textPrimary,
      surfaceContainerHighest: p.surfaceElevated,
      outline: p.borderSubtle,
      outlineVariant: p.borderStrong,
      error: p.statusAlert,
      onError: const Color(0xFFFFFFFF),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: <ThemeExtension<dynamic>>[p],
      scaffoldBackgroundColor: p.backgroundPrimary,
      canvasColor: p.backgroundPrimary,
      cardColor: p.surfaceCard,
      dividerColor: p.borderSubtle,
      iconTheme: IconThemeData(color: p.textPrimary),
      textTheme: TextTheme(
        displaySmall: KartaTypography.hudHero.copyWith(color: p.textPrimary),
        headlineSmall: KartaTypography.hudTitle.copyWith(color: p.textPrimary),
        titleMedium: KartaTypography.sectionTitle.copyWith(color: p.textPrimary),
        bodyMedium: KartaTypography.bodyPrimary.copyWith(color: p.textPrimary),
        bodySmall: KartaTypography.bodySecondary.copyWith(color: p.textSecondary),
        labelSmall: KartaTypography.captionLabel.copyWith(color: p.textSecondary),
      ),
      cardTheme: CardThemeData(
        color: p.surfaceCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KartaSpacing.radiusMd),
          side: BorderSide(color: p.borderSubtle, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceElevated,
        hintStyle: KartaTypography.bodySecondary.copyWith(color: p.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KartaSpacing.radiusSm),
          borderSide: BorderSide(color: p.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KartaSpacing.radiusSm),
          borderSide: BorderSide(color: p.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KartaSpacing.radiusSm),
          borderSide: BorderSide(color: p.accentPrimary, width: 1.7),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accentPrimary,
          foregroundColor: isDark ? p.backgroundPrimary : const Color(0xFFFFFFFF),
          textStyle: KartaTypography.bodyPrimary.copyWith(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KartaSpacing.radiusSm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KartaSpacing.radiusSm),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceElevated,
        selectedColor: p.accentGlow,
        labelStyle: KartaTypography.bodySecondary.copyWith(color: p.textPrimary),
        side: BorderSide(color: p.borderSubtle),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KartaSpacing.radiusPill),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accentPrimary,
        inactiveTrackColor: p.borderStrong,
        thumbColor: isDark ? p.textPrimary : p.accentPrimary,
        overlayColor: p.accentGlow,
        trackHeight: 3.5,
      ),
    );
  }
}
