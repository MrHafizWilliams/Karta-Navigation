import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import '../../state/phase3_providers.dart';

/// Custom Navigation Voice Pack Selector & 12-Cue User Voice Recorder Studio.
/// Supports built-in MY / SG / EN regional packs AND real user audio recording
/// with live waveform meter, instant playback preview, and PostGIS API sync.
class VoicePackStudioPanel extends ConsumerStatefulWidget {
  const VoicePackStudioPanel({super.key});

  @override
  ConsumerState<VoicePackStudioPanel> createState() => _VoicePackStudioPanelState();
}

class _VoicePackStudioPanelState extends ConsumerState<VoicePackStudioPanel> {
  final TextEditingController _packNameCtrl = TextEditingController();
  String? _editingCustomPackId;

  @override
  void dispose() {
    _packNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final engine = ref.watch(navigationVoiceEngineProvider);
    final activePack = engine.activePack;
    final customPacks = engine.customPacks;

    final selectedCustomPack = _editingCustomPackId != null
        ? customPacks.where((p) => p.id == _editingCustomPackId).firstOrNull
        : (customPacks.isNotEmpty ? customPacks.first : null);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        // Active Voice Pack Hero Card
        Container(
          padding: const EdgeInsets.all(14),
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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.surfaceCard,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.accentPrimary, width: 2),
                ),
                child: Icon(
                  activePack.isCustom ? Icons.mic_rounded : Icons.record_voice_over_rounded,
                  color: palette.accentBright,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'ACTIVE NAVIGATION VOICE',
                      style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
                    ),
                    Text(
                      activePack.name,
                      style: KartaTypography.sectionTitle.copyWith(color: palette.textPrimary),
                    ),
                    Text(
                      activePack.subtitle,
                      style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Preview Voice Pack',
                constraints: const BoxConstraints(
                  minWidth: KartaSpacing.minTouchTarget,
                  minHeight: KartaSpacing.minTouchTarget,
                ),
                onPressed: () => engine.previewCue(
                  packId: activePack.id,
                  cueKey: 'turn_left',
                  fallbackPrompt: 'In 400 meters, keep left onto Jalan Ampang.',
                ),
                icon: Icon(Icons.play_arrow_rounded, color: palette.accentBright),
              ),
            ],
          ),
        ),

        if (engine.statusMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            engine.statusMessage!,
            style: KartaTypography.bodySecondary.copyWith(color: palette.accentBright),
          ),
        ],

        const SizedBox(height: 14),
        Text(
          'CUSTOM USER VOICE RECORDER (12 CUE SLOTS)',
          style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
        ),
        const SizedBox(height: 8),

        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _packNameCtrl,
                style: KartaTypography.bodyPrimary.copyWith(
                  fontSize: 13,
                  color: palette.textPrimary,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'New custom voice pack (e.g. My Voice)',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () async {
                final name = _packNameCtrl.text.trim().isEmpty
                    ? 'My Custom Voice'
                    : _packNameCtrl.text.trim();
                final created = await engine.createCustomPack(name: name);
                _packNameCtrl.clear();
                setState(() => _editingCustomPackId = created.id);
              },
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Create'),
            ),
          ],
        ),

        if (customPacks.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final cp in customPacks)
                ChoiceChip(
                  avatar: Icon(
                    Icons.mic_rounded,
                    size: 15,
                    color: engine.activePackId == cp.id
                        ? palette.accentBright
                        : palette.textSecondary,
                  ),
                  label: Text('${cp.name} (${cp.recordedCues.length}/${cp.totalCueSlots})'),
                  selected: selectedCustomPack?.id == cp.id,
                  onSelected: (_) {
                    setState(() => _editingCustomPackId = cp.id);
                    engine.selectPack(cp.id);
                  },
                ),
            ],
          ),
        ],

        if (selectedCustomPack != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Recording Studio: ${selectedCustomPack.name}',
                        style: KartaTypography.bodyPrimary.copyWith(
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${selectedCustomPack.recordedCues.length}/${KartaVoicePackCatalog.customCueSlots.length} cues',
                      style: KartaTypography.monoBadge.copyWith(color: palette.accentBright),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: selectedCustomPack.recordedCues.length /
                      KartaVoicePackCatalog.customCueSlots.length,
                  backgroundColor: palette.backgroundPrimary,
                  color: palette.accentPrimary,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(4),
                ),
                if (engine.isRecording) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Icon(Icons.fiber_manual_record_rounded, size: 14, color: palette.statusAlert),
                      const SizedBox(width: 6),
                      Text(
                        'MIC LEVEL',
                        style: KartaTypography.monoBadge.copyWith(color: palette.textPrimary),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: engine.recordingLevel.clamp(0.1, 1.0),
                          backgroundColor: palette.backgroundPrimary,
                          color: palette.statusAlert,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final slot in KartaVoicePackCatalog.customCueSlots)
            _CueRecorderRow(
              slot: slot,
              packId: selectedCustomPack.id,
              hasClip: engine.hasRecordedClip(selectedCustomPack.id, slot.key),
              isRecordingThis: engine.recordingPackId == selectedCustomPack.id &&
                  engine.recordingCueKey == slot.key,
              onToggleRecord: () {
                if (engine.recordingPackId == selectedCustomPack.id &&
                    engine.recordingCueKey == slot.key) {
                  engine.stopRecordingCue();
                } else {
                  engine.startRecordingCue(packId: selectedCustomPack.id, cueKey: slot.key);
                }
              },
              onPreview: () => engine.previewCue(
                packId: selectedCustomPack.id,
                cueKey: slot.key,
                fallbackPrompt: slot.samplePrompt,
              ),
              onDelete: () => engine.deleteClip(packId: selectedCustomPack.id, cueKey: slot.key),
            ),
        ],

        const SizedBox(height: 16),
        Text(
          'CURATED REGIONAL VOICE PACKS',
          style: KartaTypography.captionLabel.copyWith(color: palette.accentBright),
        ),
        const SizedBox(height: 8),

        for (final pack in KartaVoicePackCatalog.builtInPacks)
          _VoicePackTile(
            title: pack.name,
            subtitle: pack.subtitle,
            badge: pack.localeTag,
            selected: engine.activePackId == pack.id,
            onSelect: () => engine.selectPack(pack.id),
            onPreview: () => engine.previewCue(
              packId: pack.id,
              cueKey: 'turn_left',
              fallbackPrompt: 'In 300 meters, turn left onto Jalan Ampang.',
            ),
          ),
      ],
    );
  }
}

