import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_map_engine/karta_map_engine.dart';

import '../../state/karta_app_state.dart';

/// Street-Level Look-Around Preview Overlay hooking into [StreetLookAroundService]
/// (Mapillary imagery when configured + live 3D eye-level ground orbit over Karta's
/// PMTiles 3D extruded buildings so users can inspect street geometry even offline).
class StreetLookAroundOverlay extends ConsumerStatefulWidget {
  const StreetLookAroundOverlay({super.key, required this.target});

  final StreetLookAroundTarget target;

  @override
  ConsumerState<StreetLookAroundOverlay> createState() => _StreetLookAroundOverlayState();
}

class _StreetLookAroundOverlayState extends ConsumerState<StreetLookAroundOverlay> {
  late double _headingDeg;
  Future<StreetLookAroundResult>? _future;

  @override
  void initState() {
    super.initState();
    _headingDeg = widget.target.headingDeg;
    _activate();
  }

  @override
  void didUpdateWidget(covariant StreetLookAroundOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.coordinate != widget.target.coordinate) {
      _headingDeg = widget.target.headingDeg;
      _activate();
    }
  }

  void _activate() {
    final svc = ref.read(streetLookAroundServiceProvider);
    _future = svc.fetchNearestPreview(
      coordinate: widget.target.coordinate,
      headingDeg: _headingDeg,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(kartaMapControllerProvider).setLookAroundOrbit(
            center: widget.target.coordinate,
            bearingDeg: _headingDeg,
            active: true,
          );
    });
  }

  void _close() {
    ref.read(kartaMapControllerProvider).setLookAroundOrbit(
          center: widget.target.coordinate,
          bearingDeg: 0,
          active: false,
        );
    ref.read(lookAroundTargetProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;

    return IgnorePointer(
      ignoring: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: KartaSurfaceCard(
              borderRadius: 18,
              highlighted: true,
              deepGlass: true,
              child: FutureBuilder<StreetLookAroundResult>(
                future: _future,
                builder: (context, snap) {
                  final res = snap.data;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.streetview_rounded, color: palette.accentBright, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'STREET-LEVEL LOOK-AROUND',
                                  style: KartaTypography.captionLabel
                                      .copyWith(color: palette.accentBright),
                                ),
                                Text(
                                  widget.target.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: KartaTypography.sectionTitle
                                      .copyWith(color: palette.textPrimary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close Look-Around',
                            constraints: const BoxConstraints(
                              minWidth: KartaSpacing.minTouchTarget,
                              minHeight: KartaSpacing.minTouchTarget,
                            ),
                            onPressed: _close,
                            icon: Icon(Icons.close_rounded, color: palette.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (res != null &&
                          res.source == LookAroundSource.mapillary &&
                          res.imageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            res.imageUrl!,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: palette.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: palette.borderSubtle),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.view_in_ar_rounded,
                                  color: palette.accentPrimary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Live 3D Ground Perspective active (Pitch 78° · Zoom 18.4). Rotate 360° below to inspect extruded city buildings & junctions.',
                                  style: KartaTypography.bodySecondary
                                      .copyWith(color: palette.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Text(
                            '360° Bearing',
                            style: KartaTypography.bodySecondary
                                .copyWith(color: palette.textSecondary),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_headingDeg.round()}°',
                            style: KartaTypography.monoBadge.copyWith(color: palette.accentBright),
                          ),
                          const Spacer(),
                          Text(
                            '${widget.target.coordinate.lat.toStringAsFixed(5)}, ${widget.target.coordinate.lon.toStringAsFixed(5)}',
                            style: KartaTypography.monoBadge.copyWith(
                              fontSize: 11,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _headingDeg,
                        min: 0,
                        max: 359,
                        onChanged: (deg) {
                          setState(() => _headingDeg = deg);
                          ref.read(kartaMapControllerProvider).setLookAroundOrbit(
                                center: widget.target.coordinate,
                                bearingDeg: deg,
                                active: true,
                              );
                        },
                      ),

                      // Quick 3D Skyline Jump Presets
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          for (final preset in const <NamedWaypoint>[
                            KartaRegionalAnchors.penangKomtar,
                            KartaRegionalAnchors.klcc,
                            KartaRegionalAnchors.marinaBay,
                          ])
                            ActionChip(
                              label: Text(
                                preset.label.split(',').first,
                                style: KartaTypography.captionLabel
                                    .copyWith(color: palette.textPrimary),
                              ),
                              onPressed: () {
                                ref.read(lookAroundTargetProvider.notifier).state =
                                    StreetLookAroundTarget(
                                  coordinate: preset.coordinate,
                                  headingDeg: 25,
                                  title: preset.label,
                                  subtitle: preset.subtitle,
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
