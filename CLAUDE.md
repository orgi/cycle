# Instructions to CLAUDE

## Application Overview

This repository contains an application for mobile phones (Android + IOS).
The app ca be used by cyclists as a replacement for an actual bike computer.
Target use case:

* Running on a mobile phone
* Mobile phone mounted on the bike
* Screen is always on (using black background & dark mode where possible for max battery saving with OLED)
* Screen will/can display different metrics like
  * Current speed
  * Average speed
  * Trip distance
  * Sensor-based
    * Heart Rate (BLE)
    * Cadence (BLE)
    * Speed (BLE) - combined with GPS speed for max accurracy
  * Map with current location (openstreetmaps offline maps, vector-based maps)
* Additional features
  * Follow track (loaded GPX)
  * Upload track to Komoot and other online services
  * Upload track to self-hosted server
* Usage features
  * Possible to start/stop track using physical buttons (where possible)
  * Local database for storing all tracks

## Testing

Every feature, bugfix other other changes to the source code ALWAYS needs to be tested.

* For the general code testing there ALWAYS have to be unit tests.
* For the system testing there needs to be at last a GUI test
* Tests need to be executed for acceptance of any automated edit

## Tech stack & architecture

* **Framework:** Flutter (Dart), single codebase for Android + iOS.
* **State management:** Riverpod 3 (`flutter_riverpod`) — use the modern `Notifier`
  API, not the deprecated `StateNotifier`.
* **Routing:** `go_router`.
* **Maps:** Mapsforge via `mapsforge_flutter` (pure-Dart, works Android+iOS), rendering
  offline **vector** `.map` files. Maps are **not bundled in the build**; users download
  ready-made per-region packs (Alps/Europe/by country) on demand from **OpenAndroMaps**
  (free, no account) — OruxMaps-style. A small `monaco.map` ships as a demo so the map
  works out of the box. Render theme: bundled minimal dark theme (`assets/render_themes/dark.xml`),
  no external symbol assets. [M2]
  * **Vendored + patched** at `third_party/mapsforge_flutter` (via `dependency_overrides`,
    see `third_party/mapsforge_flutter/PATCH.md`): upstream 4.0.0's `TileJobQueue` emitted
    tilesets stamped with the render's *old* center and dropped position updates while a
    render was in flight, so a GPS-follow map left the tiles frozen and jumped ~one tile
    (~hundreds of m) at a time while the marker/track followed correctly. The patch
    re-stamps every emitted tileset to `mapModel.lastPosition` (cheap re-projection of
    already-loaded tiles) so the map pans smoothly. Drop the override if fixed upstream.
* **GPS:** `geolocator` — note we **poll `getCurrentPosition` at 1 Hz** (not
  `getPositionStream`, which is broken on Android 14) with `forceLocationManager: true`
  (raw GPS). See `lib/core/services/location_service.dart`.
* **BLE sensors:** `flutter_blue_plus` using the standard Bluetooth SIG GATT profiles
  (HR `0x180D`, CSC `0x1816`, Power `0x1818`); modern Garmin dual-band sensors work over BLE
  with no special code. Parsers + CSC speed/cadence + GPS/BLE speed fusion live in
  `lib/core/sensors/` (pure Dart, heavily unit-tested); the `flutter_blue_plus` glue is in
  `ble_sensor_service.dart` behind a `SensorService` interface (fake for tests/emulator).
  `connect()` uses `License.nonprofit` (a commercial release needs the paid FBP license).
* **Local DB:** `drift` (SQLite) for tracks/trackpoints. [M4]
* **GPX:** `gpx` package — used for both ride export [M4] and follow-route import [M5].
* **Follow route [M5]:** `lib/features/routing/` — parse a GPX into a `FollowRoute`
  (cumulative distances), `RouteNavigator` does nearest-segment projection for
  cross-track/off-route + remaining distance (pure Dart, unit-tested). The route shows as a
  dashed-blue overlay on the map with a nav banner (name · km left · OFF-ROUTE). Import is
  **folder-based, not a system picker**: users drop `.gpx` files into the app's
  `routes/` folder (Android external files dir / iOS documents) and pick from an in-app list;
  a bundled `assets/routes/monaco_loop.gpx` is the "Follow demo route". We deliberately do
  **not** use `file_picker` — see Known gotchas.
* **Keep-awake:** `wakelock_plus`.

Code is organised under `lib/` as `core/` (services, models, metrics, utils) and
`features/<feature>/` split into `presentation/` · `application/` (Riverpod) · `domain/`.
Services (location, screen-wake, …) sit behind interfaces so tests inject fakes.

## Development environment

This machine has no local Flutter/Android SDK; the toolchain runs in a container.

* **Devcontainer:** `.devcontainer/` (image `cirruslabs/flutter` + Android emulator +
  API-34 system image + a `cycle_test` AVD, with `/dev/kvm` passthrough).
* **Run any command via the wrapper** `tool/fl`, e.g.:
  * `tool/fl flutter pub get`
  * `tool/fl flutter analyze`
  * `tool/fl flutter test`            (unit + widget tests — host VM, no device)
  * `tool/fl flutter test integration_test`   (GUI tests — needs the emulator image)
