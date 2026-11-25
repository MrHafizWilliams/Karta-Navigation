import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

import 'media_web_hook_stub.dart'
    if (dart.library.js_interop) 'media_web_hook_web.dart' as voice_audio;
import 'voice_recorder_platform.dart';
import 'voice_recorder_stub.dart'
    if (dart.library.js_interop) 'voice_recorder_web.dart' as recorder_factory;

/// Decoupled Navigation Voice Pack Engine:
/// - Manages active built-in regional packs (EN, MY EN/BM, SG, Co-Driver, Minimal)
///   and user-created Custom Recorded Voice Packs.
/// - Records & previews real user voice clips per maneuver/safety cue slot and syncs
///   clips to `services/karta-api` (`/v1/voice/packs`).
/// - Automatically plays the user's recorded clip when a navigation cue fires and
///   falls back cleanly to regional TTS.
class NavigationVoiceEngine extends ChangeNotifier {
  NavigationVoiceEngine({
    required KartaApiClient apiClient,
    this.ownerToken = 'karta-driver-default',
  })  : _api = apiClient,
        _recorder = recorder_factory.createPlatformVoiceRecorder();

  final KartaApiClient _api;
  final String ownerToken;
  final PlatformVoiceRecorder _recorder;

  String _activePackId = KartaVoicePackCatalog.builtInPacks.first.id;
  List<CustomVoicePackRecord> _customPacks = <CustomVoicePackRecord>[];
  final Map<String, Map<String, RecordedAudioClip>> _localClips =
      <String, Map<String, RecordedAudioClip>>{};

  String? _recordingPackId;
  String? _recordingCueKey;
  double _recordingLevel = 0.0;
  String? _statusMessage;
  bool _isSyncing = false;

  String get activePackId => _activePackId;
  List<CustomVoicePackRecord> get customPacks => List.unmodifiable(_customPacks);
  String? get recordingPackId => _recordingPackId;
  String? get recordingCueKey => _recordingCueKey;
  bool get isRecording => _recordingCueKey != null;
  double get recordingLevel => _recordingLevel;
  String? get statusMessage => _statusMessage;
  bool get isSyncing => _isSyncing;

  NavigationVoicePack get activePack {
    for (final p in KartaVoicePackCatalog.builtInPacks) {
      if (p.id == _activePackId) return p;
    }
    for (final cp in _customPacks) {
      if (cp.id == _activePackId) {
        final localKeys = _localClips[cp.id]?.keys ?? const <String>[];
        final mergedKeys = <String>{...cp.recordedCues, ...localKeys}.toList();
        return NavigationVoicePack(
          id: cp.id,
          name: cp.name,
          subtitle: 'Custom User Recording · ${mergedKeys.length}/${cp.totalCueSlots} cues',
          localeTag: cp.locale,
          speechRate: 1.0,
          speechPitch: 1.0,
          isCustom: true,
          recordedClipKeys: mergedKeys,
        );
      }
    }
    return KartaVoicePackCatalog.builtInPacks.first;
  }

  bool hasRecordedClip(String packId, String cueKey) {
    if (_localClips[packId]?.containsKey(cueKey) == true) return true;
    for (final cp in _customPacks) {
      if (cp.id == packId && cp.recordedCues.contains(cueKey)) return true;
    }
    return false;
  }

  void selectPack(String packId) {
    _activePackId = packId;
    _statusMessage = 'Active voice pack: ${activePack.name}';
    notifyListeners();
  }

