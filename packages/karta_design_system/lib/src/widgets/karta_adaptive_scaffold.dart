import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../i18n/karta_l10n.dart';
import '../icons/karta_logo_mark.dart';
import '../tokens/karta_palette.dart';
import '../tokens/karta_spacing.dart';
import '../tokens/karta_typography.dart';
import 'karta_pointer_shield.dart';
import 'karta_surface_card.dart';

class KartaNavRailItem {
  const KartaNavRailItem({
    required this.id,
    required this.label,
    required this.icon,
    this.badgeCount = 0,
  });

  final String id;
  final String label;
  final IconData icon;
  final int badgeCount;
}

/// Theme-aware responsive scaffold adapting Karta's full-bleed 3D map and HUD
/// across smartphones (Compact < 640dp), tablets & standard automotive head units
/// (Medium 640–1079dp), and desktops & wide automotive displays (Expanded >= 1080dp):
/// - Smartphones (< 640dp): distinct mobile layout with compact bottom tab bar
///   and spring-physics 3-state draggable active navigation sheet.
/// - Tablets, Standard Automotive, Desktop & Wide Automotive (>= 640dp): persistent
///   left `_DesktopNavRail` + collapsible glassmorphic side panel.
/// - Structurally prevents HUD overlaps via unified vertical stacks (bottom-left
///   hazard + speed cluster; compact active-nav top maneuver + horizontal utility bar).
class KartaAdaptiveScaffold extends StatefulWidget {
  const KartaAdaptiveScaffold({
    super.key,
    required this.mapLayer,
    required this.navItems,
    required this.selectedNavId,
    required this.onSelectNav,
    this.sidePanel,
    this.topSearchOverlay,
    this.topWelcomeOverlay,
    this.topHudOverlay,
    this.topRightControls,
    this.topRightControlsHorizontal,
    this.cornerHazardOverlay,
    this.floatingRightOverlay,
    this.bottomLeftOverlay,
    this.bottomCenterOverlay,
    this.bottomVoiceWaveformOverlay,
    this.bottomRightOverlay,
    this.mobileActiveSheetOverlay,
    this.mobileSheetExpanded = false,
    this.mobileExploreExpanded,
    this.onToggleMobileExplore,
    this.mobileExploreCollapsedSubtitle,
    this.onOpenLanguage,
    this.languageBadge,
    this.languageTooltip,
    this.onOpenProfile,
    this.isProfileSignedIn = false,
    this.profileInitials,
    this.profileTooltip,
    this.onRequestExit,
    this.companionOverlay,
    this.modalOverlay,
    this.hideSidePanel = false,
    this.sidebarCollapsed = false,
    this.onToggleSidebar,
  });

  final Widget mapLayer;
  final List<KartaNavRailItem> navItems;
  final String selectedNavId;
  final ValueChanged<String> onSelectNav;
  final Widget? sidePanel;

  /// Google Maps-style floating top search pill + category chips strip shown
  /// over the open map on desktop/tablet/automotive explore mode.
  final Widget? topSearchOverlay;

  /// Animated border-crossing welcome toast with state/district flag.
  final Widget? topWelcomeOverlay;
  final Widget? topHudOverlay;
  final Widget? topRightControls;

  /// Compact horizontal variant of [topRightControls] used automatically on
  /// short automotive head units (`height <= 620dp`) and below the mobile
  /// active-navigation maneuver banner so zero overlap can ever occur.
  final Widget? topRightControlsHorizontal;

  final Widget? cornerHazardOverlay;
  final Widget? floatingRightOverlay;
  final Widget? bottomLeftOverlay;
  final Widget? bottomCenterOverlay;
  final Widget? bottomVoiceWaveformOverlay;
  final Widget? bottomRightOverlay;
  final Widget? mobileActiveSheetOverlay;
  final bool mobileSheetExpanded;

  /// Controls whether the compact smartphone explore sheet is expanded or
  /// minimized into a sleek compact search pill so drivers see the full map.
  /// Defaults to minimized (`false`) on smartphones.
  final bool? mobileExploreExpanded;
  final VoidCallback? onToggleMobileExplore;
  final String? mobileExploreCollapsedSubtitle;

  /// 11-language SEA switcher button rendered in the left rail & mobile explore bar.
  final VoidCallback? onOpenLanguage;
  final String? languageBadge;
  final String? languageTooltip;

