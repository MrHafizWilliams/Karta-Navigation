import 'dart:async';
import 'dart:io';

import 'ws_transport.dart';

Future<KartaWebSocketHandle> connectPlatformWebSocket(String url) async {
  final socket = await WebSocket.connect(url);
  socket.pingInterval = const Duration(seconds: 25);
  return _IoWebSocketHandle(socket);
}

class _IoWebSocketHandle implements KartaWebSocketHandle {
  _IoWebSocketHandle(this._socket) {
    _socket.listen(
      (dynamic data) {
        if (data is String && !_msgCtrl.isClosed) {
          _msgCtrl.add(data);
        }
      },
      onDone: _handleClose,
      onError: (_) => _handleClose(),
      cancelOnError: true,
    );
  }

  final WebSocket _socket;
  final StreamController<String> _msgCtrl = StreamController<String>.broadcast();
  final StreamController<void> _closeCtrl = StreamController<void>.broadcast();
  bool _closed = false;

  @override
  Stream<String> get messages => _msgCtrl.stream;

  @override
  Stream<void> get onClosed => _closeCtrl.stream;

  @override
  bool get isOpen => !_closed && _socket.readyState == WebSocket.open;

  @override
  void sendText(String payload) {
    if (isOpen) {
      _socket.add(payload);
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
      await _socket.close();
    } catch (_) {}
  }
}