* Caches live in gitignored `/.cache/` so they persist between runs.
* **iOS cannot be built/tested on this Linux host** (needs macOS/Xcode). Keep all Dart
  code and `ios/` config cross-platform; build/test iOS later on a Mac or macOS CI.

## Milestone progress

* **M1 — Skeleton & always-on dashboard:** done. Live speed/avg/max/distance/time from GPS,
  start/stop + wakelock. **UI later consolidated (post-M4):** the home screen is now a single
  combined view — a full-screen map with the recorded track + location dot and the 5 ride
  stats as semi-transparent overlay boxes (SPEED/TIME top, DIST/AVG/MAX bottom). The separate
  metric-only dashboard was removed. An editable/drag-resize dashboard was attempted but the
  only suitable package hangs on-device, so it's **deferred** (build from first-party widgets
  if revisited). `lib/features/map/presentation/map_screen.dart` is the home.
* **M2 — Offline map + region download manager:** done. Mapsforge map screen (dark theme,
  live location marker) + OpenAndroMaps "Manage maps" downloader (catalogue, download with
  progress, delete). Bundled `monaco.map` demo. Host + emulator GUI tests green.
* **M3 — BLE sensors:** done. Scan/pair screen + live HR/cadence/power on the dashboard;
  GPS+BLE speed fusion (BLE wheel speed preferred when fresh). GATT parsers, CSC calculator
  and fusion unit-tested; emulator GUI test uses a fake BLE backend (emulators have no BLE,
  so real-sensor/Garmin verification needs a physical device).
* **M4 — Recording & track DB:** done. `drift`/SQLite (`tracks` + `trackPoints`); recording
  persists a point per GPS sample with sensor values and finalises stats on stop; Rides list
  + detail (stats, route-sketch, elevation chart) with GPX export. DB/GPX/persistence
  unit-tested; list/detail widget-tested; record→stop→Rides verified on the emulator.
  NOTE: `flutter_foreground_task` was removed — its engine-startup registration caused a
  main-thread ANR on Android 14. A real foreground service (background recording with screen
  off) is **deferred to M7**; recording currently runs while the screen is on (wakelock).
* **M5 — Follow track (GPX):** done. Import a GPX (folder-based, see tech stack) or load the
  bundled demo route; dashed-blue route overlay on the map + nav banner (name · remaining km ·
  OFF-ROUTE warning). `FollowRoute`/`parseGpxRoute`/`RouteNavigator` (off-route + remaining)
  unit-tested; follow-route GUI test loads the demo route on the emulator; build + launch +
  live follow verified via `tool/demo` (`screenshots/m5_follow_route.png`). Also fixed a
  mapsforge GPS-follow drift here — see the vendored patch in tech stack/Known gotchas.
* **M6** upload (self-hosted/Strava/Komoot) · **M7** physical buttons & polish — pending.
  Full plan: `~/.claude/plans/please-plan-an-implementation-zany-shannon.md`.

## Known gotchas

* **Tests don't catch startup hangs.** Widget/integration tests bypass real app launch, so a
  green suite is NOT proof the app runs. After adding a plugin/package or touching startup,
  boot the emulator and screenshot the app. Two packages broke launch despite green tests and
  were removed: `flutter_foreground_task` (main-thread ANR) and `dashboard` (first-frame hang,
  splash forever) — the latter was for the customisable dashboard, now **deferred**; build any
  editor from first-party widgets.
* `MetricTile` reserves the widest value (`referenceValue`) so the speed/avg/etc. value does
  not resize when it gains a digit.
* **`file_picker` does not build here.** The project uses **AGP 9 + standalone Kotlin**
  (`android.builtInKotlin=false`). `file_picker` 11's Android `build.gradle` skips applying the
  Kotlin plugin when AGP ≥ 9 (assuming built-in Kotlin), so its `FilePickerPlugin.kt` never
  compiles → "cannot find symbol FilePickerPlugin". No project flag fixes both it and the
  plugins that unconditionally apply KGP (`wakelock_plus`, `package_info_plus`). M5 import is
  therefore folder-based via `path_provider`. Revisit a system picker only with a package that
  builds on AGP 9 (or vendor+patch its gradle).
* **GPS-follow map drift (fixed).** mapsforge_flutter 4.0.0 left the tiles frozen and jumping
  ~one tile at a time while the marker/track followed correctly. Vendored + patched at
  `third_party/mapsforge_flutter` (`dependency_overrides`); details in its `PATCH.md`. The
  patch only lives in `third_party/` — a `pub get` won't carry it via the cache copy.
* **Static screenshots can't verify motion.** The drift bug looked fine in stills but was
  obvious across video frames. For map-follow/animation, extract a frame *sequence*
  (`ffmpeg -ss`) and compare — byte-identical consecutive frames = frozen screen.

## Updating this file

This file shall be kept up-to-date automatically. Update the tech stack and milestone
progress sections as features land.
