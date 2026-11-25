import 'package:flutter/material.dart';

/// Unified Karta Dual-Lighting Design Token Extension derived from `karta_logo.png`
/// and `GEMINI.md`:
/// - [KartaPalette.obsidianNight]: Deep Obsidian (#0D0F12), Charcoal Slate frosted
///   glass (#181C22), Muted Teal (#5B9A94), high-contrast amber/coral alerts.
/// - [KartaPalette.tropicalDaylight]: High-glare warm limestone off-white (#F5F2EB)
///   and crisp alabaster frosted glass (#FCFBF8) engineered for harsh midday
///   equatorial sunlight (e.g., Penang Bridge at noon).
@immutable
class KartaPalette extends ThemeExtension<KartaPalette> {
  const KartaPalette({
    required this.isDaylight,
    required this.backgroundPrimary,
    required this.surfaceCard,
    required this.surfaceElevated,
    required this.surfaceInteractive,
    required this.borderSubtle,
    required this.borderStrong,
    required this.accentPrimary,
    required this.accentBright,
    required this.accentMuted,
    required this.accentGlow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.statusClear,
    required this.statusCaution,
    required this.statusAlert,
    required this.statusInfo,
    required this.hudGlass,
    required this.hudDeepGlass,
    required this.shadowColor,
    required this.signExpresswayBg,
    required this.signExpresswayBorder,
    required this.signFederalBg,
    required this.signFederalBorder,
    required this.signShieldYellow,
    required this.signShieldInk,
    required this.mountainRidgeTint,
  });

  final bool isDaylight;
  final Color backgroundPrimary;
  final Color surfaceCard;
  final Color surfaceElevated;
  final Color surfaceInteractive;
  final Color borderSubtle;
  final Color borderStrong;
  final Color accentPrimary;
  final Color accentBright;
  final Color accentMuted;
  final Color accentGlow;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color statusClear;
  final Color statusCaution;
  final Color statusAlert;
  final Color statusInfo;
  final Color hudGlass;
  final Color hudDeepGlass;
  final Color shadowColor;
  final Color signExpresswayBg;
  final Color signExpresswayBorder;
  final Color signFederalBg;
  final Color signFederalBorder;
  final Color signShieldYellow;
  final Color signShieldInk;
  final Color mountainRidgeTint;

  /// Obsidian Night Mode — low-glare automotive cockpit palette.
  static const KartaPalette obsidianNight = KartaPalette(
    isDaylight: false,
    backgroundPrimary: Color(0xFF0D0F12),
    surfaceCard: Color(0xFF181C22),
    surfaceElevated: Color(0xFF20262F),
    surfaceInteractive: Color(0xFF272F3B),
    borderSubtle: Color(0xFF2B3340),
    borderStrong: Color(0xFF3A4556),
    accentPrimary: Color(0xFF5B9A94),
    accentBright: Color(0xFF74C4BC),
    accentMuted: Color(0xFF3E6E6A),
    accentGlow: Color(0x2E5B9A94),
    textPrimary: Color(0xFFF4F6F8),
    textSecondary: Color(0xFF8E96A0),
    textTertiary: Color(0xFF636B76),
    statusClear: Color(0xFF42B883),
    statusCaution: Color(0xFFF5A623),
    statusAlert: Color(0xFFFF5A52),
    statusInfo: Color(0xFF5A9DF0),
    hudGlass: Color(0xE0181C22),
    hudDeepGlass: Color(0xED0D0F12),
    shadowColor: Color(0x6B000000),
    signExpresswayBg: Color(0xFF006B44),
    signExpresswayBorder: Color(0xFF9FE6C8),
    signFederalBg: Color(0xFF0D4A8C),
    signFederalBorder: Color(0xFF9EC5F8),
    signShieldYellow: Color(0xFFF5C518),
    signShieldInk: Color(0xFF11161C),
    mountainRidgeTint: Color(0xFF3A434D),
  );

  /// High-Glare Tropical Daylight Mode — warm limestone canvas & WCAG AAA ink
  /// crafted for equatorial noon glare (Penang Bridge / PLUS E1 / Singapore ECP).
  static const KartaPalette tropicalDaylight = KartaPalette(
    isDaylight: true,
    backgroundPrimary: Color(0xFFF5F2EB),
    surfaceCard: Color(0xFFFCFBF8),
    surfaceElevated: Color(0xFFEFECE4),
    surfaceInteractive: Color(0xFFE4E0D6),
    borderSubtle: Color(0xFFD5D0C5),
    borderStrong: Color(0xFFA6B0BA),
    accentPrimary: Color(0xFF2F756F),
    accentBright: Color(0xFF1E5C57),
    accentMuted: Color(0xFFD7EAE7),
    accentGlow: Color(0x242F756F),
    textPrimary: Color(0xFF11161C),
    textSecondary: Color(0xFF4A5563),
    textTertiary: Color(0xFF6E7781),
    statusClear: Color(0xFF137D4E),
    statusCaution: Color(0xFFB86B00),
    statusAlert: Color(0xFFC82822),
    statusInfo: Color(0xFF1C5DB0),
    hudGlass: Color(0xE8FCFBF8),
    hudDeepGlass: Color(0xF5FFFFFF),
    shadowColor: Color(0x2B11161C),
    signExpresswayBg: Color(0xFF007A4D),
    signExpresswayBorder: Color(0xFFFFFFFF),
    signFederalBg: Color(0xFF0052A5),
    signFederalBorder: Color(0xFFFFFFFF),
    signShieldYellow: Color(0xFFF5C518),
    signShieldInk: Color(0xFF11161C),
    mountainRidgeTint: Color(0xFF8AA19F),
  );

