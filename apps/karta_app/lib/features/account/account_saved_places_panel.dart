import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_design_system/karta_design_system.dart';

import '../../state/auth_saved_places_providers.dart';
import '../../state/karta_app_state.dart';

/// User Account (Login / Register) & Saved Places / Landmarks Hub.
class AccountSavedPlacesPanel extends ConsumerStatefulWidget {
  const AccountSavedPlacesPanel({super.key});

  @override
  ConsumerState<AccountSavedPlacesPanel> createState() => _AccountSavedPlacesPanelState();
}

class _AccountSavedPlacesPanelState extends ConsumerState<AccountSavedPlacesPanel> {
  bool _registerMode = false;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _customPlaceNameCtrl = TextEditingController();
  String _customCategory = 'landmark';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _customPlaceNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitAuth() async {
    final notifier = ref.read(authSavedPlacesProvider.notifier);
    final email = _emailCtrl.text.trim();
    final pass = _passwordCtrl.text;
    if (email.isEmpty || pass.isEmpty) return;

    final ok = _registerMode
        ? await notifier.register(
            email: email,
            displayName: _nameCtrl.text.trim().isEmpty
                ? email.split('@').first
                : _nameCtrl.text.trim(),
            password: pass,
          )
        : await notifier.login(email: email, password: pass);

    if (ok && mounted) {
      _passwordCtrl.clear();
    }
  }

