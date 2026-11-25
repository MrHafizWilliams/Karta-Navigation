import 'package:flutter/material.dart';
import 'package:karta_design_system/karta_design_system.dart';

import '../automotive/automotive_privacy_thermal_panel.dart';
import 'vehicle_customization_panel.dart';
import 'voice_pack_studio_panel.dart';

/// Unified Personalization & Automotive Studio combining the 3D Vehicle Studio,
/// Navigation Voice Pack Studio, and CarPlay/Android Auto Link, Location Privacy Guard,
/// and Thermal Governor.
class KartaStudioPanel extends StatefulWidget {
  const KartaStudioPanel({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<KartaStudioPanel> createState() => _KartaStudioPanelState();
}

class _KartaStudioPanelState extends State<KartaStudioPanel> {
  late int _tabIndex;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final headerIcon = switch (_tabIndex) {
      0 => Icons.directions_car_filled_rounded,
      1 => Icons.record_voice_over_rounded,
      _ => Icons.shield_rounded,
    };
    final headerSubtitle = switch (_tabIndex) {
      0 => '3D Vehicle Mesh & Telemetry Beacon',
      1 => 'Voice Packs & Custom User Voice Recording',
      _ => 'CarPlay / Android Auto · Privacy · Thermal FPS',
    };

    return KartaSurfaceCard(
      padding: EdgeInsets.zero,
      borderRadius: KartaSpacing.radiusLg,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: <Widget>[
                Icon(
                  headerIcon,
                  color: palette.accentPrimary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Karta Driver Studio',
                        style: KartaTypography.sectionTitle.copyWith(color: palette.textPrimary),
                      ),
                      Text(
                        headerSubtitle,
                        style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: <Widget>[
                _StudioTabButton(
                  label: '3D Vehicle',
                  selected: _tabIndex == 0,
                  onTap: () => setState(() => _tabIndex = 0),
                ),
                const SizedBox(width: 6),
                _StudioTabButton(
                  label: 'Voice Packs',
                  selected: _tabIndex == 1,
                  onTap: () => setState(() => _tabIndex = 1),
                ),
                const SizedBox(width: 6),
                _StudioTabButton(
                  label: 'Auto & Privacy',
                  selected: _tabIndex == 2,
                  onTap: () => setState(() => _tabIndex = 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: palette.borderSubtle),
          Expanded(
            child: switch (_tabIndex) {
              0 => const VehicleCustomizationPanel(),
              1 => const VoicePackStudioPanel(),
              _ => const AutomotivePrivacyThermalPanel(),
            },
          ),
        ],
      ),
    );
  }
}

class _StudioTabButton extends StatelessWidget {
  const _StudioTabButton({
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
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: KartaSpacing.minTouchTarget),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? palette.accentGlow : palette.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? palette.accentPrimary : palette.borderSubtle,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KartaTypography.captionLabel.copyWith(
                fontSize: 11.5,
                color: selected ? palette.textPrimary : palette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
