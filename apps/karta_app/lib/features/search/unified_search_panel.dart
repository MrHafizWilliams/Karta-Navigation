import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_map_engine/karta_map_engine.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import '../../services/live_location_platform.dart';
import '../../state/auth_saved_places_providers.dart';
import '../../state/karta_app_state.dart';
import '../places/featured_place_info_card.dart';
import '../routing/route_comparison_panel.dart';

/// Unified Search Bar + Live Business POI & Landmark Results + Single-Destination
/// Origin → Destination Route Builder + Route Comparison Deck.
/// Queries real PostGIS `/v1/pois/search` and Valhalla `/v1/routes` endpoints.
class UnifiedNavigationPanel extends ConsumerStatefulWidget {
  const UnifiedNavigationPanel({super.key});

  @override
  ConsumerState<UnifiedNavigationPanel> createState() => _UnifiedNavigationPanelState();
}

class _UnifiedNavigationPanelState extends ConsumerState<UnifiedNavigationPanel> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  int _searchSeq = 0;
  bool _isSearching = false;
  String? _selectedCategory;
  List<PoiItem> _searchResults = const <PoiItem>[];
  String? _searchMeta;

  static const List<({String id, String label, IconData icon})> _categories = [
    (id: 'fuel', label: 'Fuel', icon: Icons.local_gas_station_rounded),
    (id: 'ev_charging', label: 'EV', icon: Icons.ev_station_rounded),
    (id: 'rest_area', label: 'R&R', icon: Icons.local_cafe_rounded),
    (id: 'food', label: 'Food', icon: Icons.restaurant_rounded),
    (id: 'transit', label: 'Transit', icon: Icons.train_rounded),
    (id: 'shopping', label: 'Malls', icon: Icons.shopping_bag_rounded),
    (id: 'parking', label: 'Parking', icon: Icons.local_parking_rounded),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 2-Stage Zero-Latency Search:
  /// 1. Instant (<50ms) local fuzzy search over downloaded POIs on every keystroke.
  /// 2. Debounced (180ms) live PostGIS/Redis refinement when online, merging seamlessly.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    _searchSeq += 1;
    final seq = _searchSeq;

    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = const <PoiItem>[];
        _searchMeta = null;
        _isSearching = false;
      });
      return;
    }

    final localIndex = ref.read(localPoiFuzzyIndexProvider);
    final mapCenter = ref.read(kartaMapControllerProvider).center;
    final localRes = localIndex.search(
      query: trimmed,
      nearLat: mapCenter.lat,
      nearLon: mapCenter.lon,
      category: _selectedCategory,
      limit: 18,
    );

    final conn = ref.read(connectivityResilienceProvider).current;
    final willRefineOnline = !conn.isOffline && trimmed.length >= 2;

    if (localRes.items.isNotEmpty || !willRefineOnline) {
      setState(() {
        _searchResults = localRes.items;
        _searchMeta = localRes.items.isNotEmpty
            ? '${localRes.items.length} places · ${localRes.queryMs.toStringAsFixed(1)} ms'
            : (conn.isOffline
                ? 'No downloaded places matched "$trimmed"'
                : null);
        _isSearching = willRefineOnline && localRes.items.isEmpty;
      });
      if (localRes.items.isNotEmpty) {
        ref.read(kartaMapControllerProvider).setPois(localRes.items);
      }
    }

    if (willRefineOnline) {
      _debounce = Timer(const Duration(milliseconds: 180), () => _runOnlineSearch(trimmed, seq));
    }
  }

  Future<void> _runOnlineSearch(String query, int seq) async {
    if (!mounted || seq != _searchSeq) return;
    if (_searchResults.isEmpty) {
      setState(() => _isSearching = true);
    }
    final api = ref.read(kartaApiClientProvider);
    final conn = ref.read(connectivityResilienceProvider);
    final localIndex = ref.read(localPoiFuzzyIndexProvider);
    final mapCenter = ref.read(kartaMapControllerProvider).center;
    try {
      final resp = await api.searchPois(
        query: query,
        lat: mapCenter.lat,
        lon: mapCenter.lon,
        category: _selectedCategory,
        limit: 18,
      );
      conn.recordNetworkSuccess();
      localIndex.upsertAll(resp.items);
      if (!mounted || seq != _searchSeq) return;

      final merged = <PoiItem>[...resp.items];
      final seenIds = resp.items.map((p) => p.id).toSet();
      for (final localItem in _searchResults) {
        if (seenIds.add(localItem.id)) merged.add(localItem);
      }

      setState(() {
        _searchResults = merged;
        _searchMeta = '${merged.length} places · ${resp.queryMs.toStringAsFixed(1)} ms';
        _isSearching = false;
      });
      ref.read(kartaMapControllerProvider).setPois(merged);
    } catch (_) {
      // Optional PostGIS POI search fallback when local Docker isn't running;
      // keep live public Valhalla routing status unaffected.
      if (!mounted || seq != _searchSeq) return;
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final l10n = context.kartaStrings;
    final planner = ref.watch(routePlannerProvider);
    final selectedFeatured = ref.watch(selectedFeaturedPlaceProvider);
    final selectedPoi = ref.watch(selectedPoiProvider);
    final inspectedSpot = ref.watch(inspectedMapSpotProvider);
    final liveLoc = ref.watch(liveLocationProvider);
    final authState = ref.watch(authSavedPlacesProvider);
    final healthAsync = ref.watch(backendHealthProvider);
    final connSnap = ref.watch(connectivitySnapshotProvider).valueOrNull ??
        ref.read(connectivityResilienceProvider).current;
    final isWideViewport =
        KartaBreakpoints.resolve(MediaQuery.sizeOf(context).width) !=
            KartaViewportClass.compact;

    return KartaSurfaceCard(
      padding: EdgeInsets.zero,
      borderRadius: KartaSpacing.radiusLg,
      child: Column(
        children: <Widget>[
          // Brand Header + Live GPS / Engine Indicator
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
            child: Row(
              children: <Widget>[
                const KartaLogoMark(size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.appTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KartaTypography.sectionTitle.copyWith(color: palette.textPrimary),
                      ),
                      Text(
                        liveLoc.hasLiveFix
                            ? (liveLoc.placeLabel ?? l10n.liveGpsActive)
                            : 'Southeast Asia · 11 Countries',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (connSnap.mode != NetworkTransitionState.online)
                  KartaOfflineStatusPill(
                    mode: connSnap.isSyncing
                        ? KartaConnectivityVisualMode.syncingQuietly
                        : KartaConnectivityVisualMode.offlineRoutingActive,
                    pendingSyncCount: connSnap.pendingSyncCount,
                    compact: true,
                  )
                else
                  healthAsync.when(
                    data: (h) {
                      final ok = h != null && h.isHealthy;
                      return _StatusPill(
                        label: ok ? 'LIVE' : l10n.readyStatus,
                        color: ok ? palette.statusClear : palette.accentPrimary,
                      );
                    },
                    loading: () => _StatusPill(label: 'SYNCING', color: palette.textSecondary),
                    error: (_, __) => const KartaOfflineStatusPill(
                      mode: KartaConnectivityVisualMode.offlineRoutingActive,
                      compact: true,
                    ),
                  ),
                if (isWideViewport) ...<Widget>[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: l10n.closeDirections,
                    child: InkWell(
                      key: const ValueKey<String>('karta-close-directions-btn'),
                      onTap: () {
                        ref.read(directionsDrawerOpenProvider.notifier).state = false;
                        ref.read(routePlannerProvider.notifier).clearRoutes();
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.surfaceElevated,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.borderSubtle),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Unified Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onQueryChanged,
              style: KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: Icon(Icons.search_rounded, color: palette.accentPrimary, size: 20),
                suffixIcon: _isSearching
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.accentPrimary,
                          ),
                        ),
                      )
                    : (_searchCtrl.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onQueryChanged('');
                            },
                          )
                        : null),
              ),
            ),
          ),

          // Category Quick-Filter Strip (>= 48dp accessible row height)
          SizedBox(
            height: 52,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, idx) {
                final cat = _categories[idx];
                final active = _selectedCategory == cat.id;
                return InkWell(
                  onTap: () {
                    setState(() => _selectedCategory = active ? null : cat.id);
                    if (_searchCtrl.text.trim().isNotEmpty) {
                      _onQueryChanged(_searchCtrl.text.trim());
                    } else if (!active) {
                      _searchCtrl.text = cat.label;
                      _onQueryChanged(cat.label);
                    }
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? palette.accentGlow : palette.surfaceElevated,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active ? palette.accentPrimary : palette.borderSubtle,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          cat.icon,
                          size: 15,
                          color: active ? palette.accentBright : palette.textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          cat.label,
                          style: KartaTypography.captionLabel.copyWith(
                            color: active ? palette.textPrimary : palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Scrollable Body: Search Results / Dropped Pin / POI Detail / Single-Destination Planner / Routes
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: <Widget>[
                // 1. Live POI & Landmark Search Results
                if (_searchResults.isNotEmpty || _searchMeta != null) ...<Widget>[
                  if (_searchMeta != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _searchMeta!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KartaTypography.monoBadge.copyWith(color: palette.accentBright),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {
                                _searchResults = const <PoiItem>[];
                                _searchMeta = null;
                              });
                            },
                            child: Text(
                              'Clear',
                              style: KartaTypography.bodySecondary.copyWith(
                                color: palette.accentBright,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final poi in _searchResults.take(8))
                    _PoiSearchResultTile(
                      poi: poi,
                      onInspect: () {
                        ref.read(selectedPoiProvider.notifier).state = poi;
                        ref.read(inspectedMapSpotProvider.notifier).state = null;
                        ref.read(kartaMapControllerProvider)
                          ..setDroppedPin(coordinate: poi.coordinate, label: poi.name)
                          ..easeTo(center: poi.coordinate, zoom: 16.2, pitch: 58);
                      },
                      onNavigateTo: () {
                        ref.read(routePlannerProvider.notifier).setDestination(
                              NamedWaypoint(
                                id: 'poi-${poi.id}',
                                label: poi.name,
                                subtitle: poi.brand ?? poi.category,
                                countryCode: poi.countryCode,
                                coordinate: poi.coordinate,
                              ),
                            );
                        _searchCtrl.clear();
                        setState(() {
                          _searchResults = const <PoiItem>[];
                          _searchMeta = null;
                        });
                        ref.read(routePlannerProvider.notifier).computeRoute();
                      },
                    ),
                  const SizedBox(height: 10),
                ],

                // 1b. Curated SEA Landmark / Airport / Sacred Site / Rail Station Guide Card
                if (selectedFeatured != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: KartaFeaturedPlaceInfoCard(
                      place: selectedFeatured,
                      isSaved: authState.isCoordinateSaved(selectedFeatured.coordinate),
                      onClose: () {
                        ref.read(selectedFeaturedPlaceProvider.notifier).state = null;
                        ref.read(kartaMapControllerProvider).setDroppedPin(coordinate: null);
                      },
                      onGoHere: () {
                        ref.read(routePlannerProvider.notifier).setDestination(
                              NamedWaypoint(
                                id: selectedFeatured.id,
                                label: selectedFeatured.name,
                                subtitle: '${selectedFeatured.city} · ${selectedFeatured.countryName}',
                                countryCode: selectedFeatured.countryCode,
                                coordinate: selectedFeatured.coordinate,
                              ),
                            );
                        ref.read(selectedFeaturedPlaceProvider.notifier).state = null;
                        ref.read(routePlannerProvider.notifier).computeRoute();
                      },
                      onStartHere: () {
                        ref.read(routePlannerProvider.notifier).setOrigin(
                              NamedWaypoint(
                                id: selectedFeatured.id,
                                label: selectedFeatured.name,
                                subtitle: '${selectedFeatured.city} · ${selectedFeatured.countryName}',
                                countryCode: selectedFeatured.countryCode,
                                coordinate: selectedFeatured.coordinate,
                              ),
                            );
                        ref.read(selectedFeaturedPlaceProvider.notifier).state = null;
                      },
                      onSave: () async {
                        if (!authState.isAuthenticated) {
                          ref.read(activeNavTabProvider.notifier).state = 'saved';
                          return;
                        }
                        await ref.read(authSavedPlacesProvider.notifier).savePlace(
                              name: selectedFeatured.name,
                              coordinate: selectedFeatured.coordinate,
                              category: selectedFeatured.kind.filterGroup,
                              addressSubtitle:
                                  '${selectedFeatured.city} · ${selectedFeatured.countryName}',
                              countryCode: selectedFeatured.countryCode,
                            );
                      },
                      onLookAround: () {
                        ref.read(lookAroundTargetProvider.notifier).state =
                            StreetLookAroundTarget(
                          coordinate: selectedFeatured.coordinate,
                          title: selectedFeatured.name,
                          subtitle: '${selectedFeatured.city} · ${selectedFeatured.countryName}',
                        );
                      },
                    ),
                  ),

                // 2. Dropped Pin / Unknown Place Inspection Card (Google Maps tap-anywhere)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: (inspectedSpot != null && selectedPoi == null)
                      ? Padding(
                          key: ValueKey<String>(
                            'spot-${inspectedSpot.coordinate.lat.toStringAsFixed(4)}-${inspectedSpot.coordinate.lon.toStringAsFixed(4)}',
                          ),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _InspectedSpotCard(
                            spot: inspectedSpot,
                            isSaved: authState.isCoordinateSaved(inspectedSpot.coordinate),
                            onClose: () {
                              ref.read(inspectedMapSpotProvider.notifier).state = null;
                              ref.read(kartaMapControllerProvider).setDroppedPin(coordinate: null);
                            },
                            onSave: () async {
                              if (!authState.isAuthenticated) {
                                ref.read(activeNavTabProvider.notifier).state = 'saved';
                                return;
                              }
                              await ref.read(authSavedPlacesProvider.notifier).savePlace(
                                    name: inspectedSpot.title,
                                    coordinate: inspectedSpot.coordinate,
                                    category: 'landmark',
                                    addressSubtitle: inspectedSpot.subtitle,
                                    countryCode: inspectedSpot.countryCode,
                                  );
                            },
                            onSetOrigin: () {
                              ref.read(routePlannerProvider.notifier).setOrigin(
                                    NamedWaypoint(
                                      id: 'spot-origin-${inspectedSpot.coordinate.lat.toStringAsFixed(4)}',
                                      label: inspectedSpot.title,
                                      subtitle: inspectedSpot.subtitle,
                                      countryCode: inspectedSpot.countryCode,
                                      coordinate: inspectedSpot.coordinate,
                                    ),
                                  );
                              ref.read(inspectedMapSpotProvider.notifier).state = null;
                            },
                            onNavigateTo: () {
                              ref.read(routePlannerProvider.notifier).setDestination(
                                    NamedWaypoint(
                                      id: 'spot-dest-${inspectedSpot.coordinate.lat.toStringAsFixed(4)}',
                                      label: inspectedSpot.title,
                                      subtitle: inspectedSpot.subtitle,
                                      countryCode: inspectedSpot.countryCode,
                                      coordinate: inspectedSpot.coordinate,
                                    ),
                                  );
                              ref.read(inspectedMapSpotProvider.notifier).state = null;
                              ref.read(routePlannerProvider.notifier).computeRoute();
                            },
                            onLookAround: () {
                              ref.read(lookAroundTargetProvider.notifier).state =
                                  StreetLookAroundTarget(
                                coordinate: inspectedSpot.coordinate,
                                title: inspectedSpot.title,
                                subtitle: inspectedSpot.subtitle ?? 'Street View',
                              );
                            },
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey<String>('spot-empty')),
                ),

                // 3. Detailed POI / Landmark Card (when a POI is selected)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: selectedPoi != null
                      ? Padding(
                          key: ValueKey<String>('poi-detail-${selectedPoi.id}'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PoiDetailCard(
                            poi: selectedPoi,
                            isSaved: authState.isCoordinateSaved(selectedPoi.coordinate),
                            onClose: () {
                              ref.read(selectedPoiProvider.notifier).state = null;
                              ref.read(kartaMapControllerProvider).setDroppedPin(coordinate: null);
                            },
                            onSave: () async {
                              if (!authState.isAuthenticated) {
                                ref.read(activeNavTabProvider.notifier).state = 'saved';
                                return;
                              }
                              await ref.read(authSavedPlacesProvider.notifier).savePlace(
                                    name: selectedPoi.name,
                                    coordinate: selectedPoi.coordinate,
                                    category: 'favorite',
                                    addressSubtitle: selectedPoi.brand ?? selectedPoi.category,
                                    countryCode: selectedPoi.countryCode,
                                    poiId: selectedPoi.id,
                                  );
                            },
                            onSetOrigin: () {
                              ref.read(routePlannerProvider.notifier).setOrigin(
                                    NamedWaypoint(
                                      id: 'poi-${selectedPoi.id}',
                                      label: selectedPoi.name,
                                      subtitle: selectedPoi.brand ?? selectedPoi.category,
                                      countryCode: selectedPoi.countryCode,
                                      coordinate: selectedPoi.coordinate,
                                    ),
                                  );
                              ref.read(selectedPoiProvider.notifier).state = null;
                            },
                            onNavigateTo: () {
                              ref.read(routePlannerProvider.notifier).setDestination(
                                    NamedWaypoint(
                                      id: 'poi-${selectedPoi.id}',
                                      label: selectedPoi.name,
                                      subtitle: selectedPoi.brand ?? selectedPoi.category,
                                      countryCode: selectedPoi.countryCode,
                                      coordinate: selectedPoi.coordinate,
                                    ),
                                  );
                              ref.read(selectedPoiProvider.notifier).state = null;
                              ref.read(routePlannerProvider.notifier).computeRoute();
                            },
                            onLookAround: () {
                              ref.read(lookAroundTargetProvider.notifier).state =
                                  StreetLookAroundTarget(
                                coordinate: selectedPoi.coordinate,
                                title: selectedPoi.name,
                                subtitle:
                                    '${selectedPoi.category.toUpperCase()} · ${selectedPoi.countryCode ?? 'MY'}',
                              );
                            },
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey<String>('poi-empty')),
                ),

                // 4. Single-Destination Route Planner (Start -> Destination only)
                _SingleDestinationSection(planner: planner, liveLocation: liveLoc),

                const SizedBox(height: 12),

                // 5. Route Comparison Deck (ETA, Distance, Corridor, Traffic)
                const RouteComparisonDeck(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label, style: KartaTypography.monoBadge.copyWith(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

class _PoiSearchResultTile extends StatelessWidget {
  const _PoiSearchResultTile({
    required this.poi,
    required this.onInspect,
    required this.onNavigateTo,
  });

  final PoiItem poi;
  final VoidCallback onInspect;
  final VoidCallback onNavigateTo;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onTap: onInspect,
          leading: CircleAvatar(
            radius: 17,
            backgroundColor: palette.accentGlow,
            child: Icon(_iconForCategory(poi.category), size: 17, color: palette.accentBright),
          ),
          title: Text(
            poi.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
          ),
          subtitle: Text(
            <String>[
              if (poi.brand != null) poi.brand!,
              poi.category.replaceAll('_', ' '),
              if (poi.countryCode != null) poi.countryCode!,
              if (poi.distanceMeters != null)
                '${(poi.distanceMeters! / 1000).toStringAsFixed(1)} km',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
          ),
          trailing: IconButton(
            tooltip: 'Set as destination',
            constraints: const BoxConstraints(
              minWidth: KartaSpacing.minTouchTarget,
              minHeight: KartaSpacing.minTouchTarget,
            ),
            icon: Icon(Icons.directions_rounded, color: palette.accentPrimary, size: 22),
            onPressed: onNavigateTo,
          ),
        ),
      ),
    );
  }

  static IconData _iconForCategory(String cat) {
    return switch (cat) {
      'fuel' => Icons.local_gas_station_rounded,
      'ev_charging' => Icons.ev_station_rounded,
      'rest_area' => Icons.local_cafe_rounded,
      'food' => Icons.restaurant_rounded,
      'transit' => Icons.train_rounded,
      'shopping' => Icons.shopping_bag_rounded,
      'healthcare' => Icons.local_hospital_rounded,
      'parking' => Icons.local_parking_rounded,
      _ => Icons.place_rounded,
    };
  }
}

class _InspectedSpotCard extends StatelessWidget {
  const _InspectedSpotCard({
    required this.spot,
    required this.isSaved,
    required this.onClose,
    required this.onSave,
    required this.onSetOrigin,
    required this.onNavigateTo,
    required this.onLookAround,
  });

  final InspectedMapSpot spot;
  final bool isSaved;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final VoidCallback onSetOrigin;
  final VoidCallback onNavigateTo;
  final VoidCallback onLookAround;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.statusAlert.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.location_pin, color: palette.statusAlert, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      spot.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KartaTypography.sectionTitle.copyWith(color: palette.textPrimary),
                    ),
                    if (spot.subtitle != null)
                      Text(
                        spot.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss pin',
                constraints: const BoxConstraints(
                  minWidth: KartaSpacing.minTouchTarget,
                  minHeight: KartaSpacing.minTouchTarget,
                ),
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 20, color: palette.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onNavigateTo,
                  icon: const Icon(Icons.navigation_rounded, size: 17),
                  label: const Text('Go Here'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onSetOrigin,
                child: const Text('Start Here'),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                tooltip: isSaved ? 'Saved in Your Places' : 'Save Landmark / Place',
                constraints: const BoxConstraints(
                  minWidth: KartaSpacing.minTouchTarget,
                  minHeight: KartaSpacing.minTouchTarget,
                ),
                onPressed: onSave,
                icon: Icon(
                  isSaved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                  size: 20,
                  color: isSaved ? palette.statusCaution : palette.accentBright,
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                tooltip: 'Street-Level Look-Around',
                constraints: const BoxConstraints(
                  minWidth: KartaSpacing.minTouchTarget,
                  minHeight: KartaSpacing.minTouchTarget,
                ),
                onPressed: onLookAround,
                icon: Icon(Icons.streetview_rounded, size: 20, color: palette.accentBright),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PoiDetailCard extends StatelessWidget {
  const _PoiDetailCard({
    required this.poi,
    required this.isSaved,
    required this.onClose,
    required this.onSave,
    required this.onSetOrigin,
    required this.onNavigateTo,
    required this.onLookAround,
  });

  final PoiItem poi;
  final bool isSaved;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final VoidCallback onSetOrigin;
  final VoidCallback onNavigateTo;
  final VoidCallback onLookAround;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.accentPrimary.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      poi.name,
                      style: KartaTypography.sectionTitle.copyWith(color: palette.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${poi.brand ?? poi.category.toUpperCase()} · ${poi.countryCode ?? 'MY'} · ${poi.coordinate.lat.toStringAsFixed(4)}, ${poi.coordinate.lon.toStringAsFixed(4)}',
                      style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close place card',
                constraints: const BoxConstraints(
                  minWidth: KartaSpacing.minTouchTarget,
                  minHeight: KartaSpacing.minTouchTarget,
                ),
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 20, color: palette.textSecondary),
              ),
            ],
          ),
          if (poi.openingHours != null) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(Icons.schedule_rounded, size: 15, color: palette.statusClear),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    poi.openingHours!,
                    style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (poi.evMetadata != null && poi.evMetadata!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: poi.evMetadata!.entries
                  .map(
                    (e) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: palette.statusInfo.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${e.key.toUpperCase()}: ${e.value}',
                        style: KartaTypography.monoBadge.copyWith(
                          fontSize: 11,
                          color: palette.statusInfo,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onNavigateTo,
                  icon: const Icon(Icons.navigation_rounded, size: 17),
                  label: const Text('Navigate'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onSetOrigin,
                child: const Text('Set Start'),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                tooltip: isSaved ? 'Saved in Your Places' : 'Save Place',
                constraints: const BoxConstraints(
                  minWidth: KartaSpacing.minTouchTarget,
                  minHeight: KartaSpacing.minTouchTarget,
                ),
                onPressed: onSave,
                icon: Icon(
                  isSaved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                  size: 20,
                  color: isSaved ? palette.statusCaution : palette.accentBright,
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                tooltip: 'Street-Level Look-Around',
                constraints: const BoxConstraints(
                  minWidth: KartaSpacing.minTouchTarget,
                  minHeight: KartaSpacing.minTouchTarget,
                ),
                onPressed: onLookAround,
                icon: Icon(Icons.streetview_rounded, size: 20, color: palette.accentBright),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SingleDestinationSection extends ConsumerWidget {
  const _SingleDestinationSection({
    required this.planner,
    required this.liveLocation,
  });

  final RoutePlannerState planner;
  final LiveLocationSnapshot liveLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final notifier = ref.read(routePlannerProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceElevated.withValues(alpha: palette.isDaylight ? 0.92 : 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'ROUTE · START TO DESTINATION',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
                ),
              ),
              IconButton(
                tooltip: 'Use My Live GPS Location as Start',
                constraints: const BoxConstraints(
                  minWidth: KartaSpacing.minTouchTarget,
                  minHeight: KartaSpacing.minTouchTarget,
                ),
                onPressed: () {
                  ref.read(liveLocationProvider.notifier).locateAndCenter(setAsOrigin: true);
                },
                icon: Icon(
                  liveLocation.hasLiveFix
                      ? Icons.my_location_rounded
                      : Icons.location_searching_rounded,
                  size: 19,
                  color: liveLocation.hasLiveFix ? palette.statusInfo : palette.accentBright,
                ),
              ),
              IconButton(
                tooltip: 'Swap Start and Destination',
                constraints: const BoxConstraints(
                  minWidth: KartaSpacing.minTouchTarget,
                  minHeight: KartaSpacing.minTouchTarget,
                ),
                onPressed: notifier.reverseStops,
                icon: Icon(Icons.swap_vert_rounded, size: 20, color: palette.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Origin (A)
          _EndpointRow(
            badgeText: 'A',
            badgeColor: planner.origin.isCurrentLocation ? palette.statusInfo : palette.statusClear,
            endpoint: planner.origin,
            isLiveGps: planner.origin.isCurrentLocation,
            onLookAround: () {
              final s = planner.origin;
              ref.read(lookAroundTargetProvider.notifier).state = StreetLookAroundTarget(
                coordinate: s.coordinate,
                title: s.label,
                subtitle: s.subtitle ?? 'Start Location',
              );
            },
          ),
          const SizedBox(height: 6),

          // Destination (B)
          _EndpointRow(
            badgeText: 'B',
            badgeColor: palette.statusAlert,
            endpoint: planner.destination,
            isLiveGps: false,
            onLookAround: () {
              final s = planner.destination;
              ref.read(lookAroundTargetProvider.notifier).state = StreetLookAroundTarget(
                coordinate: s.coordinate,
                title: s.label,
                subtitle: s.subtitle ?? 'Destination',
              );
            },
          ),

          const SizedBox(height: 10),

          // Single-Destination Travel Mode Chips (No Avoid Tolls)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final prof in const <RoutingProfileId>[
                  RoutingProfileId.driveFastest,
                  RoutingProfileId.driveNoHighways,
                  RoutingProfileId.driveMotorcycle,
                  RoutingProfileId.transit,
                  RoutingProfileId.cycle,
                  RoutingProfileId.walk,
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        prof.label,
                        style: KartaTypography.bodySecondary.copyWith(
                          fontSize: 12,
                          color: planner.profile == prof
                              ? palette.textPrimary
                              : palette.textSecondary,
                          fontWeight:
                              planner.profile == prof ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      selected: planner.profile == prof,
                      onSelected: (_) => notifier.setProfile(prof),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Primary Compute Live Route CTA
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: planner.isComputing ? null : notifier.computeRoute,
              icon: planner.isComputing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: onPrimary,
                      ),
                    )
                  : const Icon(Icons.alt_route_rounded, size: 18),
              label: Text(
                planner.isComputing ? 'Computing Route...' : 'Compute Live Route',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          if (planner.errorMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              planner.errorMessage!,
              style: KartaTypography.bodySecondary.copyWith(color: palette.statusAlert),
            ),
          ],
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.badgeText,
    required this.badgeColor,
    required this.endpoint,
    required this.isLiveGps,
    required this.onLookAround,
  });

  final String badgeText;
  final Color badgeColor;
  final NamedWaypoint endpoint;
  final bool isLiveGps;
  final VoidCallback onLookAround;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLiveGps ? palette.statusInfo.withValues(alpha: 0.6) : palette.borderSubtle,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: badgeColor),
            ),
            child: isLiveGps
                ? Icon(Icons.my_location_rounded, size: 13, color: badgeColor)
                : Text(
                    badgeText,
                    style: KartaTypography.monoBadge.copyWith(fontSize: 11, color: badgeColor),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  endpoint.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KartaTypography.bodyPrimary.copyWith(
                    fontSize: 13.5,
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  endpoint.subtitle ??
                      '${endpoint.countryCode ?? 'GPS'} · ${endpoint.coordinate.lat.toStringAsFixed(4)}, ${endpoint.coordinate.lon.toStringAsFixed(4)}',
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
          IconButton(
            tooltip: 'Street Look-Around',
            constraints: const BoxConstraints(
              minWidth: KartaSpacing.minTouchTarget,
              minHeight: KartaSpacing.minTouchTarget,
            ),
            onPressed: onLookAround,
            icon: Icon(Icons.streetview_rounded, size: 18, color: palette.accentBright),
          ),
        ],
      ),
    );
  }
}
