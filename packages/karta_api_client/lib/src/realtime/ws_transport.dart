import 'dart:async';

abstract class KartaWebSocketHandle {
  Stream<String> get messages;
  Stream<void> get onClosed;
  bool get isOpen;
  void sendText(String payload);
  Future<void> close();
}
