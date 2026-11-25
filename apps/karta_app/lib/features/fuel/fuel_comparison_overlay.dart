import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_design_system/karta_design_system.dart';

import '../../state/karta_app_state.dart';
import '../../state/phase3_providers.dart';

/// Community-updated fuel price comparison card along the active route or nearby
/// corridor (MY RON95/RON97/Diesel, SG 92/95/98/Diesel, BN RON97/RON92/Diesel).
///
/// Works seamlessly alongside always-on inline fuel station map pins along the
/// active route, highlighting the cheapest station and enabling 1-tap pit-stop
/// insertion.
class FuelComparisonOverlay extends ConsumerWidget {
  const FuelComparisonOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fuel = ref.watch(fuelComparisonProvider);
    final notifier = ref.read(fuelComparisonProvider.notifier);
    final palette = context.kartaPalette;
    final grades = FuelGrade.gradesForCountry(fuel.countryCode);
    final stations = fuel.response?.stations ?? const <FuelStationComparison>[];

    int? highestMinor;
    int? cheapestMinor;
    for (final s in stations) {
      if (highestMinor == null || s.selectedPriceMinor > highestMinor) {
        highestMinor = s.selectedPriceMinor;
      }
      if (cheapestMinor == null || s.selectedPriceMinor < cheapestMinor) {
        cheapestMinor = s.selectedPriceMinor;
      }
    }
    final savings40LMinor =
        (highestMinor != null && cheapestMinor != null && highestMinor > cheapestMinor)
            ? (highestMinor - cheapestMinor) * 40
            : 0;

