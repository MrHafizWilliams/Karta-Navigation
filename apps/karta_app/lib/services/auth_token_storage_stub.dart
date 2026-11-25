String? _inMemoryToken;

String? readPersistedAuthToken() => _inMemoryToken;

void writePersistedAuthToken(String? token) {
  _inMemoryToken = token;
}
