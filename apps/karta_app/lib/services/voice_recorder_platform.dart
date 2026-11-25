import 'package:flutter/foundation.dart';

@immutable
class RecordedAudioClip {
  const RecordedAudioClip({
    required this.mimeType,
    required this.durationMs,
    required this.audioBase64,
  });

  final String mimeType;
  final int durationMs;
  final String audioBase64;
}

abstract class PlatformVoiceRecorder {
  bool get isSupported;
  Future<bool> startRecording({void Function(double level)? onLevel});
  Future<RecordedAudioClip?> stopRecording();
  Future<bool> playClipBase64({required String audioBase64, required String mimeType});
  void dispose();
}
