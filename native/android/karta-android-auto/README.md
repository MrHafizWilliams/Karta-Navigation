# `native/android/karta-android-auto` (Phase 4 — Android Auto Gradle Library)

Standalone Kotlin Gradle library implementing the Android for Cars App Library (`androidx.car.app:1.7.0`) and offline MapLibre Native Android (`org.maplibre.gl:android-sdk:11.8.0`) surface projection for Karta Navigation (MY / SG / BN).

## Architecture Components

- **`KartaCarAppService.kt`** — Exported `CarAppService` & `KartaCarSession`:
  - Release-safe `HostValidator` allowlist (`hosts_allowlist_sample`), allowing DHU connections in debug builds.
  - Registers `KartaAutoMapSurfaceRenderer` with `AppManager.setSurfaceCallback`, binds `NavigationManagerCallback`, and orchestrates clean Car → Phone handoff + RAM location scrub in `onDestroy`.
- **`KartaNavigationScreen.kt`** — `NavigationTemplate` bound reactively to `KartaAutoStateStore`:
  - Full Valhalla maneuver (1–37) → `Maneuver` mapper with MY/SG/BN clockwise roundabouts (`TYPE_ROUNDABOUT_ENTER_CW`).
  - Recommended turn-lanes (`LaneDirection`) + dark-mode `lanesImage`, traffic-colored `TravelEstimate`, MYR/SGD/BND toll summaries synced to `NavigationManager.updateTrip`, 4-action `ActionStrip`, `MapActionStrip`, and deduplicated `Alert` banners (API ≥ 5).
- **`KartaHazardReportScreen.kt`** — 1-tap `GridTemplate` with Karta's 6 canonical hazard categories (`Police`, `Accident`, `Pothole`, `Stopped Car`, `Debris`, `Closure`).
- **`KartaAutoMapSurfaceRenderer.kt` & `KartaOfflineTileProvider.kt`** — `SurfaceCallback` rendering MapLibre Native Android onto a `VirtualDisplay` + `Presentation` with a localhost-only (`127.0.0.1`) HTTP Range `.pmtiles` proxy for 100% offline rendering, `stableArea` camera padding, pan/fling/scale gestures, and dynamic thermal FPS (`setMaximumFps`) + 3D extrusion shedding.
- **`KartaAutoVoiceController.kt`** — Hands-free voice reporting using `CarAudioRecord` (API ≥ 5) / on-device `SpeechRecognizer` with navigation audio ducking, routing EN / BM / Manglish / Singlish transcripts into Dart's `RegionalVoiceIntentParser`.
- **`KartaAutoThermalGovernor.kt`** — `PowerManager.OnThermalStatusChangedListener` (API 29+) + battery temperature receiver feeding `ThermalAdaptationController`.
- **`KartaAutomotiveBridgeHandler.kt`** — Pure Kotlin bidirectional bridge codec for `com.karta.navigation/automotive_bridge`.

## Android Host Integration & DHU Verification

1. Include `:karta-android-auto` in `android/settings.gradle.kts` and add `implementation(project(":karta-android-auto"))` to `android/app/build.gradle.kts`.
2. Attach `KartaAutomotiveBridgeHandler` to Flutter's `MethodChannel("com.karta.navigation/automotive_bridge")` in `MainActivity.configureFlutterEngine`.
3. Assemble & verify with Google's Desktop Head Unit (`desktop-head-unit`):
   - Enable Android Auto Developer Settings → Start head unit server (`adb forward tcp:5277 tcp:5277`).
   - Run `desktop-head-unit` and verify turn-by-turn cards, lane arrows, offline map surface, Voice & Quick Hazard reporting, and thermal throttling via `adb shell cmd thermalservice override-status 3`.
