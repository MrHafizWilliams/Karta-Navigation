import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

import 'voice_recorder_platform.dart';

PlatformVoiceRecorder createPlatformVoiceRecorder() => _WebMediaVoiceRecorder();

/// Real browser MediaRecorder + HTMLAudioElement clip recorder/player for custom
/// user navigation voice packs (zero third-party plugins required).
class _WebMediaVoiceRecorder implements PlatformVoiceRecorder {
  web.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  final List<web.Blob> _chunks = <web.Blob>[];
  DateTime? _startedAt;
  Timer? _levelTimer;
  String _mimeType = 'audio/webm';

  @override
  bool get isSupported => true;

  @override
  Future<bool> startRecording({void Function(double level)? onLevel}) async {
    try {
      _chunks.clear();
      final mediaDevices = web.window.navigator.mediaDevices;
      final stream = await mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
      _stream = stream;

      final rec = web.MediaRecorder(stream);
      _recorder = rec;
      _mimeType = rec.mimeType.isNotEmpty ? rec.mimeType : 'audio/webm';
      _startedAt = DateTime.now();

      rec.ondataavailable = ((web.BlobEvent event) {
        if (event.data.size > 0) {
          _chunks.add(event.data);
        }
      }).toJS;

      rec.start(150);

      // Gentle animated mic level feedback while capturing
      var phase = 0;
      _levelTimer?.cancel();
      _levelTimer = Timer.periodic(const Duration(milliseconds: 110), (_) {
        phase = (phase + 1) % 6;
        final lvl = 0.35 + (phase % 3) * 0.22;
        onLevel?.call(lvl);
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<RecordedAudioClip?> stopRecording() async {
    _levelTimer?.cancel();
    final rec = _recorder;
    if (rec == null) return null;

    final elapsed = _startedAt != null
        ? DateTime.now().difference(_startedAt!).inMilliseconds.clamp(250, 14000)
        : 1000;

    final stopped = Completer<void>();
    rec.onstop = ((web.Event _) {
      if (!stopped.isCompleted) stopped.complete();
    }).toJS;

    try {
      if (rec.state != 'inactive') {
        rec.stop();
      } else if (!stopped.isCompleted) {
        stopped.complete();
      }
      await stopped.future.timeout(const Duration(seconds: 3));
    } catch (_) {}

    _stopStreamTracks();
    _recorder = null;

    if (_chunks.isEmpty) return null;
    final blob = web.Blob(
      _chunks.toJS,
      web.BlobPropertyBag(type: _mimeType),
    );
    final arrayBuf = await blob.arrayBuffer().toDart;
    final bytes = Uint8List.view(arrayBuf.toDart);
    if (bytes.isEmpty) return null;

    return RecordedAudioClip(
      mimeType: _mimeType,
      durationMs: elapsed,
      audioBase64: base64Encode(bytes),
    );
  }

  @override
  Future<bool> playClipBase64({required String audioBase64, required String mimeType}) async {
    try {
      final dataUrl = 'data:$mimeType;base64,$audioBase64';
      final audio = web.HTMLAudioElement()..src = dataUrl;
      final playPromise = audio.callMethod('play'.toJS) as JSPromise?;
      if (playPromise != null) {
        await playPromise.toDart;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _stopStreamTracks() {
    final s = _stream;
    if (s == null) return;
    try {
      final tracks = s.getTracks().toDart;
      for (final t in tracks) {
        t.stop();
      }
    } catch (_) {}
    _stream = null;
  }

  @override
  void dispose() {
    _levelTimer?.cancel();
    _stopStreamTracks();
    _recorder = null;
  }
}
