import 'dart:async';

typedef SpeechTranscriptCallback = void Function(String transcript, bool isFinal);

abstract class PlatformSpeechRecognizer {
  bool get isSupported;
  Future<void> start({
    required String localeTag,
    required SpeechTranscriptCallback onResult,
    required void Function(String error) onError,
    required void Function() onDone,
  });
  Future<void> stop();
}