  /// Profile icon rendered in the left navigation rail footer directly above Exit.
  final VoidCallback? onOpenProfile;
  final bool isProfileSignedIn;
  final String? profileInitials;
  final String? profileTooltip;

  /// Optional Waze-style exit callback exposed in the navigation rail footer.
  final VoidCallback? onRequestExit;

  final Widget? companionOverlay;
  final Widget? modalOverlay;
  final bool hideSidePanel;
  final bool sidebarCollapsed;
  final VoidCallback? onToggleSidebar;

  @override
  State<KartaAdaptiveScaffold> createState() => _KartaAdaptiveScaffoldState();
}

class _KartaAdaptiveScaffoldState extends State<KartaAdaptiveScaffold> {
  bool _internalCollapsed = false;
  bool _internalMobileExploreExpanded = false;

  bool get _isCollapsed =>
      widget.onToggleSidebar != null ? widget.sidebarCollapsed : _internalCollapsed;

  bool get _isMobileExploreExpanded =>
      widget.mobileExploreExpanded ?? _internalMobileExploreExpanded;

  void _toggleSidebar() {
    if (widget.onToggleSidebar != null) {
      widget.onToggleSidebar!();
    } else {
      setState(() => _internalCollapsed = !_internalCollapsed);
    }
  }

  void _toggleMobileExplore() {
    if (widget.onToggleMobileExplore != null) {
      widget.onToggleMobileExplore!();
    } else {
      setState(() => _internalMobileExploreExpanded = !_internalMobileExploreExpanded);
    }
  }