  @override
  KartaPalette copyWith({
    bool? isDaylight,
    Color? backgroundPrimary,
    Color? surfaceCard,
    Color? surfaceElevated,
    Color? surfaceInteractive,
    Color? borderSubtle,
    Color? borderStrong,
    Color? accentPrimary,
    Color? accentBright,
    Color? accentMuted,
    Color? accentGlow,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? statusClear,
    Color? statusCaution,
    Color? statusAlert,
    Color? statusInfo,
    Color? hudGlass,
    Color? hudDeepGlass,
    Color? shadowColor,
    Color? signExpresswayBg,
    Color? signExpresswayBorder,
    Color? signFederalBg,
    Color? signFederalBorder,
    Color? signShieldYellow,
    Color? signShieldInk,
    Color? mountainRidgeTint,
  }) =>
      KartaPalette(
        isDaylight: isDaylight ?? this.isDaylight,
        backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
        surfaceCard: surfaceCard ?? this.surfaceCard,
        surfaceElevated: surfaceElevated ?? this.surfaceElevated,
        surfaceInteractive: surfaceInteractive ?? this.surfaceInteractive,
        borderSubtle: borderSubtle ?? this.borderSubtle,
        borderStrong: borderStrong ?? this.borderStrong,
        accentPrimary: accentPrimary ?? this.accentPrimary,
        accentBright: accentBright ?? this.accentBright,
        accentMuted: accentMuted ?? this.accentMuted,
        accentGlow: accentGlow ?? this.accentGlow,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        statusClear: statusClear ?? this.statusClear,
        statusCaution: statusCaution ?? this.statusCaution,
        statusAlert: statusAlert ?? this.statusAlert,
        statusInfo: statusInfo ?? this.statusInfo,
        hudGlass: hudGlass ?? this.hudGlass,
        hudDeepGlass: hudDeepGlass ?? this.hudDeepGlass,
        shadowColor: shadowColor ?? this.shadowColor,
        signExpresswayBg: signExpresswayBg ?? this.signExpresswayBg,
        signExpresswayBorder: signExpresswayBorder ?? this.signExpresswayBorder,
        signFederalBg: signFederalBg ?? this.signFederalBg,
        signFederalBorder: signFederalBorder ?? this.signFederalBorder,
        signShieldYellow: signShieldYellow ?? this.signShieldYellow,
        signShieldInk: signShieldInk ?? this.signShieldInk,
        mountainRidgeTint: mountainRidgeTint ?? this.mountainRidgeTint,
      );

  @override
  KartaPalette lerp(covariant ThemeExtension<KartaPalette>? other, double t) {
    if (other is! KartaPalette) return this;
    return KartaPalette(
      isDaylight: t < 0.5 ? isDaylight : other.isDaylight,
      backgroundPrimary: Color.lerp(backgroundPrimary, other.backgroundPrimary, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceInteractive: Color.lerp(surfaceInteractive, other.surfaceInteractive, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentBright: Color.lerp(accentBright, other.accentBright, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      accentGlow: Color.lerp(accentGlow, other.accentGlow, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      statusClear: Color.lerp(statusClear, other.statusClear, t)!,
      statusCaution: Color.lerp(statusCaution, other.statusCaution, t)!,
      statusAlert: Color.lerp(statusAlert, other.statusAlert, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      hudGlass: Color.lerp(hudGlass, other.hudGlass, t)!,
      hudDeepGlass: Color.lerp(hudDeepGlass, other.hudDeepGlass, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      signExpresswayBg: Color.lerp(signExpresswayBg, other.signExpresswayBg, t)!,
      signExpresswayBorder: Color.lerp(signExpresswayBorder, other.signExpresswayBorder, t)!,
      signFederalBg: Color.lerp(signFederalBg, other.signFederalBg, t)!,
      signFederalBorder: Color.lerp(signFederalBorder, other.signFederalBorder, t)!,
      signShieldYellow: Color.lerp(signShieldYellow, other.signShieldYellow, t)!,
      signShieldInk: Color.lerp(signShieldInk, other.signShieldInk, t)!,
      mountainRidgeTint: Color.lerp(mountainRidgeTint, other.mountainRidgeTint, t)!,
    );
  }
}

extension KartaPaletteContext on BuildContext {
  KartaPalette get kartaPalette =>
      Theme.of(this).extension<KartaPalette>() ?? KartaPalette.obsidianNight;

  bool get isKartaDaylight => kartaPalette.isDaylight;
}
