String? _inMemoryLanguageCode;

String? readPersistedLanguageCode() => _inMemoryLanguageCode;

void writePersistedLanguageCode(String code) {
  _inMemoryLanguageCode = code;
}
