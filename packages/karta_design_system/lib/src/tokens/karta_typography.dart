import 'package:flutter/material.dart';

/// Automotive-grade typographic hierarchy backed by bundled local `.ttf`
/// binaries (`Plus Jakarta Sans` and `JetBrains Mono`) inside
/// `packages/karta_design_system/assets/fonts/` so native iOS, Android,
/// Desktop, and offline Web builds render identically.
///
/// All styles omit an explicit [color] so they automatically inherit the
/// active theme's WCAG AA/AAA foreground or secondary ink (`#F4F6F8`/`#8E96A0`
/// in Obsidian Night and `#11161C`/`#4A5563` in High-Glare Tropical Daylight).
abstract final class KartaTypography {
  static const String _fontPackage = 'karta_design_system';

  static const List<String> _sansFallback = <String>[
    'Plus Jakarta Sans',
    'Inter',
    'Segoe UI',
    'Roboto',
    'sans-serif',
  ];

  static const List<String> _monoFallback = <String>[
    'JetBrains Mono',
    'Cascadia Mono',
    'Consolas',
    'monospace',
  ];

  static const List<FontFeature> tabularFeatures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static const TextStyle hudHero = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    package: _fontPackage,
    fontFamilyFallback: _sansFallback,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.05,
    letterSpacing: -0.8,
    fontFeatures: tabularFeatures,
  );

  static const TextStyle hudTitle = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    package: _fontPackage,
    fontFamilyFallback: _sansFallback,
    fontSize: 21,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.3,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    package: _fontPackage,
    fontFamilyFallback: _sansFallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.15,
  );

  static const TextStyle bodyPrimary = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    package: _fontPackage,
    fontFamilyFallback: _sansFallback,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    package: _fontPackage,
    fontFamilyFallback: _sansFallback,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  static const TextStyle telemetryValue = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    package: _fontPackage,
    fontFamilyFallback: _sansFallback,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.3,
    fontFeatures: tabularFeatures,
  );

  static const TextStyle monoBadge = TextStyle(
    fontFamily: 'JetBrains Mono',
    package: _fontPackage,
    fontFamilyFallback: _monoFallback,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.3,
    fontFeatures: tabularFeatures,
  );

  static const TextStyle captionLabel = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    package: _fontPackage,
    fontFamilyFallback: _sansFallback,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.5,
  );
}
