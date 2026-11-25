import 'ws_transport.dart';

Future<KartaWebSocketHandle> connectPlatformWebSocket(String url) {
  throw UnsupportedError('WebSocket transport is unavailable on this platform ($url).');
}