class _VoicePackTile extends StatelessWidget {
  const _VoicePackTile({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.selected,
    required this.onSelect,
    required this.onPreview,
  });

  final String title;
  final String subtitle;
  final String badge;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? palette.accentGlow : palette.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? palette.accentPrimary : palette.borderSubtle,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.check_circle_rounded : Icons.record_voice_over_outlined,
              size: 20,
              color: selected ? palette.accentBright : palette.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          title,
                          style: KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: palette.surfaceCard,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: palette.borderSubtle),
                        ),
                        child: Text(
                          badge,
                          style: KartaTypography.monoBadge.copyWith(
                            fontSize: 11,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    subtitle,
                    style: KartaTypography.bodySecondary.copyWith(
                      fontSize: 11.5,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Preview voice sample',
              constraints: const BoxConstraints(
                minWidth: KartaSpacing.minTouchTarget,
                minHeight: KartaSpacing.minTouchTarget,
              ),
              onPressed: onPreview,
              icon: Icon(Icons.volume_up_rounded, size: 20, color: palette.accentBright),
            ),
          ],
        ),
      ),
    );
  }
}

class _CueRecorderRow extends StatelessWidget {
  const _CueRecorderRow({
    required this.slot,
    required this.packId,
    required this.hasClip,
    required this.isRecordingThis,
    required this.onToggleRecord,
    required this.onPreview,
    required this.onDelete,
  });

  final NavigationVoiceCueSlot slot;
  final String packId;
  final bool hasClip;
  final bool isRecordingThis;
  final VoidCallback onToggleRecord;
  final VoidCallback onPreview;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: isRecordingThis
            ? palette.statusAlert.withValues(alpha: 0.16)
            : palette.surfaceElevated,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: isRecordingThis
              ? palette.statusAlert
              : (hasClip ? palette.statusClear.withValues(alpha: 0.6) : palette.borderSubtle),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            hasClip ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 16,
            color: hasClip ? palette.statusClear : palette.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  slot.label,
                  style: KartaTypography.bodyPrimary.copyWith(
                    fontSize: 12.5,
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  '"${slot.samplePrompt}"',
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
            tooltip: isRecordingThis ? 'Stop Recording' : 'Record Cue',
            constraints: const BoxConstraints(
              minWidth: KartaSpacing.minTouchTarget,
              minHeight: KartaSpacing.minTouchTarget,
            ),
            onPressed: onToggleRecord,
            icon: Icon(
              isRecordingThis ? Icons.stop_circle_rounded : Icons.mic_rounded,
              color: isRecordingThis ? palette.statusAlert : palette.accentBright,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'Preview Clip',
            constraints: const BoxConstraints(
              minWidth: KartaSpacing.minTouchTarget,
              minHeight: KartaSpacing.minTouchTarget,
            ),
            onPressed: onPreview,
            icon: Icon(Icons.play_arrow_rounded, size: 20, color: palette.textPrimary),
          ),
          if (hasClip)
            IconButton(
              tooltip: 'Delete Clip',
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
