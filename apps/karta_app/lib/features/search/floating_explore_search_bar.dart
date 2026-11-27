import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_map_engine/karta_map_engine.dart';

import '../../data/sea_featured_places.dart';
import '../../state/auth_saved_places_providers.dart';
import '../../state/karta_app_state.dart';
import '../places/featured_place_info_card.dart';

/// Google Maps–inspired floating top search pill + horizontal category chips
/// strip rendered directly over the full-bleed 3D map on desktop, tablet, and
/// automotive explore mode.
///
/// Leaves ~95% of the live map completely unobstructed while providing instant
/// POI search, 1-tap category filters, compact dropped-pin/POI inspection, and
/// a signature teal diamond Directions button to expand the route planner.
class KartaFloatingExploreSearchBar extends ConsumerStatefulWidget {
  const KartaFloatingExploreSearchBar({super.key});

  @override
  ConsumerState<KartaFloatingExploreSearchBar> createState() =>
      _KartaFloatingExploreSearchBarState();
}

class _KartaFloatingExploreSearchBarState
    extends ConsumerState<KartaFloatingExploreSearchBar> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  int _searchSeq = 0;
  bool _isSearching = false;
  String? _selectedCategory;
  List<KartaFeaturedPlace> _featuredResults = const <KartaFeaturedPlace>[];
  List<PoiItem> _results = const <PoiItem>[];
  String? _metaText;

  static const Set<String> _featuredFilterGroups = <String>{
    'landmarks',
    'airports',
    'worship',
    'transit',
  };

  List<({String id, String label, IconData icon})> _buildCategories(KartaStrings l10n) => [
        (id: 'landmarks', label: l10n.catLandmarks, icon: Icons.account_balance_rounded),
        (id: 'airports', label: l10n.catAirports, icon: Icons.flight_takeoff_rounded),
        (id: 'worship', label: l10n.catWorship, icon: Icons.mosque_rounded),
        (id: 'transit', label: l10n.catTransit, icon: Icons.train_rounded),
        (id: 'food', label: l10n.catRestaurants, icon: Icons.restaurant_rounded),
        (id: 'fuel', label: l10n.catFuel, icon: Icons.local_gas_station_rounded),
        (id: 'ev_charging', label: l10n.catEv, icon: Icons.ev_station_rounded),
        (id: 'rest_area', label: l10n.catRestArea, icon: Icons.local_cafe_rounded),
        (id: 'shopping', label: l10n.catMalls, icon: Icons.shopping_bag_rounded),
        (id: 'parking', label: l10n.catParking, icon: Icons.local_parking_rounded),
      ];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    _searchSeq += 1;
    final seq = _searchSeq;

    final isFeaturedGroup =
        _selectedCategory != null && _featuredFilterGroups.contains(_selectedCategory);

    if (trimmed.isEmpty && !isFeaturedGroup) {
      setState(() {
        _featuredResults = const <KartaFeaturedPlace>[];
        _results = const <PoiItem>[];
        _metaText = null;
        _isSearching = false;
      });
      return;
    }

    // 1. Instant curated SEA Landmarks / Airports / Religious Sites / Rail Hubs search
    final featuredMatches = SeaFeaturedPlacesCatalog.search(
      query: isFeaturedGroup ? '' : trimmed,
      filterGroup: isFeaturedGroup ? _selectedCategory : null,
      limit: isFeaturedGroup ? 28 : 8,
    );

    if (isFeaturedGroup && trimmed.isEmpty) {
      setState(() {
        _featuredResults = featuredMatches;
        _results = const <PoiItem>[];
        _metaText = '${featuredMatches.length} Southeast Asia places';
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
      category: isFeaturedGroup ? null : _selectedCategory,
      limit: 12,
    );

    final conn = ref.read(connectivityResilienceProvider).current;
    final willRefineOnline = !conn.isOffline && trimmed.length >= 2;
    final totalImmediate = featuredMatches.length + localRes.items.length;

    if (totalImmediate > 0 || !willRefineOnline) {
      setState(() {
        _featuredResults = featuredMatches;
        _results = localRes.items;
        _metaText = totalImmediate > 0
            ? '$totalImmediate places · ${localRes.queryMs.toStringAsFixed(1)} ms'
            : (conn.isOffline ? 'No offline places matched "$trimmed"' : null);
        _isSearching = willRefineOnline && totalImmediate == 0;
      });
      if (localRes.items.isNotEmpty) {
        ref.read(kartaMapControllerProvider).setPois(localRes.items);
      }
    } else {
      setState(() {
        _featuredResults = featuredMatches;
      });
    }

    if (willRefineOnline) {
      _debounce = Timer(
        const Duration(milliseconds: 180),
        () => _runOnlineSearch(trimmed, seq),
      );
    }
  }

  Future<void> _runOnlineSearch(String query, int seq) async {
    if (!mounted || seq != _searchSeq) return;
    if (_results.isEmpty) {
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
        limit: 12,
      );
      conn.recordNetworkSuccess();
      localIndex.upsertAll(resp.items);
      if (!mounted || seq != _searchSeq) return;

      final merged = <PoiItem>[...resp.items];
      final seenIds = resp.items.map((p) => p.id).toSet();
      for (final localItem in _results) {
        if (seenIds.add(localItem.id)) merged.add(localItem);
      }

      setState(() {
        _results = merged;
        _metaText = '${merged.length} places · ${resp.queryMs.toStringAsFixed(1)} ms';
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

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _selectedCategory = null;
      _featuredResults = const <KartaFeaturedPlace>[];
      _results = const <PoiItem>[];
      _metaText = null;
      _isSearching = false;
    });
  }

  IconData _iconForFeaturedKind(KartaPlaceKind kind) {
    return switch (kind) {
      KartaPlaceKind.historicalLandmark => Icons.account_balance_rounded,
      KartaPlaceKind.modernLandmark => Icons.location_city_rounded,
      KartaPlaceKind.airport => Icons.flight_takeoff_rounded,
      KartaPlaceKind.mosque => Icons.mosque_rounded,
      KartaPlaceKind.temple => Icons.temple_buddhist_rounded,
      KartaPlaceKind.church => Icons.church_rounded,
      KartaPlaceKind.railHub || KartaPlaceKind.trainStation => Icons.train_rounded,
    };
  }

  Color _colorForFeaturedKind(KartaPlaceKind kind) {
    return switch (kind) {
      KartaPlaceKind.historicalLandmark => const Color(0xFFD97706),
      KartaPlaceKind.modernLandmark => const Color(0xFF0D9488),
      KartaPlaceKind.airport => const Color(0xFF2563EB),
      KartaPlaceKind.mosque => const Color(0xFF059669),
      KartaPlaceKind.temple => const Color(0xFFEA580C),
      KartaPlaceKind.church => const Color(0xFF7C3AED),
      KartaPlaceKind.railHub || KartaPlaceKind.trainStation => const Color(0xFF0284C7),
    };
  }

  void _openDirectionsWithDestination({
    required String id,
    required String label,
    required Coordinate coord,
    String? subtitle,
    String? countryCode,
  }) {
    ref.read(routePlannerProvider.notifier).setDestination(
          NamedWaypoint(
            id: id,
            label: label,
            subtitle: subtitle,
            countryCode: countryCode,
            coordinate: coord,
          ),
        );
    ref.read(directionsDrawerOpenProvider.notifier).state = true;
    _clearSearch();
  }

  void _openDirectionsWithOrigin({
    required String id,
    required String label,
    required Coordinate coord,
    String? subtitle,
    String? countryCode,
  }) {
    ref.read(routePlannerProvider.notifier).setOrigin(
          NamedWaypoint(
            id: id,
            label: label,
            subtitle: subtitle,
            countryCode: countryCode,
            coordinate: coord,
          ),
        );
    ref.read(directionsDrawerOpenProvider.notifier).state = true;
    _clearSearch();
  }

  Future<void> _savePlace({
    required String name,
    required Coordinate coord,
    String? category,
    String? subtitle,
    String? countryCode,
  }) async {
    final authState = ref.read(authSavedPlacesProvider);
    if (!authState.isAuthenticated) {
      ref.read(activeNavTabProvider.notifier).state = 'saved';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign in or create an account to save places & landmarks.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    final saved = await ref.read(authSavedPlacesProvider.notifier).savePlace(
          name: name,
          coordinate: coord,
          category: category ?? 'landmark',
          addressSubtitle: subtitle,
          countryCode: countryCode,
        );
    if (mounted) {
      final errMsg = ref.read(authSavedPlacesProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Saved "$name" to your Karta Account.'
                : (errMsg ?? 'Could not save "$name" right now.'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final l10n = context.kartaStrings;
    final categories = _buildCategories(l10n);
    final selectedFeatured = ref.watch(selectedFeaturedPlaceProvider);
    final selectedPoi = ref.watch(selectedPoiProvider);
    final inspectedSpot = ref.watch(inspectedMapSpotProvider);
    final authState = ref.watch(authSavedPlacesProvider);
    final mapCtrl = ref.read(kartaMapControllerProvider);
    final isDay = palette.isDaylight;

    final pillBg = isDay ? const Color(0xFFFFFFFF) : const Color(0xF0181C22);
    final pillBorder = isDay
        ? const Color(0x2611161C)
        : palette.borderStrong.withValues(alpha: 0.72);
    final pillShadow = <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: isDay ? 0.14 : 0.42),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final searchWidth = math.min(
          356.0,
          math.max(248.0, constraints.maxWidth * 0.34),
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Top Google Maps-style Row: Floating Pill Search + Floating Pill Category Chips
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                KartaPointerShield(
                  child: Container(
                    key: const ValueKey<String>('karta-floating-search-bar'),
                    width: searchWidth,
                    height: 48,
                    padding: const EdgeInsets.only(left: 10, right: 6),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: pillBorder),
                      boxShadow: pillShadow,
                    ),
                    child: Row(
                      children: <Widget>[
                        const KartaLogoMark(size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: const ValueKey<String>('karta-floating-search-input'),
                            controller: _searchCtrl,
                            onChanged: _onQueryChanged,
                            style: KartaTypography.bodyPrimary.copyWith(
                              fontSize: 13.5,
                              color: palette.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: l10n.searchHint,
                              hintStyle: KartaTypography.bodySecondary.copyWith(
                                fontSize: 13.5,
                                color: palette.textSecondary,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        if (_isSearching)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: palette.accentPrimary,
                              ),
                            ),
                          )
                        else if (_searchCtrl.text.isNotEmpty || _selectedCategory != null)
                          IconButton(
                            tooltip: l10n.clearSearch,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: palette.textSecondary,
                            ),
                            onPressed: _clearSearch,
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: palette.textSecondary,
                            ),
                          ),
                        Container(
                          width: 1,
                          height: 22,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          color: palette.borderSubtle,
                        ),
                        // Signature Google Maps-style Teal Diamond Directions Button
                        Tooltip(
                          message: l10n.directionsTooltip,
                          child: InkWell(
                            key: const ValueKey<String>('karta-directions-btn'),
                            onTap: () {
                              ref.read(directionsDrawerOpenProvider.notifier).state = true;
                            },
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              child: Transform.rotate(
                                angle: math.pi / 4,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: palette.accentPrimary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Transform.rotate(
                                    angle: -math.pi / 4,
                                    child: const Icon(
                                      Icons.turn_right_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Floating Pill Category Chips Row (no giant background box)
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final cat = categories[idx];
                        final active = _selectedCategory == cat.id;
                        return KartaPointerShield(
                          child: InkWell(
                            key: ValueKey<String>('karta-chip-${cat.id}'),
                            onTap: () {
                              if (active) {
                                _clearSearch();
                              } else {
                                setState(() => _selectedCategory = cat.id);
                                if (_featuredFilterGroups.contains(cat.id)) {
                                  _searchCtrl.clear();
                                  _onQueryChanged('');
                                } else {
                                  _searchCtrl.text = cat.label;
                                  _onQueryChanged(cat.label);
                                }
                              }
                            },
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: active ? palette.accentPrimary : pillBg,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: active ? palette.accentBright : pillBorder,
                                ),
                                boxShadow: pillShadow,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    cat.icon,
                                    size: 16,
                                    color: active ? Colors.white : palette.textPrimary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    cat.label,
                                    style: KartaTypography.captionLabel.copyWith(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: active ? Colors.white : palette.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),

            // Floating Search Results Dropdown (curated SEA places + live POIs)
            if (_featuredResults.isNotEmpty || _results.isNotEmpty || _metaText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: KartaPointerShield(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(searchWidth, 380.0),
                      maxHeight: 380,
                    ),
                    child: KartaSurfaceCard(
                      deepGlass: true,
                      borderRadius: 18,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (_metaText != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8, left: 4),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      _metaText!,
                                      style: KartaTypography.captionLabel.copyWith(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: _clearSearch,
                                    borderRadius: BorderRadius.circular(999),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_featuredResults.isNotEmpty || _results.isNotEmpty)
                            Flexible(
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: _featuredResults.length + _results.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: palette.borderSubtle,
                                ),
                                itemBuilder: (context, idx) {
                                  if (idx < _featuredResults.length) {
                                    final place = _featuredResults[idx];
                                    final color = _colorForFeaturedKind(place.kind);
                                    return ListTile(
                                      key: ValueKey<String>('karta-search-feat-${place.id}'),
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      leading: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: color.withValues(alpha: 0.45),
                                          ),
                                        ),
                                        child: Icon(
                                          _iconForFeaturedKind(place.kind),
                                          color: color,
                                          size: 17,
                                        ),
                                      ),
                                      title: Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: Text(
                                              place.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: KartaTypography.bodyPrimary.copyWith(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: palette.textPrimary,
                                              ),
                                            ),
                                          ),
                                          if (place.iataCode != null)
                                            Container(
                                              margin: const EdgeInsets.only(left: 6),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 1.5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1D4ED8),
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                place.iataCode!,
                                                style: KartaTypography.monoBadge.copyWith(
                                                  fontSize: 9.5,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      subtitle: Text(
                                        '${place.city} · ${place.countryName}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: KartaTypography.bodySecondary.copyWith(
                                          fontSize: 11,
                                          color: palette.textSecondary,
                                        ),
                                      ),
                                      onTap: () {
                                        ref.read(selectedFeaturedPlaceProvider.notifier).state =
                                            place;
                                        ref.read(selectedPoiProvider.notifier).state = null;
                                        ref.read(inspectedMapSpotProvider.notifier).state = null;
                                        mapCtrl.setDroppedPin(
                                          coordinate: place.coordinate,
                                          label: place.shortLabel,
                                        );
                                        mapCtrl.easeTo(
                                          center: place.coordinate,
                                          zoom: 15.2,
                                          pitch: mapCtrl.is3DEnabled ? 50 : 0,
                                        );
                                        _clearSearch();
                                      },
                                    );
                                  }

                                  final poi = _results[idx - _featuredResults.length];
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    leading: Icon(
                                      Icons.location_on_rounded,
                                      color: palette.accentBright,
                                      size: 20,
                                    ),
                                    title: Text(
                                      poi.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: KartaTypography.bodyPrimary.copyWith(
                                        fontSize: 13,
                                        color: palette.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      [
                                        if (poi.brand != null) poi.brand!,
                                        poi.category.toUpperCase(),
                                        if (poi.countryCode != null) poi.countryCode!,
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: KartaTypography.bodySecondary.copyWith(
                                        fontSize: 11,
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                    onTap: () {
                                      ref.read(selectedFeaturedPlaceProvider.notifier).state = null;
                                      ref.read(selectedPoiProvider.notifier).state = poi;
                                      ref.read(inspectedMapSpotProvider.notifier).state = null;
                                      mapCtrl.setDroppedPin(
                                        coordinate: poi.coordinate,
                                        label: poi.name,
                                      );
                                      mapCtrl.easeTo(
                                        center: poi.coordinate,
                                        zoom: 16.0,
                                        pitch: mapCtrl.is3DEnabled ? 52 : 0,
                                      );
                                      _clearSearch();
                                    },
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Rich Curated Travel Guide / Airport / Religious Site / Rail Station Card
            if (selectedFeatured != null &&
                _featuredResults.isEmpty &&
                _results.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: math.max(searchWidth, 384.0),
                  child: KartaFeaturedPlaceInfoCard(
                    place: selectedFeatured,
                    isSaved: authState.isCoordinateSaved(selectedFeatured.coordinate),
                    onClose: () {
                      ref.read(selectedFeaturedPlaceProvider.notifier).state = null;
                      mapCtrl.setDroppedPin(coordinate: null);
                    },
                    onGoHere: () {
                      _openDirectionsWithDestination(
                        id: selectedFeatured.id,
                        label: selectedFeatured.name,
                        subtitle: '${selectedFeatured.city} · ${selectedFeatured.countryName}',
                        countryCode: selectedFeatured.countryCode,
                        coord: selectedFeatured.coordinate,
                      );
                      ref.read(selectedFeaturedPlaceProvider.notifier).state = null;
                      ref.read(routePlannerProvider.notifier).computeRoute();
                    },
                    onStartHere: () {
                      _openDirectionsWithOrigin(
                        id: selectedFeatured.id,
                        label: selectedFeatured.name,
                        subtitle: '${selectedFeatured.city} · ${selectedFeatured.countryName}',
                        countryCode: selectedFeatured.countryCode,
                        coord: selectedFeatured.coordinate,
                      );
                      ref.read(selectedFeaturedPlaceProvider.notifier).state = null;
                    },
                    onSave: () {
                      _savePlace(
                        name: selectedFeatured.name,
                        coord: selectedFeatured.coordinate,
                        category: selectedFeatured.kind.filterGroup,
                        subtitle: '${selectedFeatured.city} · ${selectedFeatured.countryName}',
                        countryCode: selectedFeatured.countryCode,
                      );
                    },
                    onLookAround: () {
                      ref.read(lookAroundTargetProvider.notifier).state =
                          StreetLookAroundTarget(
                        coordinate: selectedFeatured.coordinate,
                        headingDeg: mapCtrl.bearing,
                        title: selectedFeatured.name,
                        subtitle: '${selectedFeatured.city} · ${selectedFeatured.countryName}',
                      );
                    },
                  ),
                ),
              ),

            // Compact Floating Dropped Pin / Selected POI Inspection Card
            if (selectedFeatured == null &&
                (selectedPoi != null || inspectedSpot != null) &&
                _featuredResults.isEmpty &&
                _results.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: KartaPointerShield(
                  child: SizedBox(
                    width: searchWidth,
                    child: KartaSurfaceCard(
                      deepGlass: true,
                      borderRadius: 18,
                      padding: const EdgeInsets.all(14),
                      child: _FloatingPlaceCardBody(
                        title: selectedPoi?.name ?? inspectedSpot!.title,
                        subtitle: selectedPoi != null
                            ? [
                                if (selectedPoi.brand != null) selectedPoi.brand!,
                                selectedPoi.category.toUpperCase(),
                                if (selectedPoi.countryCode != null) selectedPoi.countryCode!,
                              ].join(' · ')
                            : (inspectedSpot!.subtitle ?? ''),
                        coordinate: selectedPoi?.coordinate ?? inspectedSpot!.coordinate,
                        onDismiss: () {
                          ref.read(selectedPoiProvider.notifier).state = null;
                          ref.read(inspectedMapSpotProvider.notifier).state = null;
                          mapCtrl.setDroppedPin(coordinate: null);
                        },
                        onGoHere: () {
                          final coord = selectedPoi?.coordinate ?? inspectedSpot!.coordinate;
                          final title = selectedPoi?.name ?? inspectedSpot!.title;
                          _openDirectionsWithDestination(
                            id: selectedPoi != null
                                ? 'poi-${selectedPoi.id}'
                                : 'spot-${coord.lat.toStringAsFixed(5)}',
                            label: title,
                            subtitle: selectedPoi?.category ?? inspectedSpot?.subtitle,
                            countryCode: selectedPoi?.countryCode ?? inspectedSpot?.countryCode,
                            coord: coord,
                          );
                        },
                        onStartHere: () {
                          final coord = selectedPoi?.coordinate ?? inspectedSpot!.coordinate;
                          final title = selectedPoi?.name ?? inspectedSpot!.title;
                          _openDirectionsWithOrigin(
                            id: selectedPoi != null
                                ? 'poi-${selectedPoi.id}'
                                : 'spot-${coord.lat.toStringAsFixed(5)}',
                            label: title,
                            subtitle: selectedPoi?.category ?? inspectedSpot?.subtitle,
                            countryCode: selectedPoi?.countryCode ?? inspectedSpot?.countryCode,
                            coord: coord,
                          );
                        },
                        onSave: () {
                          final coord = selectedPoi?.coordinate ?? inspectedSpot!.coordinate;
                          final title = selectedPoi?.name ?? inspectedSpot!.title;
                          _savePlace(
                            name: title,
                            coord: coord,
                            category: selectedPoi?.category ?? inspectedSpot?.category,
                            subtitle: selectedPoi?.brand ?? inspectedSpot?.subtitle,
                            countryCode: selectedPoi?.countryCode ?? inspectedSpot?.countryCode,
                          );
                        },
                        onLookAround: () {
                          final coord = selectedPoi?.coordinate ?? inspectedSpot!.coordinate;
                          final title = selectedPoi?.name ?? inspectedSpot!.title;
                          ref.read(lookAroundTargetProvider.notifier).state =
                              StreetLookAroundTarget(
                            coordinate: coord,
                            headingDeg: mapCtrl.bearing,
                            title: title,
                            subtitle: '3D Street-Level Look-Around',
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FloatingPlaceCardBody extends StatelessWidget {
  const _FloatingPlaceCardBody({
    required this.title,
    required this.subtitle,
    required this.coordinate,
    required this.onDismiss,
    required this.onGoHere,
    required this.onStartHere,
    required this.onSave,
    required this.onLookAround,
  });

  final String title;
  final String subtitle;
  final Coordinate coordinate;
  final VoidCallback onDismiss;
  final VoidCallback onGoHere;
  final VoidCallback onStartHere;
  final VoidCallback onSave;
  final VoidCallback onLookAround;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.location_on_rounded, color: palette.statusAlert, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KartaTypography.sectionTitle.copyWith(
                      fontSize: 14.5,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
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
            IconButton(
              tooltip: 'Dismiss pin',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.close_rounded, size: 18, color: palette.textSecondary),
              onPressed: onDismiss,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: onGoHere,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: const Size(0, 38),
                ),
                icon: const Icon(Icons.directions_rounded, size: 16),
                label: Text(context.kartaStrings.goHere, style: const TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: onStartHere,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: const Size(0, 38),
              ),
              child: Text(context.kartaStrings.startHere, style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: context.kartaStrings.save,
              onPressed: onSave,
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              style: IconButton.styleFrom(
                side: BorderSide(color: palette.borderSubtle),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(Icons.bookmark_add_outlined, size: 18, color: palette.accentBright),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: context.kartaStrings.lookAround,
              onPressed: onLookAround,
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              style: IconButton.styleFrom(
                side: BorderSide(color: palette.borderSubtle),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(Icons.streetview_rounded, size: 18, color: palette.accentBright),
            ),
          ],
        ),
      ],
    );
  }
}
