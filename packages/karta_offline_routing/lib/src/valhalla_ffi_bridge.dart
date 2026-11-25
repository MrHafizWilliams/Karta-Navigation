/// Cross-platform abstraction over `native/cpp/valhalla_ffi` (`tyr::actor_t`).
/// On native targets (iOS, Android, Windows, macOS, Linux), binds directly to
/// `libkarta_valhalla_ffi` via `dart:ffi` to route offline against downloaded
/// `valhalla_tiles.tar` packs. On Web, cleanly reports unavailable so the router
/// stays on live `karta-api` or cached offline manifests.
abstract class ValhallaOfflineRouter {
  bool get isNativeFfiAvailable;

  Future<bool> initializeWithConfigJson(String valhallaConfigJson);
  Future<String> computeRawRouteJson(String valhallaRequestJson);
  void dispose();
}

class ValhallaOfflineRouterBridge implements ValhallaOfflineRouter {
  bool _initialized = false;

  @override
  bool get isNativeFfiAvailable => false;

  bool get isInitialized => _initialized;

  @override
  Future<bool> initializeWithConfigJson(String valhallaConfigJson) async {
    if (!isNativeFfiAvailable) return false;
    _initialized = true;
    return true;
  }

  @override
  Future<String> computeRawRouteJson(String valhallaRequestJson) async {
    throw UnsupportedError(
      'Offline libvalhalla FFI routing requires native binary libkarta_valhalla_ffi '
      '(built from native/cpp/valhalla_ffi/CMakeLists.txt).',
    );
  }

  @override
  void dispose() {
    _initialized = false;
  }
}
