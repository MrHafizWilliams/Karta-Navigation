import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import '../../state/karta_app_state.dart';
import '../../state/phase3_providers.dart';

/// Single-Destination Route Comparison Cards displaying live Valhalla routing
/// algorithm output, animated route computation state, turn-by-turn maneuver preview,
/// distance, primary corridor, and live traffic delays.
class RouteComparisonDeck extends ConsumerWidget {
  const RouteComparisonDeck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final planner = ref.watch(routePlannerProvider);
    final liveLoc = ref.watch(liveLocationProvider);
    final resp = planner.routeResponse;

    if (planner.isComputing) {
      return const _RouteAlgorithmComputingCard();
    }

    if (resp == null || resp.routes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surfaceElevated.withValues(alpha: palette.isDaylight ? 0.9 : 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.borderSubtle),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.route_rounded, color: palette.accentPrimary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tap "Compute Live Route" to run Karta\'s Valhalla routing algorithm and preview turns, live traffic, and ETAs on the map.',
                style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final notifier = ref.read(routePlannerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'ROUTE OPTIONS (${resp.routes.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () =>
                  ref.read(realtimeCrowdsourcingProvider.notifier).toggleFuelOverlay(true),
              icon: Icon(Icons.local_gas_station_rounded, size: 15, color: palette.statusClear),
              label: Text(
                'Fuel Prices',
                style: KartaTypography.captionLabel.copyWith(color: palette.statusClear),
              ),
            ),
            if (resp.cached)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'CACHED',
                  style: KartaTypography.monoBadge.copyWith(
                    fontSize: 11,
                    color: palette.textSecondary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < resp.routes.length; i++) ...<Widget>[
          TweenAnimationBuilder<double>(
            key: ValueKey<String>('route-anim-$i-${resp.routes[i].distanceKm.toStringAsFixed(1)}'),
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 220 + (i * 80).clamp(0, 240)),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 10),
                child: child,
              ),
            ),
            child: _RouteOptionCard(
              route: resp.routes[i],
              isSelected: i == planner.selectedRouteIndex,
              hasLiveGps: liveLoc.hasLiveFix,
              onSelect: () => notifier.selectRouteIndex(i),
              onStartLiveNavigation: () {
                notifier.selectRouteIndex(i);
                notifier.startActiveNavigation(simulate: false);
              },
              onStartPreview: () {
                notifier.selectRouteIndex(i);
                notifier.startActiveNavigation(simulate: true);
              },
            ),
          ),
          if (i < resp.routes.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RouteAlgorithmComputingCard extends StatefulWidget {
  const _RouteAlgorithmComputingCard();

  @override
  State<_RouteAlgorithmComputingCard> createState() => _RouteAlgorithmComputingCardState();
}

class _RouteAlgorithmComputingCardState extends State<_RouteAlgorithmComputingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        return Container(
          key: const ValueKey<String>('karta-route-algorithm-computing'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: palette.accentPrimary.withValues(alpha: 0.45 + _pulseCtrl.value * 0.45),
              width: 1.4,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: palette.accentBright,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Computing Live Route Algorithm…',
                      style: KartaTypography.bodyPrimary.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: palette.borderSubtle,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.accentBright),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Valhalla Bidirectional A* · Road graph snapping · Live traffic & turn geometry',
                style: KartaTypography.bodySecondary.copyWith(
                  fontSize: 11.5,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RouteOptionCard extends StatefulWidget {
  const _RouteOptionCard({
    required this.route,
    required this.isSelected,
    required this.hasLiveGps,
    required this.onSelect,
    required this.onStartLiveNavigation,
    required this.onStartPreview,
  });

  final CandidateRoute route;
  final bool isSelected;
  final bool hasLiveGps;
  final VoidCallback onSelect;
  final VoidCallback onStartLiveNavigation;
  final VoidCallback onStartPreview;

  @override
  State<_RouteOptionCard> createState() => _RouteOptionCardState();
}

class _RouteOptionCardState extends State<_RouteOptionCard> {
  bool _showSteps = false;

  static ({Color color, IconData icon}) _uxBadgeVisual(
    String kind,
    KartaPalette palette,
  ) {
    return switch (kind) {
      'fastest' => (color: palette.accentBright, icon: Icons.bolt_rounded),
      'fewer_turns' => (color: palette.statusInfo, icon: Icons.straight_rounded),
      'avoids_highway' => (color: palette.statusCaution, icon: Icons.park_rounded),
      'shortest' => (color: palette.accentPrimary, icon: Icons.compress_rounded),
      _ => (color: palette.textSecondary, icon: Icons.alt_route_rounded),
    };
  }

  static String _cleanTagLabel(CandidateRoute route) {
    final raw = route.uxPrimaryTag.trim();
    final lower = raw.toLowerCase();
    if (raw.isEmpty || lower.contains('toll')) {
      final dur = RegionalCurrencyFormatter.formatDuration(route.durationSeconds);
      return route.routeIndex == 0 ? 'Fastest · $dur' : 'Alternative · $dur';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final route = widget.route;
    final isSelected = widget.isSelected;
    final eta = DateTime.now().add(Duration(seconds: route.durationSeconds.round()));
    final etaStr = '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
    final uxVis = _uxBadgeVisual(route.uxBadgeKind, palette);
    final uxLabel = _cleanTagLabel(route);
    final allManeuvers = route.legs.expand((l) => l.maneuvers).toList();

    return InkWell(
      onTap: widget.onSelect,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isSelected ? palette.surfaceElevated : palette.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? palette.accentPrimary : palette.borderSubtle,
            width: isSelected ? 1.8 : 1,
          ),
          boxShadow: isSelected
              ? <BoxShadow>[
                  BoxShadow(
                    color: palette.accentPrimary.withValues(alpha: palette.isDaylight ? 0.14 : 0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Scannable UX Differentiation Pill + Primary Corridor
            Row(
              children: <Widget>[
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: uxVis.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: uxVis.color.withValues(alpha: 0.55)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(uxVis.icon, size: 14, color: uxVis.color),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            uxLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KartaTypography.monoBadge.copyWith(
                              fontSize: 11,
                              color: uxVis.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (route.primaryCorridorName != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      route.primaryCorridorName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KartaTypography.bodySecondary.copyWith(
                        fontSize: 11.5,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Duration, ETA, Traffic Delay, Distance
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  RegionalCurrencyFormatter.formatDuration(route.durationSeconds),
                  style: KartaTypography.telemetryValue.copyWith(color: palette.textPrimary),
                ),
                Text(
                  'ETA $etaStr',
                  style: KartaTypography.monoBadge.copyWith(
                    color: palette.accentBright,
                    fontSize: 11.5,
                  ),
                ),
                if (route.liveTrafficDelaySeconds >= 60)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: palette.statusAlert.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+${(route.liveTrafficDelaySeconds / 60).round()}m traffic',
                      style: KartaTypography.monoBadge.copyWith(
                        fontSize: 11,
                        color: palette.statusAlert,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${route.distanceKm.toStringAsFixed(1)} km · Direct route'
              '${route.turnCount > 0 ? ' · ${route.turnCount} ${route.turnCount == 1 ? 'turn' : 'turns'}' : ''}',
              style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
            ),

            // Selected route algorithm telemetry + expandable turn-by-turn preview
            if (isSelected) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: palette.surfaceCard.withValues(alpha: palette.isDaylight ? 0.92 : 0.72),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.borderSubtle),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.alt_route_rounded, size: 15, color: palette.accentBright),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Valhalla Live Route · ${allManeuvers.length} steps · Road-snapped turn arrows active',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KartaTypography.monoBadge.copyWith(
                          fontSize: 10.5,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                    if (allManeuvers.isNotEmpty)
                      InkWell(
                        onTap: () => setState(() => _showSteps = !_showSteps),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                _showSteps ? 'Hide' : 'Steps',
                                style: KartaTypography.captionLabel.copyWith(
                                  color: palette.accentBright,
                                ),
                              ),
                              Icon(
                                _showSteps
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 16,
                                color: palette.accentBright,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                sizeCurve: Curves.easeOutCubic,
                crossFadeState:
                    _showSteps ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: palette.surfaceCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.borderSubtle),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: allManeuvers.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 10,
                      color: palette.borderSubtle.withValues(alpha: 0.6),
                    ),
                    itemBuilder: (context, idx) {
                      final m = allManeuvers[idx];
                      return Row(
                        children: <Widget>[
                          KartaManeuverIcon(valhallaType: m.type, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              m.instruction,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: KartaTypography.bodySecondary.copyWith(
                                fontSize: 11.5,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            RegionalCurrencyFormatter.formatDistance(m.distanceKm * 1000),
                            style: KartaTypography.monoBadge.copyWith(
                              fontSize: 10.5,
                              color: palette.accentBright,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onStartLiveNavigation,
                      icon: const Icon(Icons.navigation_rounded, size: 18),
                      label: const Text(
                        'Start GPS Navigation',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Preview animated drive along route',
                    child: OutlinedButton(
                      onPressed: widget.onStartPreview,
                      child: Text(
                        'Preview',
                        style: KartaTypography.captionLabel.copyWith(color: palette.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
