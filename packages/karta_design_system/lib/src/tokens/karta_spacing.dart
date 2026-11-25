/// Spacing, corner radii, and responsive viewport breakpoints for Karta.
abstract final class KartaSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusPill = 999;

  static const double railWidth = 78;
  static const double sidePanelWidth = 408;
  static const double tabletPanelWidth = 372;

  /// Material / WCAG minimum accessible touch target for general interactive controls.
  static const double minTouchTarget = 48.0;

  /// Fitts's Law minimum automotive thumb touch target during active driving.
  static const double minDrivingTouchTarget = 60.0;
}

enum KartaViewportClass {
  /// Smartphones & narrow windows (< 640dp)
  compact,

  /// Tablets & foldables (640dp – 1079dp)
  medium,

  /// Wide laptops, desktops & landscape automotive displays (>= 1080dp)
  expanded,
}

abstract final class KartaBreakpoints {
  static const double mediumMin = 640;
  static const double expandedMin = 1080;

  static KartaViewportClass resolve(double width) {
    if (width >= expandedMin) return KartaViewportClass.expanded;
    if (width >= mediumMin) return KartaViewportClass.medium;
    return KartaViewportClass.compact;
  }
}