    return KartaSurfaceCard(
      deepGlass: true,
      borderRadius: 18,
      borderColor: palette.accentPrimary.withValues(alpha: 0.65),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header: Country switcher + inline map pins indicator + close
          Row(
            children: <Widget>[
              Icon(Icons.local_gas_station_rounded, size: 18, color: palette.accentBright),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Fuel Finder Along Route',
                      style: KartaTypography.sectionTitle.copyWith(
                        fontSize: 13.5,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (fuel.response?.cheapestFormattedPrice != null)
                      Text(
                        '★ Best ${fuel.selectedGrade.shortLabel}: ${fuel.response!.cheapestFormattedPrice}/L'
                        '${savings40LMinor > 0 ? ' · Save ${_formatMinor(savings40LMinor, stations.first.currencyCode)} / 40L' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KartaTypography.monoBadge.copyWith(
                          fontSize: 11,
                          color: palette.statusClear,
                        ),
                      ),
                  ],
                ),
              ),
              for (final cc in const <String>['MY', 'SG', 'BN'])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: InkWell(
                    onTap: () => notifier.setCountry(cc),
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: fuel.countryCode == cc ? palette.accentGlow : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: fuel.countryCode == cc
                                ? palette.accentPrimary
                                : palette.borderSubtle,
                          ),
                        ),
                        child: Text(
                          cc,
                          style: KartaTypography.monoBadge.copyWith(
                            fontSize: 11,
                            color: fuel.countryCode == cc
                                ? palette.accentBright
                                : palette.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              IconButton(
                constraints: const BoxConstraints(
                  minWidth: KartaSpacing.minTouchTarget,
                  minHeight: KartaSpacing.minTouchTarget,
                ),
                tooltip: 'Close panel (inline route badges stay visible)',
                onPressed: () =>
                    ref.read(realtimeCrowdsourcingProvider.notifier).toggleFuelOverlay(false),
                icon: Icon(Icons.close_rounded, size: 20, color: palette.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Fuel Grade Pills + Sort + Inline Map Badges Toggle
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final g in grades)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(g.shortLabel),
                      selected: fuel.selectedGrade == g,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => notifier.setGrade(g),
                    ),
                  ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Cheapest'),
                  selected: fuel.sortBy == 'price',
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => notifier.setSortBy('price'),
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('Nearest'),
                  selected: fuel.sortBy == 'detour',
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => notifier.setSortBy('detour'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text(
                    fuel.inlineRoutePinsEnabled ? 'Map Badges ON' : 'Map Badges OFF',
                    style: KartaTypography.captionLabel.copyWith(color: palette.textPrimary),
                  ),
                  selected: fuel.inlineRoutePinsEnabled,
                  onSelected: notifier.toggleInlineRoutePins,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          if (fuel.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: palette.accentPrimary),
                ),
              ),
            )
          else if (fuel.errorMessage != null)
            Text(
              fuel.errorMessage!,
              style: KartaTypography.bodySecondary.copyWith(color: palette.statusAlert),
            )
          else if (stations.isEmpty)
            Text(
              'No fuel stations matched this corridor yet — compute a route or move map.',
              style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
            )
          else
            SizedBox(
              height: 144,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: stations.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final st = stations[index];
                  final deltaMinor =
                      cheapestMinor != null ? (st.selectedPriceMinor - cheapestMinor) : 0;
                  return _FuelStationCard(
                    station: st,
                    isHighlighted: fuel.highlightedPoiId == st.poiId,
                    deltaMinor: deltaMinor,
                    onUpdatePrice: () => _showUpdatePriceDialog(context, ref, st),
                    onAddPitStop: () => notifier.insertFuelStationAsStop(st),
                    onFocusMap: () {
                      ref.read(kartaMapControllerProvider).easeTo(
                            center: st.coordinate,
                            zoom: 16.0,
                            pitch: 56,
                          );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  static String _formatMinor(int minor, String currencyCode) {
    final val = (minor / 100.0).toStringAsFixed(2);
    return switch (currencyCode.toUpperCase()) {
      'SGD' => '\$$val',
      'BND' => 'B\$$val',
      _ => 'RM $val',
    };
  }

  Future<void> _showUpdatePriceDialog(
    BuildContext context,
    WidgetRef ref,
    FuelStationComparison station,
  ) async {
    final ctrl = TextEditingController(
      text: (station.selectedPriceMinor / 100.0).toStringAsFixed(2),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => KartaPointerShield(
        child: AlertDialog(
          title: Text('Update ${station.selectedGrade.shortLabel} Price'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                station.name,
                style: KartaTypography.bodySecondary,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Price per litre (${station.currencyCode})',
                  hintText: 'e.g. 2.05',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publish')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final parsed = double.tryParse(ctrl.text.trim());
    if (parsed == null || parsed <= 0) return;
    final minor = (parsed * 100).round();
    final msg = await ref.read(fuelComparisonProvider.notifier).submitCommunityPrice(
          poiId: station.poiId,
          grade: station.selectedGrade,
          priceMinor: minor,
        );
    if (context.mounted && msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

class _FuelStationCard extends StatelessWidget {
  const _FuelStationCard({
    required this.station,
    required this.isHighlighted,
    required this.deltaMinor,
    required this.onUpdatePrice,
    required this.onAddPitStop,
    required this.onFocusMap,
  });

  final FuelStationComparison station;
  final bool isHighlighted;
  final int deltaMinor;
  final VoidCallback onUpdatePrice;
  final VoidCallback onAddPitStop;
  final VoidCallback onFocusMap;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final borderColor = isHighlighted
        ? palette.accentBright
        : (station.isCheapest ? palette.statusClear : palette.borderSubtle);

    return InkWell(
      onTap: onFocusMap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 234,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: station.isCheapest
              ? palette.statusClear.withValues(alpha: palette.isDaylight ? 0.12 : 0.14)
              : palette.surfaceElevated.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: (station.isCheapest || isHighlighted) ? 1.7 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    station.brand ?? station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KartaTypography.bodyPrimary.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                if (station.isCheapest)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: palette.statusClear.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '★ BEST',
                      style: KartaTypography.monoBadge.copyWith(
                        fontSize: 11,
                        color: palette.statusClear,
                      ),
                    ),
                  )
                else if (deltaMinor > 0)
                  Text(
                    '+${(deltaMinor / 100.0).toStringAsFixed(2)}',
                    style: KartaTypography.monoBadge.copyWith(
                      fontSize: 11,
                      color: palette.statusCaution,
                    ),
                  ),
              ],
            ),
            Text(
              station.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KartaTypography.bodySecondary.copyWith(
                fontSize: 11.5,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  station.selectedFormattedPrice,
                  style: KartaTypography.telemetryValue.copyWith(
                    fontSize: 19,
                    color: station.isCheapest ? palette.statusClear : palette.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '/L ${station.selectedGrade.shortLabel}',
                  style: KartaTypography.monoBadge.copyWith(
                    fontSize: 11,
                    color: palette.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  station.detourMinutes > 0 ? '+${station.detourMinutes}m' : 'On route',
                  style: KartaTypography.monoBadge.copyWith(
                    fontSize: 11,
                    color: palette.accentBright,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      backgroundColor: palette.accentGlow,
                      foregroundColor: palette.accentBright,
                    ),
                    onPressed: onAddPitStop,
                    child: Text(
                      'Go Here',
                      style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    foregroundColor: palette.textPrimary,
                    side: BorderSide(color: palette.borderStrong),
                  ),
                  onPressed: onUpdatePrice,
                  child: Text(
                    'Update',
                    style: KartaTypography.captionLabel.copyWith(color: palette.textPrimary),
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
