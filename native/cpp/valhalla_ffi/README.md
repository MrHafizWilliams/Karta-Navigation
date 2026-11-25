# `native/cpp/valhalla_ffi` (Phase 2 — Offline `libvalhalla` C ABI Shim)

Thin C ABI wrapper around Valhalla's `tyr::actor_t` built with CMake + `vcpkg` (`arm64-ios`, `arm64-android`, `x64-windows`, `arm64-osx`, `x64-linux`), reading the regional `valhalla_tiles.tar` packs produced by `pipelines/scripts/05_build_valhalla.sh`.
