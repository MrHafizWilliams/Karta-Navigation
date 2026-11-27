import 'package:web/web.dart' as web;

const String _langStorageKey = 'karta_nav_language_v1';

String? readPersistedLanguageCode() {
  try {
    final code = web.window.localStorage.getItem(_langStorageKey);
    if (code == null || code.trim().isEmpty) return null;
    return code.trim();
  } catch (_) {
    return null;
  }
}

void writePersistedLanguageCode(String code) {
  try {
    web.window.localStorage.setItem(_langStorageKey, code.trim());
  } catch (_) {
    // Ignore private mode / storage quota restrictions
  }
}
