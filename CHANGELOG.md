# Changelog

BearFuel follows semantic versioning. Android build numbers increase for every
published APK.

## [0.2.8] - 2026-08-28

- Fixed the last-known map location distance using a hardcoded Jingmen coordinate.
- Fixed record time-range boundaries, weather snapshot fallback, and forecast cold-start rate limiting.
- Fixed stale backup version metadata, swallowed calculation write failures, and missing cached-price labeling.
- Release automation now builds unsigned split Android APKs and an unsigned iOS IPA while retaining local signing support.

## [0.2.6] - 2026-08-28

- Updated release automation to publish Android all-architecture APK and iOS unsigned IPA only.
- Removed the first-run application identifier migration notice.
- Raised Android version to `0.2.6+17`.

## [0.2.7] - 2026-08-28

- Published separate Android APKs for `armeabi-v7a`, `arm64-v8a`, and `x86_64`.
- Divided settings into service and backup sections.
- Raised Android version to `0.2.7+18`.

## [0.2.5] - 2026-08-28

- Rebuilt the application UI around a shared light and dark design system.
- Migrated all visible application icons to Lucide and removed emoji from UI.
- Improved dashboard, navigation, settings, fuel-price, and station-picker UI.
- Kept the Android release target limited to `arm64-v8a` by default.
- Added a permanent self-managed Android release-signing configuration.
- Added GitHub CI and tag-driven release automation.

[0.2.5]: https://github.com/1378944437/BearFuel/releases/tag/v0.2.5
