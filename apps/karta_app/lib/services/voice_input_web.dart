import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

import 'voice_input_platform.dart';

PlatformSpeechRecognizer createPlatformSpeechRecognizer() => _WebSpeechRecognizer();

class _WebSpeechRecognizer implements PlatformSpeechRecognizer {
  JSObject? _recognition;

  JSFunction? get _ctor {
    final win = web.window as JSObject;
    final std = win.getProperty('SpeechRecognition'.toJS);
    if (std != null && !std.isUndefinedOrNull) return std as JSFunction;
    final webkit = win.getProperty('webkitSpeechRecognition'.toJS);
    if (webkit != null && !webkit.isUndefinedOrNull) return webkit as JSFunction;
    return null;
  }

  @override
  bool get isSupported => _ctor != null;

  @override
  Future<void> start({
    required String localeTag,
    required SpeechTranscriptCallback onResult,
    required void Function(String error) onError,
    required void Function() onDone,
  }) async {
    final ctor = _ctor;
    if (ctor == null) {
      onError('Browser SpeechRecognition unavailable — type or pick a quick voice phrase.');
      onDone();
      return;
    }

    try {
      final rec = ctor.callAsConstructor<JSObject>();
      _recognition = rec;
      rec.setProperty('lang'.toJS, localeTag.toJS);
      rec.setProperty('interimResults'.toJS, true.toJS);
      rec.setProperty('maxAlternatives'.toJS, 1.toJS);
      rec.setProperty('continuous'.toJS, false.toJS);

      rec.setProperty(
        'onresult'.toJS,
        ((JSObject evt) {
          try {
            final results = evt.getProperty('results'.toJS) as JSObject?;
            if (results == null) return;
            final len = (results.getProperty('length'.toJS) as JSNumber?)?.toDartInt ?? 0;
            if (len <= 0) return;
            final last = results.getProperty((len - 1).toJS) as JSObject?;
            if (last == null) return;
            final isFinal = (last.getProperty('isFinal'.toJS) as JSBoolean?)?.toDart ?? false;
            final alt0 = last.getProperty(0.toJS) as JSObject?;
            final text = (alt0?.getProperty('transcript'.toJS) as JSString?)?.toDart ?? '';
            if (text.isNotEmpty) {
              onResult(text, isFinal);
            }
          } catch (_) {}
        }).toJS,
      );

      rec.setProperty(
        'onerror'.toJS,
        ((JSObject evt) {
          final code = (evt.getProperty('error'.toJS) as JSString?)?.toDart ?? 'speech_error';
          onError('Voice capture error ($code)');
        }).toJS,
      );

      rec.setProperty('onend'.toJS, (() => onDone()).toJS);
      rec.callMethod('start'.toJS);
    } catch (e) {
      onError('Voice recognition failed: $e');
      onDone();
    }
  }

  @override
  Future<void> stop() async {
    try {
      _recognition?.callMethod('stop'.toJS);
    } catch (_) {}
    _recognition = null;
  }
}