  Future<void> _saveCurrentMapCenter() async {
    final mapCtrl = ref.read(kartaMapControllerProvider);
    final liveLoc = ref.read(liveLocationProvider);
    final coord = liveLoc.hasLiveFix && liveLoc.coordinate != null
        ? liveLoc.coordinate!
        : mapCtrl.center;
    final defaultLabel = liveLoc.placeLabel ?? 'Pinned Spot';
    final name = _customPlaceNameCtrl.text.trim().isEmpty
        ? defaultLabel
        : _customPlaceNameCtrl.text.trim();

    final ok = await ref.read(authSavedPlacesProvider.notifier).savePlace(
          name: name,
          coordinate: coord,
          category: _customCategory,
          addressSubtitle:
              '${coord.lat.toStringAsFixed(5)}, ${coord.lon.toStringAsFixed(5)}',
          countryCode: liveLoc.countryCode ?? 'MY',
        );
    if (ok && mounted) {
      _customPlaceNameCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final auth = ref.watch(authSavedPlacesProvider);

    return KartaSurfaceCard(
      padding: EdgeInsets.zero,
      deepGlass: true,
      child: Column(
        children: <Widget>[
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: palette.accentGlow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.accentPrimary.withValues(alpha: 0.65)),
                  ),
                  child: Icon(
                    auth.isAuthenticated ? Icons.bookmarks_rounded : Icons.person_add_alt_1_rounded,
                    size: 18,
                    color: palette.accentBright,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        auth.isAuthenticated ? 'Saved Places & Landmarks' : 'Karta Account',
                        style: KartaTypography.sectionTitle.copyWith(color: palette.textPrimary),
                      ),
                      Text(
                        auth.isAuthenticated
                            ? '${auth.user!.displayName} · ${auth.savedPlaces.length} saved'
                            : 'Sign in or register to sync your places & landmarks',
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
                if (auth.isAuthenticated)
                  TextButton(
                    key: const ValueKey<String>('karta-auth-logout-btn'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, KartaSpacing.minTouchTarget),
                    ),
                    onPressed: () => ref.read(authSavedPlacesProvider.notifier).logout(),
                    child: Text(
                      'Sign Out',
                      style: KartaTypography.captionLabel.copyWith(color: palette.statusAlert),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.borderSubtle),

          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: auth.isRestoring
                  ? Center(
                      key: const ValueKey<String>('auth-restoring'),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: palette.accentPrimary,
                      ),
                    )
                  : auth.isAuthenticated
                      ? _buildSavedPlacesBody(context, auth, palette)
                      : _buildAuthFormBody(context, auth, palette),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthFormBody(
    BuildContext context,
    AuthSavedPlacesState auth,
    KartaPalette palette,
  ) {
    return ListView(
      key: const ValueKey<String>('auth-form-view'),
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        // Animated Mode Switcher (Sign In <-> Create Account)
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _AuthTabChip(
                  key: const ValueKey<String>('karta-auth-tab-login'),
                  label: 'Sign In',
                  selected: !_registerMode,
                  onTap: () {
                    setState(() => _registerMode = false);
                    ref.read(authSavedPlacesProvider.notifier).clearFeedback();
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _AuthTabChip(
                  key: const ValueKey<String>('karta-auth-tab-register'),
                  label: 'Create Account',
                  selected: _registerMode,
                  onTap: () {
                    setState(() => _registerMode = true);
                    ref.read(authSavedPlacesProvider.notifier).clearFeedback();
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _registerMode
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    key: const ValueKey<String>('karta-auth-name-field'),
                    controller: _nameCtrl,
                    style: KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Full Name / Driver Name',
                      prefixIcon: Icon(Icons.badge_outlined, size: 19),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        TextField(
          key: const ValueKey<String>('karta-auth-email-field'),
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Email Address',
            hintText: 'driver@karta.my',
            prefixIcon: Icon(Icons.email_outlined, size: 19),
          ),
        ),
        const SizedBox(height: 10),

        TextField(
          key: const ValueKey<String>('karta-auth-password-field'),
          controller: _passwordCtrl,
          obscureText: true,
          onSubmitted: (_) => _submitAuth(),
          style: KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
          decoration: InputDecoration(
            labelText: _registerMode ? 'Password (min 6 chars)' : 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
          ),
        ),

        if (auth.errorMessage != null) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.statusAlert.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.statusAlert.withValues(alpha: 0.55)),
            ),
            child: Text(
              auth.errorMessage!,
              style: KartaTypography.bodySecondary.copyWith(color: palette.statusAlert),
            ),
          ),
        ],

        if (auth.statusMessage != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            auth.statusMessage!,
            style: KartaTypography.bodySecondary.copyWith(color: palette.statusClear),
          ),
        ],

        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey<String>('karta-auth-submit-btn'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, KartaSpacing.minTouchTarget),
            ),
            onPressed: auth.isBusy ? null : _submitAuth,
            icon: auth.isBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_registerMode ? Icons.person_add_rounded : Icons.login_rounded, size: 18),
            label: Text(_registerMode ? 'Create Karta Account' : 'Sign In to Karta'),
          ),
        ),

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.surfaceElevated.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'WITH A KARTA ACCOUNT YOU CAN:',
                style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
              ),
              const SizedBox(height: 6),
              _BenefitRow(
                icon: Icons.home_rounded,
                text: 'Pin Home, Work, Favorites & Landmarks to your map',
                palette: palette,
              ),
              const SizedBox(height: 4),
              _BenefitRow(
                icon: Icons.bookmark_add_rounded,
                text: 'Bookmark any tapped road, building, or POI in 1 tap',
                palette: palette,
              ),
              const SizedBox(height: 4),
              _BenefitRow(
                icon: Icons.navigation_rounded,
                text: 'Launch instant Start → Destination GPS routing to saved spots',
                palette: palette,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSavedPlacesBody(
    BuildContext context,
    AuthSavedPlacesState auth,
    KartaPalette palette,
  ) {
    final notifier = ref.read(authSavedPlacesProvider.notifier);
    final places = auth.filteredPlaces;

    return ListView(
      key: const ValueKey<String>('saved-places-view'),
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        // Quick Save Current Location / Map Center Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.accentPrimary.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'QUICK SAVE PLACE OR LANDMARK',
                style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey<String>('karta-quick-save-name'),
                controller: _customPlaceNameCtrl,
                style: KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Name (e.g. Home, Penang Hill, Office...)',
                  prefixIcon: Icon(Icons.bookmark_add_outlined, size: 18),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final cat in const <(String, String, IconData)>[
                    ('home', 'Home', Icons.home_rounded),
                    ('work', 'Work', Icons.work_rounded),
                    ('favorite', 'Favorite', Icons.star_rounded),
                    ('landmark', 'Landmark', Icons.flag_rounded),
                  ])
                    ChoiceChip(
                      avatar: Icon(cat.$3, size: 14),
                      label: Text(cat.$2),
                      selected: _customCategory == cat.$1,
                      onSelected: (_) => setState(() => _customCategory = cat.$1),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey<String>('karta-quick-save-submit'),
                  onPressed: auth.isBusy ? null : _saveCurrentMapCenter,
                  icon: const Icon(Icons.add_location_alt_rounded, size: 17),
                  label: const Text('Save Current Location / Map Spot'),
                ),
              ),
            ],
          ),
        ),

        if (auth.statusMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            auth.statusMessage!,
            style: KartaTypography.bodySecondary.copyWith(color: palette.statusClear),
          ),
        ],
        if (auth.errorMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            auth.errorMessage!,
            style: KartaTypography.bodySecondary.copyWith(color: palette.statusAlert),
          ),
        ],

        const SizedBox(height: 12),
        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final f in const <(String, String)>[
                ('all', 'All'),
                ('home', 'Home'),
                ('work', 'Work'),
                ('favorite', 'Favorites'),
                ('landmark', 'Landmarks'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f.$2),
                    selected: auth.selectedCategoryFilter == f.$1,
                    onSelected: (_) => notifier.setCategoryFilter(f.$1),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (places.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surfaceElevated.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.borderSubtle),
            ),
            child: Column(
              children: <Widget>[
                Icon(Icons.bookmarks_outlined, size: 30, color: palette.textSecondary),
                const SizedBox(height: 8),
                Text(
                  'No saved places yet',
                  style: KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap any landmark, POI pin, or road on the map and tap "Save", or save your current spot above.',
                  textAlign: TextAlign.center,
                  style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < places.length; i++)
            TweenAnimationBuilder<double>(
              key: ValueKey<String>('saved-${places[i].id}'),
              tween: Tween<double>(begin: 0, end: 1),
              duration: Duration(milliseconds: 200 + (i * 55).clamp(0, 220)),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
              ),
              child: _SavedPlaceTile(
                place: places[i],
                onGoHere: () {
                  final p = places[i];
                  final planner = ref.read(routePlannerProvider.notifier);
                  planner.setDestination(
                    NamedWaypoint(
                      id: 'saved-${p.id}',
                      label: p.name,
                      subtitle: p.addressSubtitle ?? p.category,
                      countryCode: p.countryCode ?? 'MY',
                      coordinate: p.coordinate,
                    ),
                  );
                  ref.read(activeNavTabProvider.notifier).state = 'navigate';
                  planner.computeRoute();
                },
                onLocate: () {
                  final p = places[i];
                  ref.read(kartaMapControllerProvider).easeTo(
                        center: p.coordinate,
                        zoom: 16.0,
                        pitch: 48,
                      );
                  ref.read(kartaMapControllerProvider).setDroppedPin(
                        coordinate: p.coordinate,
                        label: p.name,
                      );
                },
                onDelete: () => notifier.deleteSavedPlace(places[i].id),
              ),
            ),
      ],
    );
  }
}

