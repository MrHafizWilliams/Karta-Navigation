import 'package:flutter/material.dart';
import 'package:karta_design_system/karta_design_system.dart';

import '../../data/sea_featured_places.dart';

/// Rich, tourist-friendly info card opened whenever a user taps a curated
/// Southeast Asian landmark, international airport, mosque, temple, church,
/// or railway station on the map or in search results.
class KartaFeaturedPlaceInfoCard extends StatelessWidget {
  const KartaFeaturedPlaceInfoCard({
    super.key,
    required this.place,
    required this.isSaved,
    required this.onClose,
    required this.onGoHere,
    required this.onStartHere,
    required this.onSave,
    required this.onLookAround,
  });

  final KartaFeaturedPlace place;
  final bool isSaved;
  final VoidCallback onClose;
  final VoidCallback onGoHere;
  final VoidCallback onStartHere;
  final VoidCallback onSave;
  final VoidCallback onLookAround;

  ({Color accent, IconData icon, String label}) _styleForKind(
    KartaPlaceKind kind,
    KartaStrings l10n,
  ) {
    return switch (kind) {
      KartaPlaceKind.historicalLandmark => (
          accent: const Color(0xFFD97706),
          icon: Icons.account_balance_rounded,
          label: l10n.kindHistoricLandmark,
        ),
      KartaPlaceKind.modernLandmark => (
          accent: const Color(0xFF0D9488),
          icon: Icons.location_city_rounded,
          label: l10n.kindModernLandmark,
        ),
      KartaPlaceKind.airport => (
          accent: const Color(0xFF2563EB),
          icon: Icons.flight_takeoff_rounded,
          label: l10n.kindAirport,
        ),
      KartaPlaceKind.mosque => (
          accent: const Color(0xFF059669),
          icon: Icons.mosque_rounded,
          label: l10n.kindMosque,
        ),
      KartaPlaceKind.temple => (
          accent: const Color(0xFFEA580C),
          icon: Icons.temple_buddhist_rounded,
          label: l10n.kindTemple,
        ),
      KartaPlaceKind.church => (
          accent: const Color(0xFF7C3AED),
          icon: Icons.church_rounded,
          label: l10n.kindChurch,
        ),
      KartaPlaceKind.railHub => (
          accent: const Color(0xFF0284C7),
          icon: Icons.train_rounded,
          label: l10n.kindRailHub,
        ),
      KartaPlaceKind.trainStation => (
          accent: const Color(0xFF0284C7),
          icon: Icons.subway_rounded,
          label: l10n.kindTrainStation,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final l10n = context.kartaStrings;
    final kindStyle = _styleForKind(place.kind, l10n);

    return KartaPointerShield(
      child: KartaSurfaceCard(
        key: const ValueKey<String>('karta-place-info-card'),
        deepGlass: true,
        borderRadius: 20,
        padding: EdgeInsets.zero,
        borderColor: kindStyle.accent.withValues(alpha: 0.55),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Top category pill + UNESCO badge + Close
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: kindStyle.accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: kindStyle.accent.withValues(alpha: 0.55),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(kindStyle.icon, size: 13, color: kindStyle.accent),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    kindStyle.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: KartaTypography.captionLabel.copyWith(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: palette.isDaylight
                                          ? kindStyle.accent
                                          : palette.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (place.iataCode != null && place.iataCode!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1D4ED8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                place.iataCode!,
                                style: KartaTypography.monoBadge.copyWith(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          if (place.isUnesco)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.55),
                                ),
                              ),
                              child: Text(
                                l10n.unescoBadge,
                                style: KartaTypography.captionLabel.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: palette.isDaylight
                                      ? const Color(0xFFB45309)
                                      : const Color(0xFFFCD34D),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey<String>('karta-place-info-close'),
                      tooltip: l10n.dismiss,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 19,
                        color: palette.textSecondary,
                      ),
                      onPressed: onClose,
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Place Title & City / Country
                Text(
                  place.name,
                  style: KartaTypography.sectionTitle.copyWith(
                    fontSize: 16.5,
                    height: 1.2,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.place_rounded,
                      size: 13.5,
                      color: palette.accentBright,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        place.countryCode.isNotEmpty
                            ? '${place.city} · ${place.countryName} (${place.countryCode})'
                            : '${place.city} · ${place.countryName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KartaTypography.bodySecondary.copyWith(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),

                // Metadata strip (Established / Airport ICAO / Coordinates)
                if (place.established != null || place.icaoCode != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      if (place.established != null)
                        _MetaPill(
                          icon: Icons.history_edu_rounded,
                          text: '${l10n.establishedLabel}: ${place.established}',
                        ),
                      if (place.iataCode != null && place.icaoCode != null)
                        _MetaPill(
                          icon: Icons.radar_rounded,
                          text: '${l10n.iataCodeLabel}: ${place.iataCode} / ${place.icaoCode}',
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),

                // Curated Tourist Summary
                Text(
                  l10n.aboutSection,
                  style: KartaTypography.captionLabel.copyWith(
                    fontSize: 10,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w700,
                    color: palette.accentBright,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  place.summary,
                  style: KartaTypography.bodyPrimary.copyWith(
                    fontSize: 12.8,
                    height: 1.45,
                    color: palette.textPrimary.withValues(alpha: 0.92),
                  ),
                ),

                // Highlights chips
                if (place.highlights.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 11),
                  Text(
                    l10n.highlightsSection,
                    style: KartaTypography.captionLabel.copyWith(
                      fontSize: 10,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w700,
                      color: palette.accentBright,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: place.highlights
                        .map(
                          (h) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: palette.surfaceElevated.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: palette.borderSubtle),
                            ),
                            child: Text(
                              h,
                              style: KartaTypography.captionLabel.copyWith(
                                fontSize: 11,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],

                // Rail & Transit Access
                if (place.transitAccess != null && place.transitAccess!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 11),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(
                          Icons.train_rounded,
                          size: 16,
                          color: Color(0xFF38BDF8),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                l10n.transitAccessLabel,
                                style: KartaTypography.captionLabel.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: palette.isDaylight
                                      ? const Color(0xFF0369A1)
                                      : const Color(0xFF7DD3FC),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                place.transitAccess!,
                                style: KartaTypography.bodySecondary.copyWith(
                                  fontSize: 11.5,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Primary Actions Row (overflow-proof across all 11 languages & narrow viewports)
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 5,
                      child: FilledButton.icon(
                        key: const ValueKey<String>('karta-place-info-go-btn'),
                        onPressed: onGoHere,
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.accentPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.navigation_rounded, size: 15),
                        label: Text(
                          l10n.goHere,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KartaTypography.bodyPrimary.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: OutlinedButton(
                        onPressed: onStartHere,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          side: BorderSide(color: palette.borderStrong),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          l10n.startHere,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KartaTypography.bodyPrimary.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: IconButton.outlined(
                        tooltip: isSaved ? l10n.savedLabel : l10n.save,
                        padding: EdgeInsets.zero,
                        onPressed: onSave,
                        style: IconButton.styleFrom(
                          side: BorderSide(
                            color: isSaved ? const Color(0xFFF59E0B) : palette.borderStrong,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        icon: Icon(
                          isSaved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                          size: 17,
                          color: isSaved ? const Color(0xFFF59E0B) : palette.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: IconButton.outlined(
                        tooltip: l10n.lookAround,
                        padding: EdgeInsets.zero,
                        onPressed: onLookAround,
                        style: IconButton.styleFrom(
                          side: BorderSide(color: palette.borderStrong),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        icon: Icon(
                          Icons.streetview_rounded,
                          size: 17,
                          color: palette.accentBright,
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
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: palette.surfaceElevated.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12.5, color: palette.textSecondary),
          const SizedBox(width: 5),
          Text(
            text,
            style: KartaTypography.captionLabel.copyWith(
              fontSize: 11,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
