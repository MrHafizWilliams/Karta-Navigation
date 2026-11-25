# `native/ios/KartaCarPlay` (Phase 4 — Apple CarPlay Swift Package)

Standalone Swift Package implementing Apple CarPlay projection for Karta Navigation (MY / SG / BN), strictly decoupled from Flutter UI widgets and compliant with Apple's CarPlay Driver Distraction Guidelines.

## Architecture Components

- **`KartaCarPlaySceneDelegate.swift`** — `CPTemplateApplicationSceneDelegate` & `CPMapTemplateDelegate`:
  - Navigation bar capped at 2 leading (`Report`, `Voice`) + 2 trailing (`Mute`, `End`) buttons.
  - Map buttons capped at 4 (`Recenter`, `Zoom +`, `Zoom −`, `Pan`).
  - 1-tap `CPGridTemplate` for Karta's 6 canonical hazard categories (`Police`, `Accident`, `Pothole`, `Stopped Car`, `Debris`, `Closure`) with zero scrolling, template depth guard (`<= 2`), and 12s inactivity auto-dismiss.
  - Full `CPNavigationSession` with `CPManeuver`, iOS 17.4+ `CPLaneGuidance` (+ iOS 15–17.3 `junctionImage` fallback), MY/SG/BN toll/ETA summaries (`RM`, `$`, `B$`), and deduplicated `CPNavigationAlert` prompts.
- **`KartaCarPlayMapViewController.swift`** — Mounts MapLibre Native iOS (`MLNMapView`) into `CPWindow.rootViewController` with Karta Dark v1 styling (`#0D0F12` / `#181C22` / `#5B9A94`), offline PMTiles/TileJSON binding, congestion/hazard layers, safe-area inset camera padding, and dynamic thermal FPS + 3D extrusion shedding.
- **`KartaCarPlayStateStore.swift`** — Thread-safe volatile RAM-only state store enforcing zero raw GPS disk persistence and instant memory scrubbing on disconnect.
- **`KartaCarPlayVoiceBridge.swift`** — `AVAudioSession` navigation ducking + on-device `SFSpeechRecognizer` capture routed into Dart's `RegionalVoiceIntentParser`.
- **`KartaCarPlayThermalMonitor.swift`** — Streams `ProcessInfo.thermalState` & battery state to `ThermalAdaptationController` with `.critical` local fail-safe capping.
- **`KartaCarPlayFlutterPlugin.swift`** — Optional `FlutterPlugin` binding `com.karta.navigation/automotive_bridge` to `KartaCarPlayStateStore`.

## Xcode Host Integration Checklist

1. Add `native/ios/KartaCarPlay` as a local Swift Package dependency to `Runner.xcodeproj`, and link `maplibre-gl-native-distribution` (`>= 6.8.0`).
2. Merge `Config/KartaCarPlay.entitlements` (`com.apple.developer.carplay-navigation`) into `Runner.entitlements`.
3. Merge `Config/Info.CarPlay.plist` (`UIApplicationSceneManifest`, `UIBackgroundModes`, usage descriptions) into `Runner/Info.plist`.
4. Register `KartaCarPlayFlutterPlugin.register(with: registrar(forPlugin: "KartaCarPlayFlutterPlugin")!)` in `AppDelegate.swift`.
5. Test on macOS with Xcode iOS Simulator → **I/O → External Displays → CarPlay**.
