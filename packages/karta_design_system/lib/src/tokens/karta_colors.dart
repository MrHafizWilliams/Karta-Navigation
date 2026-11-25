import 'package:flutter/material.dart';

/// Canonical Karta Brand & Automotive HUD Color Palette (derived from GEMINI.md)
/// kept strictly synchronized with [KartaPalette.obsidianNight].
abstract final class KartaColors {
  // Core Brand Surfaces
  static const Color backgroundPrimary = Color(0xFF0D0F12); // Deep Obsidian
  static const Color surfaceCard = Color(0xFF181C22); // Charcoal Slate
  static const Color surfaceElevated = Color(0xFF20262F);
  static const Color surfaceInteractive = Color(0xFF272F3B);
  static const Color borderSubtle = Color(0xFF2B3340);
  static const Color borderStrong = Color(0xFF3A4556);

  // Brand Accent (Karta Muted Teal)
  static const Color accentPrimary = Color(0xFF5B9A94);
  static const Color accentBright = Color(0xFF74C4BC);
  static const Color accentMuted = Color(0xFF3E6E6A);
  static const Color accentGlow = Color(0x2E5B9A94);

  // Typography
  static const Color textPrimary = Color(0xFFF4F6F8); // Crisp Off-White
  static const Color textSecondary = Color(0xFF8E96A0); // Steel Gray
  static const Color textTertiary = Color(0xFF636B76);

  // Automotive Semantic Telemetry
  static const Color statusClear = Color(0xFF42B883); // Free flow / clear route
  static const Color statusCaution = Color(0xFFF5A623); // +1..9 km/h over limit / caution
  static const Color statusAlert = Color(0xFFFF5A52); // >= +10 km/h overspeed / AWAS camera
  static const Color statusInfo = Color(0xFF5A9DF0); // Transit / EV fast charger

  // Legacy regional accent aliases retained for package API compatibility
  static const Color tollRfid = Color(0xFF5B9A94);
  static const Color tollSmartTag = Color(0xFF4F8CE0);
  static const Color tollTng = Color(0xFF3B82F6);
  static const Color tollErp = Color(0xFFF5A623);
  static const Color tollBrunei = Color(0xFFD4AF37);

  // Glassmorphic HUD fills
  static const Color hudGlass = Color(0xE0181C22);
  static const Color hudDeepGlass = Color(0xED0D0F12);
}
