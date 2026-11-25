import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'ws_transport.dart';

Future<KartaWebSocketHandle> connectPlatformWebSocket(String url) async {
  final ws = web.WebSocket(url);
  final completer = Completer<KartaWebSocketHandle>();
  final handle = _WebWebSocketHandle(ws);

  ws.onopen = ((web.Event _) {
    if (!completer.isCompleted) completer.complete(handle);
  }).toJS;
  ws.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('WebSocket connection error for $url'));
    }
  }).toJS;

  return completer.future.timeout(const Duration(seconds: 8));
}

class _WebWebSocketHandle implements KartaWebSocketHandle {
  _WebWebSocketHandle(this._ws) {
    _ws.onmessage = ((web.MessageEvent event) {
      final raw = event.data;
      if (raw != null && raw.isA<JSString>() && !_msgCtrl.isClosed) {
        _msgCtrl.add((raw as JSString).toDart);
      }
    }).toJS;
    _ws.onclose = ((web.CloseEvent _) => _handleClose()).toJS;
  }

  final web.WebSocket _ws;
  final StreamController<String> _msgCtrl = StreamController<String>.broadcast();
  final StreamController<void> _closeCtrl = StreamController<void>.broadcast();
  bool _closed = false;

  @override
  Stream<String> get messages => _msgCtrl.stream;

  @override
  Stream<void> get onClosed => _closeCtrl.stream;

  @override
  bool get isOpen => !_closed && _ws.readyState == web.WebSocket.OPEN;

  @override
  void sendText(String payload) {
    if (isOpen) {
      _ws.send(payload.toJS);
    }
  }

  void _handleClose() {
    if (_closed) return;
    _closed = true;
    if (!_closeCtrl.isClosed) _closeCtrl.add(null);
    _msgCtrl.close();
    _closeCtrl.close();
  }

  @override
  Future<void> close() async {
    _handleClose();
    try {
      _ws.close();
    } catch (_) {}
  }
}
