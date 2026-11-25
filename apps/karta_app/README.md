# `apps/karta_app` (Phase 2 — Flutter 6-Platform Client)

Single Flutter client targeting **iOS, Android, Windows, macOS, Linux, and Web**.
Consumes shared packages from `packages/` and links native automotive modules from `native/ios/KartaCarPlay` and `native/android/karta-android-auto` via strongly-typed Pigeon contracts (`packages/karta_automotive_bridge`).

UI components here MUST remain strictly decoupled from native GPS and automotive background services.