  Future<void> refreshCustomPacks() async {
    _isSyncing = true;
    notifyListeners();
    try {
      final fetched = await _api.listVoicePacks(ownerToken: ownerToken, includeAudio: true);
      _customPacks = fetched;
      for (final pack in fetched) {
        final bucket = _localClips.putIfAbsent(pack.id, () => <String, RecordedAudioClip>{});
        for (final entry in pack.clips.entries) {
          if (entry.value.audioBase64 != null && entry.value.audioBase64!.isNotEmpty) {
            bucket[entry.key] = RecordedAudioClip(
              mimeType: entry.value.mimeType,
              durationMs: entry.value.durationMs,
              audioBase64: entry.value.audioBase64!,
            );
          }
        }
      }
    } catch (_) {
      // Keep local packs available even if offline
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<CustomVoicePackRecord> createCustomPack({
    required String name,
    String locale = 'en-MY',
  }) async {
    try {
      final created = await _api.createVoicePack(
        ownerToken: ownerToken,
        name: name.trim(),
        locale: locale,
      );
      _customPacks = <CustomVoicePackRecord>[created, ..._customPacks];
      _activePackId = created.id;
      _statusMessage = 'Created custom voice pack "${created.name}"';
      notifyListeners();
      return created;
    } catch (_) {
      final now = DateTime.now();
      final local = CustomVoicePackRecord(
        id: 'local-pack-${now.millisecondsSinceEpoch}',
        ownerToken: ownerToken,
        name: name.trim(),
        locale: locale,
        baseTtsVoice: 'karta_studio_en',
        createdAt: now,
        updatedAt: now,
      );
      _customPacks = <CustomVoicePackRecord>[local, ..._customPacks];
      _activePackId = local.id;
      _statusMessage = 'Created local custom pack "${local.name}"';
      notifyListeners();
      return local;
    }
  }

  Future<void> startRecordingCue({required String packId, required String cueKey}) async {
    if (isRecording) {
      await stopRecordingCue();
    }
    _recordingPackId = packId;
    _recordingCueKey = cueKey;
    _recordingLevel = 0.25;
    _statusMessage = 'Recording "$cueKey"... tap Stop when done';
    notifyListeners();

    final ok = await _recorder.startRecording(
      onLevel: (lvl) {
        _recordingLevel = lvl;
        notifyListeners();
      },
    );
    if (!ok) {
      _recordingPackId = null;
      _recordingCueKey = null;
      _recordingLevel = 0.0;
      _statusMessage = 'Microphone permission needed to record custom voice clips.';
      notifyListeners();
    }
  }

  Future<void> stopRecordingCue() async {
    final packId = _recordingPackId;
    final cueKey = _recordingCueKey;
    _recordingPackId = null;
    _recordingCueKey = null;
    _recordingLevel = 0.0;
    notifyListeners();

    if (packId == null || cueKey == null) return;
    final clip = await _recorder.stopRecording();
    if (clip == null) {
      _statusMessage = 'No audio captured — try holding a bit longer.';
      notifyListeners();
      return;
    }

    _localClips.putIfAbsent(packId, () => <String, RecordedAudioClip>{})[cueKey] = clip;
    _customPacks = _customPacks.map((p) {
      if (p.id != packId) return p;
      final cues = <String>{...p.recordedCues, cueKey}.toList()..sort();
      return CustomVoicePackRecord(
        id: p.id,
        ownerToken: p.ownerToken,
        name: p.name,
        locale: p.locale,
        baseTtsVoice: p.baseTtsVoice,
        recordedCues: cues,
        totalCueSlots: p.totalCueSlots,
        clips: p.clips,
        createdAt: p.createdAt,
        updatedAt: DateTime.now(),
      );
    }).toList();
    _statusMessage = 'Saved clip "$cueKey" (${(clip.durationMs / 1000).toStringAsFixed(1)}s)';
    notifyListeners();

    if (!packId.startsWith('local-pack-')) {
      try {
        await _api.uploadVoiceClip(
          packId: packId,
          cueKey: cueKey,
          mimeType: clip.mimeType,
          durationMs: clip.durationMs,
          audioBase64: clip.audioBase64,
        );
      } catch (_) {}
    }
  }

  Future<void> previewCue({
    required String packId,
    required String cueKey,
    required String fallbackPrompt,
  }) async {
    final clip = _localClips[packId]?[cueKey];
    if (clip != null) {
      final played = await _recorder.playClipBase64(
        audioBase64: clip.audioBase64,
        mimeType: clip.mimeType,
      );
      if (played) return;
    }
    final pack = activePack;
    final styled = KartaVoicePackCatalog.formatPromptForPack(pack, fallbackPrompt, cueKey: cueKey);
    voice_audio.speakNavigationCue(
      styled,
      localeTag: pack.localeTag,
      rate: pack.speechRate,
      pitch: pack.speechPitch,
    );
  }

  Future<void> deleteClip({required String packId, required String cueKey}) async {
    _localClips[packId]?.remove(cueKey);
    _customPacks = _customPacks.map((p) {
      if (p.id != packId) return p;
      final cues = p.recordedCues.where((k) => k != cueKey).toList();
      return CustomVoicePackRecord(
        id: p.id,
        ownerToken: p.ownerToken,
        name: p.name,
        locale: p.locale,
        baseTtsVoice: p.baseTtsVoice,
        recordedCues: cues,
        totalCueSlots: p.totalCueSlots,
        clips: p.clips,
        createdAt: p.createdAt,
        updatedAt: DateTime.now(),
      );
    }).toList();
    notifyListeners();
    if (!packId.startsWith('local-pack-')) {
      try {
        await _api.deleteVoiceClip(packId: packId, cueKey: cueKey);
      } catch (_) {}
    }
  }

  /// Dispatches an active turn-by-turn maneuver or hazard voice event through the
  /// selected voice pack (custom audio clip -> regional TTS fallback).
  Future<void> speakNavigationEvent(NavigationVoiceEvent event, {required bool muted}) async {
    final pack = activePack;
    if (pack.minimalMode && !event.isUrgentSafety && event.cueKey == 'straight') {
      return;
    }
    if (muted) return;

    if (pack.isCustom) {
      final clip = _localClips[pack.id]?[event.cueKey];
      if (clip != null) {
        final played = await _recorder.playClipBase64(
          audioBase64: clip.audioBase64,
          mimeType: clip.mimeType,
        );
        if (played) return;
      }
    }

    final styled = KartaVoicePackCatalog.formatPromptForPack(
      pack,
      event.text,
      cueKey: event.cueKey,
    );
    voice_audio.speakNavigationCue(
      styled,
      localeTag: pack.localeTag,
      rate: pack.speechRate,
      pitch: pack.speechPitch,
    );
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }
}
