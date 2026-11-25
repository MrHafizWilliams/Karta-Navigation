import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_map_engine/karta_map_engine.dart';

import '../../state/karta_app_state.dart';

/// 3D Vehicle & Karta Pin Customization Studio syncing live to MapLibre's
/// WebGL2 Custom 3D Vehicle Layer.
class VehicleCustomizationPanel extends ConsumerWidget {
  const VehicleCustomizationPanel({super.key});

  static const List<({String name, String hex, Color color})> _accents = [
    (name: 'Karta Teal', hex: '#5B9A94', color: Color(0xFF5B9A94)),
    (name: 'Arctic Cyan', hex: '#4CC9F0', color: Color(0xFF4CC9F0)),
    (name: 'Amber Pulse', hex: '#E6A23C', color: Color(0xFFE6A23C)),
    (name: 'Crisp Silver', hex: '#F4F6F8', color: Color(0xFFF4F6F8)),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final mapCtrl = ref.watch(kartaMapControllerProvider);
    final style = mapCtrl.vehicleCustomization;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        // Live Avatar Hero Preview
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                palette.surfaceElevated,
                palette.accentPrimary.withValues(alpha: palette.isDaylight ? 0.14 : 0.18),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.accentPrimary.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.surfaceCard,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _parseHex(style.accentHex),
                    width: style.showHaloRing ? 2.5 : 1,
                  ),
                  boxShadow: style.showHaloRing
                      ? <BoxShadow>[
                          BoxShadow(
                            color: _parseHex(style.accentHex).withValues(alpha: 0.35),
                            blurRadius: 18,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  _iconForAvatar(style.avatar),
                  size: 32,
                  color: _parseHex(style.accentHex),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'ACTIVE 2D NAVIGATION ARROW',
                      style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      style.avatar.name,
                      style: KartaTypography.hudTitle.copyWith(
                        fontSize: 18,
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      style.avatar.subtitle,
                      style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        Text(
          'SELECT 2D ARROW STYLE',
          style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
        ),
        const SizedBox(height: 8),

        for (final avatar in KartaVehicleAvatar.values) ...<Widget>[
          InkWell(
            onTap: () => mapCtrl.updateVehicleCustomization(style.copyWith(avatar: avatar)),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: style.avatar == avatar ? palette.accentGlow : palette.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: style.avatar == avatar ? palette.accentPrimary : palette.borderSubtle,
                ),
              ),
              child: Row(
                children: <Widget>[
                  if (avatar == KartaVehicleAvatar.kartaPin3d)
                    const KartaLogoMark(size: 28)
                  else
                    Icon(_iconForAvatar(avatar), size: 24, color: palette.accentBright),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          avatar.name,
                          style: KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
                        ),
                        Text(
                          avatar.subtitle,
                          style:
                              KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (style.avatar == avatar)
                    Icon(Icons.check_circle_rounded, color: palette.accentBright, size: 20),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 12),
        Text(
          'ACCENT TRIM & GLOW',
          style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final swatch in _accents)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: swatch.color, radius: 7),
                label: Text(
                  swatch.name,
                  style: KartaTypography.bodySecondary.copyWith(
                    fontSize: 12,
                    color: palette.textPrimary,
                  ),
                ),
                selected: style.accentHex.toUpperCase() == swatch.hex.toUpperCase(),
                onSelected: (_) =>
                    mapCtrl.updateVehicleCustomization(style.copyWith(accentHex: swatch.hex)),
              ),
          ],
        ),

        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'GPS Radar Halo Ring',
            style: KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
          ),
          subtitle: Text(
            'Soft radial GPS beacon beneath the 2D navigation arrow',
            style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
          ),
          value: style.showHaloRing,
          activeThumbColor: palette.accentPrimary,
          onChanged: (v) => mapCtrl.updateVehicleCustomization(style.copyWith(showHaloRing: v)),
        ),

        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Text(
              '3D Mesh Scale',
              style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
            ),
            const Spacer(),
            Text(
              '${style.scale.toStringAsFixed(1)}x',
              style: KartaTypography.monoBadge.copyWith(color: palette.textPrimary),
            ),
          ],
        ),
        Slider(
          value: style.scale,
          min: 0.7,
          max: 1.5,
          divisions: 8,
          onChanged: (v) => mapCtrl.updateVehicleCustomization(style.copyWith(scale: v)),
        ),
      ],
    );
  }

  static IconData _iconForAvatar(KartaVehicleAvatar a) {
    return switch (a) {
      KartaVehicleAvatar.kartaPin3d => Icons.location_on_rounded,
      KartaVehicleAvatar.stealthSedan => Icons.directions_car_rounded,
      KartaVehicleAvatar.gtCoupe => Icons.sports_score_rounded,
      KartaVehicleAvatar.evSuv => Icons.electric_car_rounded,
      KartaVehicleAvatar.touringMoto => Icons.two_wheeler_rounded,
    };
  }

  static Color _parseHex(String hex) {
    final clean = hex.replaceAll('#', '');
    return Color(int.tryParse('FF$clean', radix: 16) ?? 0xFF5B9A94);
  }
}