  void _setMobileExploreExpanded(bool expanded) {
    if (_isMobileExploreExpanded == expanded) return;
    _toggleMobileExplore();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = KartaBreakpoints.resolve(constraints.maxWidth);
        final safe = MediaQuery.paddingOf(context);
        final isExpanded = viewport == KartaViewportClass.expanded;
        final isCompact = viewport == KartaViewportClass.compact;
        final isShortLandscape = !isCompact && constraints.maxHeight <= 620;

        final double maxMediumPanel = math.max(
          280.0,
          math.min(
            KartaSpacing.tabletPanelWidth,
            constraints.maxWidth - KartaSpacing.railWidth - 130,
          ),
        );
        final double panelWidth =
            isExpanded ? KartaSpacing.sidePanelWidth : maxMediumPanel;
        final bool panelVisible =
            widget.sidePanel != null && !widget.hideSidePanel && !_isCollapsed;

        // Both Medium (Tablet / Standard Auto) and Expanded (Desktop / Wide Auto)
        // share the persistent left navigation rail (`KartaSpacing.railWidth`).
        final double sideLeftBase = KartaSpacing.railWidth + KartaSpacing.md;
        final double leftInset = isCompact
            ? KartaSpacing.sm
            : KartaSpacing.railWidth +
                (panelVisible
                    ? panelWidth + KartaSpacing.xl + 36
                    : (widget.hideSidePanel || widget.sidePanel == null
                        ? KartaSpacing.md
                        : KartaSpacing.md + 54));

        // On mobile explore, if a bottom overlay (e.g. Fuel Comparison) is open,
        // it replaces the explore side panel cleanly instead of overlapping it.
        final bool compactShowsBottomCenter =
            isCompact &&
            widget.bottomCenterOverlay != null &&
            widget.mobileActiveSheetOverlay == null;

        final bool compactExplorePanelVisible =
            isCompact &&
            widget.sidePanel != null &&
            !widget.hideSidePanel &&
            widget.mobileActiveSheetOverlay == null &&
            !compactShowsBottomCenter;

        // On mobile active nav, hide lower floating overlays while the draggable
        // bottom sheet is expanded or voice waveform is active so zero collisions occur.
        final bool hideCompactLowerHud =
            isCompact &&
            widget.mobileActiveSheetOverlay != null &&
            (widget.mobileSheetExpanded || widget.bottomVoiceWaveformOverlay != null);

        final bool useHorizontalTopControls =
            (isShortLandscape || (isCompact && widget.topHudOverlay != null)) &&
            widget.topRightControlsHorizontal != null;

        final double desktopRightReserve =
            widget.floatingRightOverlay != null ? 96.0 : KartaSpacing.md;
        final double topHudRightInset = isShortLandscape && useHorizontalTopControls
            ? 248.0
            : (widget.topRightControls != null ? 88.0 : KartaSpacing.md);

        // Unified bottom-left cluster combining hazard pill directly above speed telemetry
        final bool hasBottomLeftCluster =
            (widget.bottomLeftOverlay != null || widget.cornerHazardOverlay != null) &&
            !hideCompactLowerHud &&
            !compactExplorePanelVisible;

        final double compactExploreMaxHeight =
            math.max(220.0, math.min(410.0, constraints.maxHeight * 0.48));

        return Scaffold(
          backgroundColor: palette.backgroundPrimary,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 1. Full-bleed 3D MapLibre canvas
              Positioned.fill(child: widget.mapLayer),

              // 2. Persistent Left Navigation Rail (Medium: Tablet & Standard Auto; Expanded: Desktop & Wide Auto)
              if (!isCompact)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: KartaSpacing.railWidth,
                  child: KartaPointerShield(
                    child: _DesktopNavRail(
                      items: widget.navItems,
                      selectedId: widget.selectedNavId,
                      onSelect: (id) {
                        widget.onSelectNav(id);
                        if (_isCollapsed) _toggleSidebar();
                      },
                      onOpenLanguage: widget.onOpenLanguage,
                      languageBadge: widget.languageBadge,
                      languageTooltip: widget.languageTooltip,
                      onOpenProfile: widget.onOpenProfile,
                      isProfileSignedIn: widget.isProfileSignedIn,
                      profileInitials: widget.profileInitials,
                      profileTooltip: widget.profileTooltip,
                      onRequestExit: widget.onRequestExit,
                    ),
                  ),
                ),

              // 2b. Google Maps-style Floating Search Pill + Category Chips (Desktop/Tablet/Auto Explore)
              if (!isCompact && widget.topSearchOverlay != null)
                Positioned(
                  left: KartaSpacing.railWidth + KartaSpacing.md,
                  right: widget.topRightControls != null ? 84.0 : KartaSpacing.md,
                  top: safe.top + KartaSpacing.md,
                  child: widget.topSearchOverlay!,
                ),

              // 2c. State / District Border-Crossing Welcome Notification Banner with Flag
              if (widget.topWelcomeOverlay != null)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: isCompact ? KartaSpacing.sm : leftInset,
                  right: isCompact ? KartaSpacing.sm : topHudRightInset,
                  top: safe.top +
                      (isCompact
                          ? (widget.topHudOverlay != null ? 156.0 : 14.0)
                          : (widget.topHudOverlay != null
                              ? 148.0
                              : (widget.topSearchOverlay != null ? 74.0 : 18.0))),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: widget.topWelcomeOverlay!,
                  ),
                ),

              // 3. Collapsible Glassmorphic Side Panel (Medium & Expanded)
              if (widget.sidePanel != null && !widget.hideSidePanel && !isCompact)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: _isCollapsed ? sideLeftBase - panelWidth - 28 : sideLeftBase,
                  top: safe.top + KartaSpacing.md,
                  bottom: safe.bottom + KartaSpacing.md,
                  width: panelWidth,
                  child: IgnorePointer(
                    ignoring: _isCollapsed,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isCollapsed ? 0.0 : 1.0,
                      child: KartaPointerShield(
                        intercepting: !_isCollapsed,
                        child: widget.sidePanel!,
                      ),
                    ),
                  ),
                ),

              // 3b. Floating Glassmorphic Sidebar Collapse / Expand Handle (48x48dp target)
              if (widget.sidePanel != null && !widget.hideSidePanel && !isCompact)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: _isCollapsed
                      ? KartaSpacing.railWidth + 8
                      : sideLeftBase + panelWidth + 6,
                  top: safe.top + (isShortLandscape ? 16 : 74),
                  child: KartaPointerShield(
                    child: Tooltip(
                      message: _isCollapsed
                          ? 'Expand Karta Sidebar'
                          : 'Collapse Sidebar for Panoramic 3D View',
                      child: InkWell(
                        key: const ValueKey<String>('karta-sidebar-toggle'),
                        onTap: _toggleSidebar,
                        borderRadius: BorderRadius.circular(14),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: KartaSpacing.minTouchTarget,
                            minHeight: KartaSpacing.minTouchTarget,
                          ),
                          child: KartaSurfaceCard(
                            padding: const EdgeInsets.all(12),
                            borderRadius: 14,
                            deepGlass: true,
                            child: Icon(
                              _isCollapsed
                                  ? Icons.chevron_right_rounded
                                  : Icons.chevron_left_rounded,
                              size: 22,
                              color: palette.accentBright,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // 4a. Compact Smartphone Active Nav Top Stack (Maneuver Banner + Horizontal Utility Bar)
              // Stacking both in a single Column guarantees zero overlap regardless of street wrapping.
              if (isCompact && widget.topHudOverlay != null)
                Positioned(
                  left: KartaSpacing.sm,
                  right: KartaSpacing.sm,
                  top: safe.top + KartaSpacing.sm,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      KartaPointerShield(child: widget.topHudOverlay!),
                      if (widget.topRightControlsHorizontal != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: KartaPointerShield(
                            child: widget.topRightControlsHorizontal!,
                          ),
                        ),
                      ] else if (widget.topRightControls != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: KartaPointerShield(
                            child: widget.topRightControls!,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // 4b. Desktop / Tablet / Automotive Top-center Turn-by-Turn HUD Signboard
              if (!isCompact && widget.topHudOverlay != null)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: leftInset,
                  right: topHudRightInset,
                  top: safe.top + KartaSpacing.md,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: KartaPointerShield(child: widget.topHudOverlay!),
                    ),
                  ),
                ),

              // 5. Top-right Map Utility Cluster (Desktop / Tablet / Automotive / Compact Explore)
              if (widget.topRightControls != null &&
                  !(isCompact && widget.topHudOverlay != null))
                Positioned(
                  right: KartaSpacing.md,
                  top: safe.top + KartaSpacing.md,
                  child: KartaPointerShield(
                    child: useHorizontalTopControls
                        ? widget.topRightControlsHorizontal!
                        : widget.topRightControls!,
                  ),
                ),

              // 6. Unified Bottom-Left Cluster: Corner Spatial Hazard Pill stacked ABOVE Speed Telemetry
              if (hasBottomLeftCluster)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: isCompact ? KartaSpacing.sm : leftInset,
                  bottom: safe.bottom +
                      (isCompact
                          ? (widget.mobileActiveSheetOverlay != null ? 124 : 132)
                          : KartaSpacing.md),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isCompact
                          ? math.max(196.0, math.min(252.0, constraints.maxWidth - 96))
                          : 248.0,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (widget.cornerHazardOverlay != null)
                          KartaPointerShield(child: widget.cornerHazardOverlay!),
                        if (widget.cornerHazardOverlay != null &&
                            widget.bottomLeftOverlay != null)
                          const SizedBox(height: 8),
                        if (widget.bottomLeftOverlay != null)
                          KartaPointerShield(child: widget.bottomLeftOverlay!),
                      ],
                    ),
                  ),
                ),

              // 6b. Compact Explore Corner Spatial Hazard Pill (top-center between floating triggers & top-right utils)
              if (compactExplorePanelVisible && widget.cornerHazardOverlay != null)
                Positioned(
                  left: widget.floatingRightOverlay != null ? 84 : KartaSpacing.sm,
                  right: widget.topRightControls != null ? 76 : KartaSpacing.sm,
                  top: safe.top + KartaSpacing.md,
                  child: KartaPointerShield(child: widget.cornerHazardOverlay!),
                ),

              // 7. Bottom-center Navigation Trip Dock / Fuel Overlay
              if (widget.bottomCenterOverlay != null &&
                  (!isCompact || widget.mobileActiveSheetOverlay == null))
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: isCompact
                      ? KartaSpacing.sm
                      : leftInset + (widget.bottomLeftOverlay != null ? 260 : 0),
                  right: isCompact ? KartaSpacing.sm : desktopRightReserve,
                  bottom: safe.bottom + (isCompact ? 66 : KartaSpacing.md),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: widget.bottomLeftOverlay != null ? 740 : 680,
                        maxHeight: isCompact ? compactExploreMaxHeight : double.infinity,
                      ),
                      child: KartaPointerShield(child: widget.bottomCenterOverlay!),
                    ),
                  ),
                ),

              // 7b. Floating Crowdsourcing Cluster (60x60dp Report Hazard / Voice Mic / Fuel)
              // - Compact Explore: top-left above the explore sheet (zero overlap with panel or top-right utils)
              // - Compact Active Nav: bottom-right above collapsed sheet (hidden while expanded)
              // - Desktop/Tablet/Auto: bottom-right with generous clearance below top-right controls
              if (widget.floatingRightOverlay != null && !hideCompactLowerHud)
                Positioned(
                  left: (isCompact && widget.mobileActiveSheetOverlay == null)
                      ? KartaSpacing.sm
                      : null,
                  right: (isCompact && widget.mobileActiveSheetOverlay == null)
                      ? null
                      : KartaSpacing.md,
                  top: (isCompact && widget.mobileActiveSheetOverlay == null)
                      ? safe.top + KartaSpacing.md
                      : null,
                  bottom: (isCompact && widget.mobileActiveSheetOverlay == null)
                      ? null
                      : safe.bottom +
                          (isCompact
                              ? 124
                              : (widget.bottomRightOverlay != null ? 116 : KartaSpacing.md)),
                  child: KartaPointerShield(child: widget.floatingRightOverlay!),
                ),

              // 8. Optional Bottom-Right Overlay (Desktop / Tablet / Auto — unused when media bar disabled)
              if (widget.bottomRightOverlay != null && !isCompact)
                Positioned(
                  right: KartaSpacing.md,
                  bottom: safe.bottom + KartaSpacing.md,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: KartaPointerShield(child: widget.bottomRightOverlay!),
                  ),
                ),

              // 8b. Minimal Bottom-Center Hands-Free Voice Audio Waveform Pill
              if (widget.bottomVoiceWaveformOverlay != null)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  left: isCompact
                      ? KartaSpacing.sm
                      : leftInset + (widget.bottomLeftOverlay != null ? 260 : 0),
                  right: isCompact ? KartaSpacing.sm : desktopRightReserve,
                  bottom: safe.bottom +
                      (isCompact
                          ? (widget.mobileActiveSheetOverlay != null ? 124 : 74)
                          : (widget.bottomCenterOverlay != null ? 96 : KartaSpacing.md)),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isCompact ? 374 : 440),
                      child: KartaPointerShield(
                        child: widget.bottomVoiceWaveformOverlay!,
                      ),
                    ),
                  ),
                ),

              // 9a. Mobile Spring-Physics 3-State Draggable Bottom Sheet (active navigation)
              if (isCompact && widget.mobileActiveSheetOverlay != null)
                Positioned(
                  left: KartaSpacing.xs,
                  right: KartaSpacing.xs,
                  bottom: safe.bottom + 8,
                  child: KartaPointerShield(
                    child: widget.mobileActiveSheetOverlay!,
                  ),
                ),

              // 9b. Compact Smartphone layout: minimized-by-default collapsible explore sheet + bottom tab bar
              if (compactExplorePanelVisible)
                Positioned(
                  left: KartaSpacing.sm,
                  right: KartaSpacing.sm,
                  bottom: safe.bottom + 66,
                  child: KartaPointerShield(
                    child: GestureDetector(
                      onVerticalDragEnd: (details) {
                        final vy = details.primaryVelocity ?? 0;
                        if (vy < -180) {
                          _setMobileExploreExpanded(true);
                        } else if (vy > 180) {
                          _setMobileExploreExpanded(false);
                        }
                      },
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.bottomCenter,
                        child: _isMobileExploreExpanded
                            ? ConstrainedBox(
                                key: const ValueKey<String>('karta-mobile-explore-expanded'),
                                constraints: BoxConstraints(maxHeight: compactExploreMaxHeight + 28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    // Compact drag / minimize header strip above expanded sheet
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _toggleMobileExplore,
                                      child: Container(
                                        margin: const EdgeInsets.only(bottom: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: palette.hudDeepGlass,
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(color: palette.borderStrong),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            Container(
                                              width: 28,
                                              height: 3.5,
                                              decoration: BoxDecoration(
                                                color: palette.textSecondary.withValues(alpha: 0.6),
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              context.kartaStrings.minimize,
                                              style: KartaTypography.captionLabel.copyWith(
                                                fontSize: 11,
                                                color: palette.textSecondary,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              key: const ValueKey<String>('karta-mobile-explore-toggle'),
                                              size: 16,
                                              color: palette.accentBright,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Flexible(child: widget.sidePanel!),
                                  ],
                                ),
                              )
                            : _CompactMinimizedExploreBar(
                                key: const ValueKey<String>('karta-mobile-explore-minimized'),
                                subtitle: widget.mobileExploreCollapsedSubtitle ??
                                    context.kartaStrings.whereToPrompt,
                                onExpand: () => _setMobileExploreExpanded(true),
                                onOpenLanguage: widget.onOpenLanguage,
                                languageBadge: widget.languageBadge,
                              ),
                      ),
                    ),
                  ),
                ),

              if (isCompact && widget.mobileActiveSheetOverlay == null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: KartaPointerShield(
                    child: _CompactBottomNav(
                      items: widget.navItems,
                      selectedId: widget.selectedNavId,
                      onSelect: (id) {
                        if (id == widget.selectedNavId) {
                          _toggleMobileExplore();
                        } else {
                          widget.onSelectNav(id);
                          _setMobileExploreExpanded(true);
                        }
                      },
                      safeBottom: safe.bottom,
                    ),
                  ),
                ),

              // 9c. Optional animated Phone-to-Car Companion overlay
              if (widget.companionOverlay != null)
                Positioned.fill(child: widget.companionOverlay!),

              // 10. Optional modal overlay (Radial Hazard Wheel / Street-Level Look-Around)
              if (widget.modalOverlay != null)
                Positioned.fill(
                  child: KartaPointerShield(child: widget.modalOverlay!),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DesktopNavRail extends StatelessWidget {
  const _DesktopNavRail({
    required this.items,
    required this.selectedId,
    required this.onSelect,
    this.onOpenLanguage,
    this.languageBadge,
    this.languageTooltip,
    this.onOpenProfile,
    this.isProfileSignedIn = false,
    this.profileInitials,
    this.profileTooltip,
    this.onRequestExit,
  });

  final List<KartaNavRailItem> items;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback? onOpenLanguage;
  final String? languageBadge;
  final String? languageTooltip;
  final VoidCallback? onOpenProfile;
  final bool isProfileSignedIn;
  final String? profileInitials;
  final String? profileTooltip;
  final VoidCallback? onRequestExit;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final l10n = context.kartaStrings;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: palette.hudDeepGlass,
        border: Border(right: BorderSide(color: palette.borderSubtle)),
      ),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 12),
                    const KartaLogoMark(size: 38),
                    const SizedBox(height: 6),
                    Text(
                      'KARTA',
                      style: KartaTypography.monoBadge.copyWith(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: palette.accentBright,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, indent: 14, endIndent: 14, color: palette.borderSubtle),
                    const SizedBox(height: 10),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                        child: _RailTile(
                          item: item,
                          selected: item.id == selectedId,
                          onTap: () => onSelect(item.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (onOpenLanguage != null || onOpenProfile != null || onRequestExit != null)
              Divider(height: 1, indent: 14, endIndent: 14, color: palette.borderSubtle),
            if (onOpenLanguage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                child: Tooltip(
                  message: languageTooltip ?? l10n.selectLanguageTitle,
                  preferBelow: false,
                  child: InkWell(
                    key: const ValueKey<String>('karta-language-btn'),
                    onTap: onOpenLanguage,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 54,
                        minHeight: 42,
                      ),
                      child: SizedBox(
                        width: 68,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: palette.accentGlow,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: palette.accentPrimary.withValues(alpha: 0.55),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.translate_rounded,
                                      size: 12.5,
                                      color: palette.accentBright,
                                    ),
                                    const SizedBox(width: 2.5),
                                    Text(
                                      languageBadge ?? 'EN',
                                      style: KartaTypography.monoBadge.copyWith(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: palette.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.navLanguage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KartaTypography.captionLabel.copyWith(
                                fontSize: 10,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (onOpenProfile != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                child: Tooltip(
                  message: profileTooltip ?? l10n.accountTitle,
                  preferBelow: false,
                  child: InkWell(
                    key: const ValueKey<String>('karta-header-account-btn'),
                    onTap: onOpenProfile,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 54,
                        minHeight: KartaSpacing.minTouchTarget,
                      ),
                      child: SizedBox(
                        width: 68,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isProfileSignedIn
                                    ? palette.accentPrimary
                                    : palette.surfaceElevated,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isProfileSignedIn
                                      ? palette.accentBright
                                      : palette.borderStrong,
                                  width: 1.4,
                                ),
                              ),
                              child: isProfileSignedIn &&
                                      profileInitials != null &&
                                      profileInitials!.isNotEmpty
                                  ? Text(
                                      profileInitials!,
                                      style: KartaTypography.captionLabel.copyWith(
                                        color: onPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    )
                                  : Icon(
                                      Icons.person_outline_rounded,
                                      size: 19,
                                      color: palette.textPrimary,
                                    ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              l10n.navProfile,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KartaTypography.captionLabel.copyWith(
                                fontSize: 10.5,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (onRequestExit != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                child: Tooltip(
                  message: l10n.exitDialogTitle,
                  preferBelow: false,
                  child: InkWell(
                    key: const ValueKey<String>('karta-rail-exit-btn'),
                    onTap: onRequestExit,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 54,
                        minHeight: KartaSpacing.minTouchTarget,
                      ),
                      child: SizedBox(
                        width: 68,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              Icons.power_settings_new_rounded,
                              size: 20,
                              color: palette.statusAlert,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              l10n.navExit,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KartaTypography.captionLabel.copyWith(
                                fontSize: 10.5,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sleek minimized smartphone explore dock (~72dp tall) that keeps ~80%+ of
/// the phone screen open for the full 3D map until the user taps or swipes up.
class _CompactMinimizedExploreBar extends StatelessWidget {
  const _CompactMinimizedExploreBar({
    super.key,
    required this.subtitle,
    required this.onExpand,
    this.onOpenLanguage,
    this.languageBadge,
  });

  final String subtitle;
  final VoidCallback onExpand;
  final VoidCallback? onOpenLanguage;
  final String? languageBadge;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final l10n = context.kartaStrings;
    return KartaSurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 7, 10, 10),
      borderRadius: 18,
      deepGlass: true,
      child: InkWell(
        onTap: onExpand,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 34,
              height: 3.5,
              margin: const EdgeInsets.only(bottom: 7),
              decoration: BoxDecoration(
                color: palette.textSecondary.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Row(
              children: <Widget>[
                const KartaLogoMark(size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        l10n.appTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KartaTypography.sectionTitle.copyWith(
                          fontSize: 14,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
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
                if (onOpenLanguage != null) ...<Widget>[
                  const SizedBox(width: 6),
                  InkWell(
                    key: const ValueKey<String>('karta-language-btn'),
                    onTap: onOpenLanguage,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: palette.surfaceElevated,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: palette.borderStrong),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.translate_rounded,
                            size: 14,
                            color: palette.accentBright,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            languageBadge ?? 'EN',
                            style: KartaTypography.monoBadge.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: palette.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Container(
                  key: const ValueKey<String>('karta-mobile-explore-toggle'),
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: palette.accentGlow,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: palette.accentPrimary.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: palette.accentBright,
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 18,
                        color: palette.accentBright,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final KartaNavRailItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Tooltip(
      message: item.label,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 54,
            minHeight: KartaSpacing.minTouchTarget,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 68,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
            decoration: BoxDecoration(
              color: selected ? palette.accentGlow : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? palette.accentPrimary.withValues(alpha: 0.75)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Icon(
                      item.icon,
                      size: 21,
                      color: selected ? palette.accentBright : palette.textSecondary,
                    ),
                    if (item.badgeCount > 0)
                      Positioned(
                        right: -7,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: palette.accentPrimary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${item.badgeCount}',
                            style: KartaTypography.monoBadge.copyWith(
                              fontSize: 10,
                              color: onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KartaTypography.captionLabel.copyWith(
                    fontSize: 10.5,
                    letterSpacing: 0.1,
                    color: selected ? palette.textPrimary : palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactBottomNav extends StatelessWidget {
  const _CompactBottomNav({
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.safeBottom,
  });

  final List<KartaNavRailItem> items;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final double safeBottom;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      padding: EdgeInsets.only(top: 6, bottom: safeBottom + 6, left: 6, right: 6),
      decoration: BoxDecoration(
        color: palette.hudDeepGlass,
        border: Border(top: BorderSide(color: palette.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          for (final item in items)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(item.id),
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: KartaSpacing.minTouchTarget,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          item.icon,
                          size: 20,
                          color: item.id == selectedId
                              ? palette.accentBright
                              : palette.textSecondary,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KartaTypography.captionLabel.copyWith(
                            fontSize: 11,
                            letterSpacing: 0.1,
                            color: item.id == selectedId
                                ? palette.textPrimary
                                : palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
