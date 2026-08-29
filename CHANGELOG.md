# Changelog

BearFuel follows semantic versioning. Android build numbers increase for every
published APK.

## [0.2.13] - 2026-08-29

### Added

- “关于应用”设置板块：当前版本与 Build 号、GitHub Release 地址与检查更新、应用内更新日志、构建与发布入口。
- 一键发布流水线 `scripts/release.sh`：一条命令完成升版（patch/minor/major）、本地构建（analyze + test + 分架构 Android APK，macOS 附带未签名 iOS IPA）与远端构建（提交、打 tag 并推送，触发 GitHub Actions 发布）。
- 更新日志（CHANGELOG.md）随安装包打包，应用内可直接浏览历届版本变更。

### Changed

- README 重写：补充构建与发布流水线、产物矩阵（签名 APK×3 + 未签名 IPA）与签名配置说明。
- Android Kotlin 插件升级至 2.2.0，适配 `package_info_plus` 及其依赖的 Kotlin 2.2 元数据。
- 升版至 `0.2.13+24`。

## [0.2.12] - 2026-08-29

### Fixed

- CSV export → import round trip no longer corrupts `总价`: the `每公里花费` header now maps to its own derived column instead of overwriting the total-price column (`_detectColumns` first-match-wins).
- Partial-fill records no longer double-count mileage: period stats, ten-thousand-km stats, the 365-day heatmap, and overview distance now aggregate only completed measurement cycles.
- Append-mode CSV import now detects duplicates (same vehicle + minute + mileage) and reports "imported N, skipped M duplicates" instead of silently duplicating history.
- Record ledger custom date range actually filters records now; "全部时间" no longer hides future-dated records; statistics custom range no longer leaks the day before the start date.
- Save buttons in add-refuel and add-expense forms are debounced with a busy state, preventing duplicate records from double taps.
- Overwrite import now asks for explicit confirmation (showing the number of records that will be erased).
- Trip statistics group by full date instead of MM-dd, so same-month days from different years no longer merge.
- Left-swiped ledger card can be dismissed again by tapping the card, swiping right, scrolling, or opening another card's actions.
- Chart axes: adaptive nice intervals and sparse X labels across trend/temperature/price charts fix crowded or overlapping axis text.
- City search now covers all ~340 Chinese prefecture-level cities with pinyin/initials matching; the sheet no longer auto-requests GPS permission on open and compensates for keyboard insets.
- Network response bodies now read with timeouts across location, AMap, ApiZero price/forecast, and Moji weather services; platform geocoding is bounded so "locating" can no longer hang forever.
- Station search re-queries with the latest location after an in-flight request instead of dropping it; dashboard marquee no longer stacks two scroll loops; date-range dialog guards setState after dispose; license-plate field reacts to `initialPlate` changes.
- Deleting the last vehicle clears stale refuel/expense provider state; vehicle dialog text controllers are disposed on close.

### Changed

- Release builds no longer print GPS coordinates or database paths to system logs (`enableDebugLog` follows `kDebugMode`).
- Vehicle insert/update use `ConflictAlgorithm.abort` instead of `replace`, eliminating a latent cascade-delete trap; full-backup export reads all four tables inside a single transaction; database lazy init is future-memoized.
- Unifies hardcoded brand colors in city picker, license-plate field, and date dialog onto `AppBrandColors`; fixed collapsed `AppRadius` tokens; added accessibility labels to the plate input controls.
- Android `targetSdk` raised to 35 with release lint re-enabled; pubspec Dart lower bound aligned with reality and `flutter_lints` upgraded to 6; release workflow resolves build-tools dynamically; CI adds an iOS debug compile job.
- Bumped version to `0.2.12+23`.

## [0.2.11] - 2026-08-28

- Completed remaining audit optimizations and follow-up fixes.
- Normalized Dart formatting and fixed an analyzer warning.

## [0.2.10] - 2026-08-28

- Fixed empty-backup validation, city-to-province mapping, CSV round trips, and vehicle-switch failure handling.
- Added iOS external-link handling and improved weather chart data ranges.
- Normalized CI formatting and analyzer checks.

## [0.2.9] - 2026-08-28

- Restored permanent release signing and signature verification for split Android APKs.
- Removed retired report sharing, PDF export, and unused UI components.
- Rewrote the GitHub project documentation and removed obsolete local artifacts.

## [0.2.8] - 2026-08-28

- Fixed the last-known map location distance using a hardcoded Jingmen coordinate.
- Fixed record time-range boundaries, weather snapshot fallback, and forecast cold-start rate limiting.
- Fixed stale backup version metadata, swallowed calculation write failures, and missing cached-price labeling.
- Release automation builds unsigned split Android APKs and an unsigned iOS IPA.

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
