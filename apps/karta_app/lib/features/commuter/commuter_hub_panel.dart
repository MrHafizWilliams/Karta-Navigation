import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_design_system/karta_design_system.dart';

import '../../state/karta_app_state.dart';
import '../../state/phase3_providers.dart';

/// Smart Commuter Hub featuring:
/// 1. Smart Calendar & Facebook Events Sync with live Valhalla Time-to-Leave
///    traffic urgency timelines and 1-tap route / stop insertion.
/// 2. Privacy-First Carpool / Ride-Sharing route matching with clear 500m privacy
///    shield badges, corridor overlap bars, and 1-tap route insertion.
class CommuterHubPanel extends ConsumerStatefulWidget {
  const CommuterHubPanel({super.key});

  @override
  ConsumerState<CommuterHubPanel> createState() => _CommuterHubPanelState();
}

class _CommuterHubPanelState extends ConsumerState<CommuterHubPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // Calendar controllers
  final _eventTitleCtrl = TextEditingController();
  final _eventLocationCtrl = TextEditingController(text: 'Petronas Twin Towers, KLCC');
  final _icsCtrl = TextEditingController();
  bool _showIcsImport = false;

  // Carpool controllers
  final _aliasCtrl = TextEditingController(text: 'Amir (Subang → KLCC)');
  bool _carpoolDriverMode = false;
  int _seats = 3;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(smartCommuterProvider.notifier).evaluateCalendarDepartures();
      ref.read(smartCommuterProvider.notifier).refreshCarpoolOffers();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _eventTitleCtrl.dispose();
    _eventLocationCtrl.dispose();
    _icsCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commuter = ref.watch(smartCommuterProvider);
    final palette = context.kartaPalette;

    return KartaSurfaceCard(
      padding: EdgeInsets.zero,
      borderRadius: 18,
      deepGlass: true,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: palette.accentGlow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.accentPrimary.withValues(alpha: 0.7)),
                  ),
                  child: Icon(Icons.commute_rounded, size: 18, color: palette.accentBright),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Smart Commute Hub',
                        style: KartaTypography.sectionTitle.copyWith(color: palette.textPrimary),
                      ),
                      Text(
                        'Live Traffic Departures & 500m Privacy Carpool',
                        style: KartaTypography.bodySecondary.copyWith(
                          fontSize: 11.5,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabCtrl,
            indicatorColor: palette.accentPrimary,
            labelColor: palette.textPrimary,
            unselectedLabelColor: palette.textSecondary,
            tabs: const <Widget>[
              Tab(text: 'Calendar & Events'),
              Tab(text: 'Privacy Carpool'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: <Widget>[
                _buildCalendarTab(commuter, palette),
                _buildCarpoolTab(commuter, palette),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarTab(SmartCommuterState commuter, KartaPalette palette) {
    final notifier = ref.read(smartCommuterProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        // Mode switcher: Manual Event vs .ics / Facebook Events import
        Row(
          children: <Widget>[
            Expanded(
              child: _SegmentPill(
                label: 'Quick Event',
                icon: Icons.event_rounded,
                selected: !_showIcsImport,
                onTap: () => setState(() => _showIcsImport = false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SegmentPill(
                label: 'Import .ics / FB',
                icon: Icons.calendar_month_rounded,
                selected: _showIcsImport,
                onTap: () => setState(() => _showIcsImport = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.surfaceElevated.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!_showIcsImport) ...<Widget>[
                TextField(
                  controller: _eventTitleCtrl,
                  style: KartaTypography.bodyPrimary.copyWith(
                    fontSize: 13,
                    color: palette.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Event title (e.g. Client Dinner @ KLCC)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _eventLocationCtrl,
                  style: KartaTypography.bodyPrimary.copyWith(
                    fontSize: 13,
                    color: palette.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Venue geocoded via PostGIS (e.g. KLCC, Marina Bay)',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: commuter.isEvaluatingCalendar
                            ? null
                            : () {
                                final title = _eventTitleCtrl.text.trim().isEmpty
                                    ? 'Upcoming KLCC Meeting'
                                    : _eventTitleCtrl.text.trim();
                                final loc = _eventLocationCtrl.text.trim();
                                notifier.addManualCalendarEvent(
                                  title: title,
                                  locationText: loc.isEmpty ? 'KLCC' : loc,
                                  destination: loc.toLowerCase().contains('marina')
                                      ? KartaRegionalAnchors.marinaBay.coordinate
                                      : KartaRegionalAnchors.klcc.coordinate,
                                  startsAt: DateTime.now().add(const Duration(minutes: 55)),
                                );
                                _eventTitleCtrl.clear();
                              },
                        icon: const Icon(Icons.notification_add_rounded, size: 16),
                        label: const Text('Add + Check Traffic'),
                      ),
                    ),
                  ],
                ),
              ] else ...<Widget>[
                TextField(
                  controller: _icsCtrl,
                  maxLines: 4,
                  style: KartaTypography.monoBadge.copyWith(
                    fontSize: 10.5,
                    color: palette.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Paste RFC 5545 .ics (Google Calendar / Apple / Facebook Events export)',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: commuter.isEvaluatingCalendar
                            ? null
                            : () {
                                if (_icsCtrl.text.trim().isNotEmpty) {
                                  notifier.importIcsPayload(
                                    _icsCtrl.text.trim(),
                                    provider: 'facebook_ics',
                                  );
                                }
                              },
                        icon: const Icon(Icons.upload_file_rounded, size: 16),
                        label: const Text('Parse .ics & Compute TTL'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: () {
                        final target = DateTime.now().toUtc().add(const Duration(minutes: 70));
                        final stamp =
                            '${target.year}${target.month.toString().padLeft(2, '0')}${target.day.toString().padLeft(2, '0')}T'
                            '${target.hour.toString().padLeft(2, '0')}${target.minute.toString().padLeft(2, '0')}00Z';
                        _icsCtrl.text =
                            'BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VEVENT\nUID:fb-karta-${target.millisecondsSinceEpoch}\n'
                            'DTSTART:$stamp\nSUMMARY:Facebook Meetup · KLCC Skyline\n'
                            'LOCATION:Petronas Twin Towers, Kuala Lumpur\nGEO:3.1579;101.7116\nEND:VEVENT\nEND:VCALENDAR';
                      },
                      child: Text(
                        'Sample FB .ics',
                        style: KartaTypography.captionLabel.copyWith(color: palette.textPrimary),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        if (commuter.statusMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            commuter.statusMessage!,
            style: KartaTypography.bodySecondary.copyWith(color: palette.accentBright),
          ),
        ],
        if (commuter.errorMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            commuter.errorMessage!,
            style: KartaTypography.bodySecondary.copyWith(color: palette.statusAlert),
          ),
        ],

        const SizedBox(height: 12),
        Text(
          'LIVE TIME-TO-LEAVE ADVISORIES (${commuter.evaluations.length})',
          style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
        ),
        const SizedBox(height: 8),

        if (commuter.isEvaluatingCalendar)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: palette.accentPrimary),
            ),
          )
        else if (commuter.evaluations.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.surfaceElevated.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.borderSubtle),
            ),
            child: Text(
              'Add an event or import an .ics / Facebook Events feed above to compute live Valhalla traffic departure alerts.',
              style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
            ),
          )
        else
          for (final ev in commuter.evaluations) _TimeToLeaveCard(eval: ev),
      ],
    );
  }

  Widget _buildCarpoolTab(SmartCommuterState commuter, KartaPalette palette) {
    final notifier = ref.read(smartCommuterProvider.notifier);
    final planner = ref.watch(routePlannerProvider);
    final defaultOrigin = planner.stops.isNotEmpty
        ? planner.stops.first.coordinate
        : KartaRegionalAnchors.klcc.coordinate;
    final defaultDest = planner.stops.length >= 2
        ? planner.stops.last.coordinate
        : KartaRegionalAnchors.marinaBay.coordinate;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        // Privacy Shield Assurance Strip with Explicit Trust Badges
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.accentGlow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.accentPrimary.withValues(alpha: 0.65)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.verified_user_rounded, size: 18, color: palette.accentBright),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Privacy-First Shield',
                      style: KartaTypography.bodyPrimary.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Home & work addresses are fuzzed to 500 m public transit/R&R zones. Exact rendezvous unlocks only on mutual acceptance.',
                style: KartaTypography.bodySecondary.copyWith(
                  fontSize: 11.5,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  _PrivacyTrustPill(
                    icon: Icons.radar_rounded,
                    label: '500m Privacy Zone',
                    color: palette.accentBright,
                  ),
                  _PrivacyTrustPill(
                    icon: Icons.lock_outline_rounded,
                    label: 'Zero Home Address',
                    color: palette.textSecondary,
                  ),
                  _PrivacyTrustPill(
                    icon: Icons.handshake_rounded,
                    label: 'Mutual Opt-In',
                    color: palette.statusClear,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Driver Offer vs Rider Search Switch
        Row(
          children: <Widget>[
            Expanded(
              child: _SegmentPill(
                label: 'Find Ride',
                icon: Icons.search_rounded,
                selected: !_carpoolDriverMode,
                onTap: () => setState(() => _carpoolDriverMode = false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SegmentPill(
                label: 'Offer Seats',
                icon: Icons.directions_car_rounded,
                selected: _carpoolDriverMode,
                onTap: () => setState(() => _carpoolDriverMode = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Active Corridor Preview & Form
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.surfaceElevated.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _carpoolDriverMode
                    ? 'POST PRIVACY-FUZZED COMMUTE OFFER'
                    : 'MATCH SAME-DIRECTION CORRIDOR (POSTGIS)',
                style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _aliasCtrl,
                style: KartaTypography.bodyPrimary.copyWith(
                  fontSize: 13,
                  color: palette.textPrimary,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Pseudonymous Commuter Alias',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Corridor: ${planner.stops.first.label.split(',').first} → ${planner.stops.last.label.split(',').first}',
                style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
              ),
              if (_carpoolDriverMode) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Text(
                      'Seats available:',
                      style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    for (final s in const <int>[1, 2, 3, 4])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('$s'),
                          selected: _seats == s,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _seats = s),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: commuter.isSearchingCarpool
                      ? null
                      : () {
                          final dep = DateTime.now().add(const Duration(minutes: 30));
                          if (_carpoolDriverMode) {
                            notifier.publishCarpoolOffer(
                              alias: _aliasCtrl.text.trim().isEmpty
                                  ? 'Commuter MY'
                                  : _aliasCtrl.text.trim(),
                              origin: defaultOrigin,
                              destination: defaultDest,
                              departureAt: dep,
                              seatsTotal: _seats,
                              notes: 'Shared fuel split along expressway',
                            );
                          } else {
                            notifier.searchCarpoolMatches(
                              pickup: defaultOrigin,
                              dropoff: defaultDest,
                              departureAt: dep,
                            );
                          }
                        },
                  icon: Icon(
                    _carpoolDriverMode ? Icons.directions_car_rounded : Icons.search_rounded,
                    size: 17,
                  ),
                  label: Text(
                    _carpoolDriverMode
                        ? 'Publish 500m-Shielded Offer'
                        : 'Find Same-Direction Matches',
                  ),
                ),
              ),
            ],
          ),
        ),

        if (commuter.statusMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            commuter.statusMessage!,
            style: KartaTypography.bodySecondary.copyWith(color: palette.accentBright),
          ),
        ],

        if (commuter.carpoolMatches.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'DIRECTIONAL CORRIDOR MATCHES (${commuter.carpoolMatches.length})',
            style: KartaTypography.captionLabel.copyWith(color: palette.statusClear),
          ),
          const SizedBox(height: 6),
          for (final m in commuter.carpoolMatches)
            _CarpoolMatchPreviewCard(
              match: m,
              onInsertIntoRoute: () => notifier.insertCarpoolIntoRoute(m),
              onRequestSeat: () => notifier.requestSeat(
                candidate: m,
                riderAlias: _aliasCtrl.text.trim().isEmpty ? 'Rider MY' : _aliasCtrl.text.trim(),
                pickup: defaultOrigin,
                dropoff: defaultDest,
              ),
              onPreviewZone: () => notifier.previewCarpoolOnMap(m.offer),
            ),
        ],

        if (commuter.activeOffers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'ACTIVE CORRIDOR OFFERS (${commuter.activeOffers.length})',
            style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
          ),
          const SizedBox(height: 6),
          for (final o in commuter.activeOffers.take(6))
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: palette.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.borderSubtle),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                '${o.driverAlias} · ${o.seatsAvailable}/${o.seatsTotal} seats',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: KartaTypography.bodyPrimary.copyWith(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.shield_rounded, size: 13, color: palette.accentBright),
                          ],
                        ),
                        Text(
                          '${o.originLandmarkName} → ${o.destLandmarkName}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: KartaTypography.bodySecondary.copyWith(
                            fontSize: 11,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        o.estimatedSplitFormatted,
                        style: KartaTypography.monoBadge.copyWith(color: palette.accentBright),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                        onPressed: () => notifier.previewCarpoolOnMap(o),
                        child: Text(
                          '500m Zone',
                          style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _TimeToLeaveCard extends ConsumerWidget {
  const _TimeToLeaveCard({required this.eval});

  final TimeToLeaveEvaluation eval;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final badgeColor = switch (eval.urgencyLevel) {
      'running_late' => palette.statusAlert,
      'leave_now' => palette.statusCaution,
      'prepare' => palette.accentBright,
      _ => palette.statusClear,
    };
    final depLocal = eval.recommendedDepartureAt.toLocal();
    final depStr =
        '${depLocal.hour.toString().padLeft(2, '0')}:${depLocal.minute.toString().padLeft(2, '0')}';

    final delayMins = (eval.trafficDelaySeconds / 60).round();
    final baseMins = (eval.baselineDurationSeconds / 60).round().clamp(1, 999);
    final totalSec = (eval.liveTrafficDurationSeconds + eval.event.parkingBufferSec).clamp(1.0, 1e9);
    final baseRatio = (eval.baselineDurationSeconds / totalSec).clamp(0.15, 0.9);
    final delayRatio = (eval.trafficDelaySeconds / totalSec).clamp(0.0, 0.6);

    final sourceLabel = switch (eval.event.provider) {
      'facebook_ics' => 'Facebook Event',
      'ics_url' => 'Calendar .ics',
      _ => 'Smart Event',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: badgeColor.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Source + Traffic badge row (wraps cleanly inside narrow sidebars)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    _PrivacyTrustPill(
                      icon: Icons.calendar_today_rounded,
                      label: sourceLabel,
                      color: palette.textSecondary,
                    ),
                    if (delayMins > 0)
                      _PrivacyTrustPill(
                        icon: Icons.traffic_rounded,
                        label: '+${delayMins}m traffic',
                        color: palette.statusCaution,
                      )
                    else
                      _PrivacyTrustPill(
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Clear flow',
                        color: palette.statusClear,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.55)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: badgeColor),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'LEAVE $depStr',
                      style: KartaTypography.monoBadge.copyWith(fontSize: 10, color: badgeColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),

          Text(
            eval.event.title,
            style: KartaTypography.bodyPrimary.copyWith(
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            eval.advisoryMessage,
            style: KartaTypography.bodySecondary.copyWith(
              fontSize: 11.5,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 8),

          // Visual Traffic Urgency Timeline Bar (Base Drive + Traffic Delay + Parking Buffer)
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: (baseRatio * 100).round().clamp(10, 90),
                    child: ColoredBox(color: palette.accentPrimary),
                  ),
                  if (delayRatio > 0.02)
                    Expanded(
                      flex: (delayRatio * 100).round().clamp(5, 60),
                      child: ColoredBox(
                        color: delayMins >= 10 ? palette.statusAlert : palette.statusCaution,
                      ),
                    ),
                  Expanded(
                    flex: ((1.0 - baseRatio - delayRatio) * 100).round().clamp(5, 40),
                    child: ColoredBox(color: palette.borderStrong.withValues(alpha: 0.55)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          Text(
            '${baseMins + delayMins} min drive · ${eval.distanceKm.toStringAsFixed(1)} km',
            style: KartaTypography.monoBadge.copyWith(fontSize: 11, color: palette.textSecondary),
          ),

          if (eval.event.destination != null) ...<Widget>[
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey<String>('ttl-insert-go-${eval.event.id}'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, KartaSpacing.minTouchTarget),
                  backgroundColor: palette.accentPrimary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: () => ref
                    .read(smartCommuterProvider.notifier)
                    .insertCalendarEventIntoRoute(eval),
                icon: const Icon(Icons.navigation_rounded, size: 16),
                label: Text(
                  'Navigate to Event',
                  style: KartaTypography.bodyPrimary.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CarpoolMatchPreviewCard extends StatelessWidget {
  const _CarpoolMatchPreviewCard({
    required this.match,
    required this.onInsertIntoRoute,
    required this.onRequestSeat,
    required this.onPreviewZone,
  });

  final CarpoolMatchCandidate match;
  final VoidCallback onInsertIntoRoute;
  final VoidCallback onRequestSeat;
  final VoidCallback onPreviewZone;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final overlapFrac = (match.overlapPct / 100.0).clamp(0.05, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.accentPrimary.withValues(alpha: 0.68), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Driver alias + split cost
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  match.offer.driverAlias,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KartaTypography.bodyPrimary.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.statusClear.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  'Split ${match.splitCostFormatted}',
                  style: KartaTypography.monoBadge.copyWith(
                    fontSize: 10,
                    color: palette.statusClear,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Explicit Privacy Badges on every match card
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: <Widget>[
              _PrivacyTrustPill(
                icon: Icons.shield_rounded,
                label: '${match.offer.privacyRadiusM}m Privacy Zone',
                color: palette.accentBright,
              ),
              _PrivacyTrustPill(
                icon: Icons.lock_outline_rounded,
                label: 'Zero Home Address',
                color: palette.textSecondary,
              ),
              _PrivacyTrustPill(
                icon: Icons.verified_rounded,
                label: 'Mutual Opt-In',
                color: palette.statusClear,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Corridor Overlap Meter
          Row(
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: overlapFrac,
                    minHeight: 5.5,
                    backgroundColor: palette.borderSubtle,
                    valueColor: AlwaysStoppedAnimation<Color>(palette.accentPrimary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${match.overlapPct.round()}% shared',
                style: KartaTypography.monoBadge.copyWith(
                  fontSize: 10,
                  color: palette.accentBright,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Public Landmark Pickup -> Dropoff Timeline
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Column(
                children: <Widget>[
                  Icon(Icons.trip_origin_rounded, size: 13, color: palette.accentBright),
                  Container(width: 1.5, height: 14, color: palette.borderStrong),
                  Icon(Icons.flag_rounded, size: 13, color: palette.statusClear),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Pickup: ${match.pickupLandmarkName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KartaTypography.bodySecondary.copyWith(
                        fontSize: 11.5,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dropoff: ${match.dropoffLandmarkName}',
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
            ],
          ),
          const SizedBox(height: 10),

          // One-Tap Direct Route Assignment + Seat Request + 500m Map Preview
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: ValueKey<String>('carpool-insert-route-${match.offer.id}'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, KartaSpacing.minTouchTarget),
                backgroundColor: palette.accentPrimary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: onInsertIntoRoute,
              icon: const Icon(Icons.alt_route_rounded, size: 16),
              label: Text(
                'Set Carpool Route (Pickup → Dropoff)',
                style: KartaTypography.bodyPrimary.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, KartaSpacing.minTouchTarget),
                    backgroundColor: palette.accentGlow,
                    foregroundColor: palette.accentBright,
                  ),
                  onPressed: onRequestSeat,
                  child: Text(
                    'Request Seat',
                    style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, KartaSpacing.minTouchTarget),
                  foregroundColor: palette.textPrimary,
                  side: BorderSide(color: palette.borderStrong),
                ),
                onPressed: onPreviewZone,
                child: Text(
                  'Show 500m Zone',
                  style: KartaTypography.captionLabel.copyWith(color: palette.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyTrustPill extends StatelessWidget {
  const _PrivacyTrustPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: palette.isDaylight ? 0.12 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: KartaTypography.monoBadge.copyWith(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: KartaSpacing.minTouchTarget),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? palette.accentGlow : palette.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? palette.accentPrimary : palette.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 16,
                color: selected ? palette.accentBright : palette.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KartaTypography.captionLabel.copyWith(
                    color: selected ? palette.textPrimary : palette.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