class _AuthTabChip extends StatelessWidget {
  const _AuthTabChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.accentPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: KartaTypography.bodyPrimary.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Theme.of(context).colorScheme.onPrimary : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.text,
    required this.palette,
  });

  final IconData icon;
  final String text;
  final KartaPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 15, color: palette.accentBright),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: KartaTypography.bodySecondary.copyWith(
              fontSize: 12,
              color: palette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SavedPlaceTile extends StatelessWidget {
  const _SavedPlaceTile({
    required this.place,
    required this.onGoHere,
    required this.onLocate,
    required this.onDelete,
  });

  final SavedPlaceItem place;
  final VoidCallback onGoHere;
  final VoidCallback onLocate;
  final VoidCallback onDelete;

  static IconData _iconForCategory(String cat) => switch (cat.toLowerCase()) {
        'home' => Icons.home_rounded,
        'work' => Icons.work_rounded,
        'landmark' => Icons.flag_rounded,
        _ => Icons.star_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          InkWell(
            onTap: onLocate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: palette.statusCaution.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.statusCaution.withValues(alpha: 0.5)),
              ),
              child: Icon(
                _iconForCategory(place.category),
                size: 19,
                color: palette.statusCaution,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onLocate,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KartaTypography.bodyPrimary.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  Text(
                    place.addressSubtitle ??
                        '${place.category.toUpperCase()} · ${place.coordinate.lat.toStringAsFixed(4)}, ${place.coordinate.lon.toStringAsFixed(4)}',
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
          ),
          IconButton(
            tooltip: 'Navigate here',
            constraints: const BoxConstraints(
              minWidth: KartaSpacing.minTouchTarget,
              minHeight: KartaSpacing.minTouchTarget,
            ),
            onPressed: onGoHere,
            icon: Icon(Icons.directions_rounded, size: 20, color: palette.accentBright),
          ),
          IconButton(
            tooltip: 'Delete saved place',
            constraints: const BoxConstraints(
              minWidth: KartaSpacing.minTouchTarget,
              minHeight: KartaSpacing.minTouchTarget,
            ),
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded, size: 19, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
