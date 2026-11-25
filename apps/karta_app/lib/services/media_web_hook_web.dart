import 'dart:js_interop';
import 'package:web/web.dart' as web;

@JS('KartaAudioChime')
extension type _KartaAudioChimeJs._(JSObject _) implements JSObject {
  external void play(String type);
}

@JS('KartaAudioChime')
external _KartaAudioChimeJs? get _kartaAudioChime;

void speakNavigationCue(
  String cue, {
  String localeTag = 'en-US',
  double rate = 1.02,
  double pitch = 1.0,
}) {
  try {
    final synth = web.window.speechSynthesis;
    synth.cancel();
    final utter = web.SpeechSynthesisUtterance(cue)
      ..lang = localeTag
      ..rate = rate
      ..pitch = pitch;
    synth.speak(utter);
  } catch (_) {}
}

void playKartaChime(String chimeType) {
  try {
    _kartaAudioChime?.play(chimeType);
  } catch (_) {}
}
