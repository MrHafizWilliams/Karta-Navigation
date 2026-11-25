# `packages/` (Melos-Managed Shared Packages)

Domain-isolated Dart & C++ FFI packages:
- `karta_design_system` — Dark-first automotive/desktop theme (`#0D0F12`, `#181C22`, `#5B9A94`, `#F4F6F8`, `#8E96A0`)
- `karta_api_client` — OpenAPI-generated client from `contracts/openapi/`
- `karta_navigation_core` — Headless GPS map matcher, maneuver state machine, speed/lane alerts & MYR/SGD/BND currency formatter
- `karta_map_engine` — MapLibre abstraction, dark style JSON, offline `.pmtiles` manager
- `karta_offline_routing` — `dart:ffi` wrapper around `native/cpp/valhalla_ffi` (`tyr::actor_t`) + offline SQLite toll engine
- `karta_automotive_bridge` — Pigeon IDL contracts bridging Dart navigation state to Swift CarPlay and Kotlin Android Auto
