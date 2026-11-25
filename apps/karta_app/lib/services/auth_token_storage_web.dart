import 'package:web/web.dart' as web;

const String _storageKey = 'karta_nav_session_token_v1';

String? readPersistedAuthToken() {
  try {
    final token = web.window.localStorage.getItem(_storageKey);
    if (token == null || token.trim().isEmpty) return null;
    return token.trim();
  } catch (_) {
    return null;
  }
}

void writePersistedAuthToken(String? token) {
  try {
    if (token == null || token.trim().isEmpty) {
      web.window.localStorage.removeItem(_storageKey);
    } else {
      web.window.localStorage.setItem(_storageKey, token.trim());
    }
  } catch (_) {
    // Ignore storage quota / private mode restrictions
  }
}
