import 'package:flutter/services.dart';
import 'voice_input_platform.dart';

PlatformSpeechRecognizer createPlatformSpeechRecognizer() => _NativeChannelSpeechRecognizer();

/// Native iOS/Android/Desktop speech recognition hook via `com.karta.navigation/voice_input`
/// MethodChannel (decoupled from Flutter UI widgets).
class _NativeChannelSpeechRecognizer implements PlatformSpeechRecognizer {
  static const MethodChannel _channel = MethodChannel('com.karta.navigation/voice_input');

  @override
  bool get isSupported => false;

  @override
  Future<void> start({
    required String localeTag,
    required SpeechTranscriptCallback onResult,
    required void Function(String error) onError,
    required void Function() onDone,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('listenOnce', <String, dynamic>{
        'locale': localeTag,
      });
      if (result != null && result.isNotEmpty) {
        onResult(result, true);
      }
      onDone();
    } on MissingPluginException {
      onError('On-device speech channel not attached — use hands-free voice command input.');
      onDone();
    } catch (e) {
      onError(e.toString());
      onDone();
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopListening');
    } catch (_) {}
  }
}
