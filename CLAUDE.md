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

The actual phones available for manual testing will be

* A Galaxy A33 5G
* Possibly a Galaxy A3 2017

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
* **Release signing (stable key):** release builds are signed with a fixed key
  (`android/app/cycle-release.jks` + `android/key.properties`, **both gitignored**) wired in
  `android/app/build.gradle.kts`. This lets a release APK be updated in place (`adb install -r`)
  **without uninstalling**, so downloaded maps + other app data survive updates. Back up the
  keystore — losing it forces an uninstall to update again. The build falls back to the debug
  key when the keystore is absent (so a fresh clone still builds).

## Milestone progress

* **M1 — Skeleton & always-on dashboard:** done. Live speed/avg/max/distance/time from GPS,
  start/stop + wakelock. **UI later consolidated (post-M4):** the home screen is now a single
  combined view — a full-screen map with the recorded track + location dot and the 5 ride
  stats as semi-transparent overlay boxes (SPEED/TIME top, DIST/AVG/MAX bottom). The separate
  metric-only dashboard was removed. An editable/drag-resize dashboard was attempted but the
  only suitable package hangs on-device, so it's **deferred** (build from first-party widgets
  if revisited). `lib/features/map/presentation/map_screen.dart` is the home.
  * **Map-follow camera:** the first GPS fix sets a riding zoom (16); later fixes use
    `MapModel.moveTo` (re-centre, **keep the user's zoom/rotation**) — `setPosition` with a
    fixed zoom on every 1 Hz fix snapped a manual zoom back. Before any GPS fix the camera sits
    on the active map's bounding-box centre (see the camera gotcha), re-centring when a
    different map loads.
* **M2 — Offline map + region download manager:** done. Mapsforge map screen (dark theme,
  live location marker) + OpenAndroMaps "Manage maps" downloader (catalogue, download with
  progress, delete). Bundled `monaco.map` demo. Host + emulator GUI tests green.
  * **Catalogue** (`lib/features/map/domain/map_catalog.dart`) is the **full** OpenAndroMaps
    Europe + Germany listing (~80 regions: Alpine/multi-country regions, countries, and German
    Bundesländer incl. Bayern), grouped greater-region-first then alphabetical. It is
    **generated** from the live mirror by `tool/gen_map_catalog.py` (`tool/fl python3
    tool/gen_map_catalog.py > …/map_catalog.dart`) — don't hand-edit names/URLs/sizes; re-run to
    refresh. Add other continents by extending that script.
  * **Which map is displayed** (only one renders at a time — no multi-datastore in this
    mapsforge port): `pickMapPath` (pure, unit-tested) chooses the user's manually picked map
    (`AppSettings.selectedMapFileName`) if still installed, else the **smallest installed map
    whose bbox contains the current GPS position** (most local detail when regions overlap, e.g.
    Bayern inside Alps), else the first installed map. `chosenMapPathProvider` feeds
    `activeMapModelProvider` a *stable* path so the map reloads only when the choice actually
    changes (not every 1 Hz fix); `installedMapBoundsProvider` reads each map's bbox once via
    `MapRenderService.boundsOf`, which reads the **16-byte bbox straight from the mapsforge
    header** (offset 44, four big-endian int32 microdegrees) — it must NOT
    `Mapfile.createFromFile` each map just for metadata: opening/indexing a multi-GB region in
    an isolate for every installed map (on top of the display map) froze the app on a real
    device with the Alps + Bayern maps. A `map_outlined` app-bar picker (`_MapPickerMenu`, shown
    only with ≥2 maps installed) offers "Automatic (by location)" + each installed map.
  * Downloads are **streamed to a `.zip.part` file on disk** with back-pressure
    (`IOSink.addStream`, not a `sink.add` loop) — nothing is held in memory (region zips reach
    ~2.9 GB; ~3.7 GB extracted). **Resumable** via HTTP `Range`: an interrupted download (screen
    locked → OS suspends the app) resumes on retry instead of restarting. The `.map` is
    **stream-inflated** out of the zip with dart:io's native zlib (the `archive` package's
    `writeContent` buffers the whole decompressed output in RAM → OOM on big maps; we use
    `archive` only to read the central directory, then `ZLibDecoder(raw:true).bind` + `addStream`
    the entry's byte range to disk). `android:largeHeap` set for headroom. Screen kept awake
    during a download.
  * **Storage:** new maps go to a removable **SD card** when present (app-specific external
    dir, no permission, removed on uninstall), else internal; installed maps are listed across
    all volumes. The Manage-maps screen shows where maps are stored.
  * **Errors** are classified to a short reason (no connection / not enough space / server
    error (HTTP nnn) / …) shown in the row instead of a generic "Download failed".
  * NOTE: `INTERNET` permission lives in the MAIN manifest (was only in debug/profile, so
    release builds had no network) — see Known gotchas.
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
* **M5 — Follow track (GPX):** done. Import a GPX (folder-based, see tech stack), load the
  bundled demo route, or **open/share a `.gpx` into the app** (Android intent-filters +
  native `MainActivity` `cycle/incoming_gpx` MethodChannel → `IncomingGpxService`; iOS
  document types registered, delivery handler is a macOS-time TODO). Slim dashed-blue route
  overlay + nav banner (name · remaining km · OFF-ROUTE · ghost ±delta).
  `FollowRoute`/`parseGpxRoute`/`RouteNavigator`/`GhostRider` all unit-tested; follow-route
  GUI test on the emulator; build + follow + ghost + open-intent verified via `tool/demo`.
  **Ghost rider:** `GhostRider` replays the GPX's own timestamps when present, else paces at a
  default target speed (25 km/h); translucent marker + ahead/behind delta, active only while
  recording. **Live metrics now only accumulate while recording** (TIME/dist/avg/max stay 0
  until Start; current speed still shows). Also fixed a mapsforge GPS-follow drift here — see
  the vendored patch in tech stack/Known gotchas.
* **M6 — Upload (Strava + Komoot):** done (self-hosted skipped per user). `lib/core/services/upload/`:
  `StravaClient` (official OAuth2 + multipart `/uploads` + poll), `KomootClient` (UNOFFICIAL
  session-cookie login + `/v007/tours/` — Komoot's official API is partner-only; fragile, may
  break), `UploadStore` (creds/token in `shared_preferences`), `RideUploader` (token/refresh/
  interactive-OAuth orchestration). OAuth is plugin-free: native `MainActivity` `cycle/oauth`
  channel (`openUrl` + capture `cycle://strava-callback` redirect) + manifest intent-filter;
  `NativeOAuthAuthenticator` polls it. UI: Rides → "Upload accounts" settings (`/upload-accounts`)
  + cloud-upload action on ride detail. Verified: 23 unit/widget tests + a real-socket
  mock-server Strava test; build/launch on the emulator. **Real OAuth + a real upload need the
  user's own Strava API app (client_id/secret) + account, done once on a device — see the M6
  device checklist.** Komoot is unverifiable without a live account + attempt.
* **M7 — Physical buttons & polish:** done. **Volume-key start/stop:** native `MainActivity`
  intercepts VOLUME_UP (start) / VOLUME_DOWN (stop) in **`dispatchKeyEvent`** (NOT `onKeyDown`
  — a FlutterActivity routes keys through the FlutterView first, which swallows the volume keys
  before `onKeyDown`; `dispatchKeyEvent` is the activity's first look, before the view hierarchy
  / default volume handling) and routes them over the `cycle/hardware_buttons` MethodChannel
  (plugin-free). Consumes both down+up (ignores key-repeat) so the volume neither changes nor
  shows its UI. `HardwareButtonService`/`HardwareButtonController` toggle recording, gated by a
  setting. **Foreground+screen-on only** (capturing keys with the screen off needs a media
  session / accessibility service — out of scope); iOS can't intercept volume keys (no-op).
  **Settings screen** (`/settings`, gear in the map app bar):
  units (metric/imperial — wired through `formatSpeed`/`formatDistance` into the live stats),
  wheel circumference (pushed to the CSC calculator via `SensorService.setWheelCircumference`),
  and the volume-key toggle. `AppSettings`/`SettingsStore` on `shared_preferences`. Verified:
  unit/widget tests incl. the volume-key→recording wiring; on the emulator the injected
  `adb input keyevent KEYCODE_VOLUME_UP/DOWN` starts/stops a recording **and the media volume
  stays unchanged** (proving interception), with the native `volume key -> up/down` log firing.
  Full plan: `~/.claude/plans/please-plan-an-implementation-zany-shannon.md`.

## Known gotchas

* **`MapModel.dispose()` disposes its registered marker datastores.** Swapping the active map
  (manual/auto map selection, or a download replacing it) disposes the old `MapModel`, which
  disposes every `MarkerDatastore` registered to it via `MarkerDatastoreOverlay`. The map
  screen shares ONE datastore (track/location/route/ghost markers) across map swaps, so a naive
  `DefaultMarkerDatastore` gets torn down on the first swap → next render throws "used after
  disposed". The screen uses `_ScreenMarkerDatastore` (swallows the model's swap-time dispose;
  the screen disposes it for real in its own `dispose()`).
* **Map camera must start over the loaded map.** The home map's initial camera centres on the
  active map's **bounding-box centre** (`MapRenderService` returns a `LoadedMap{model, center}`),
  not a hard-coded location. A downloaded region map does NOT cover the Monaco demo coords, so
  centring there showed only blank/unloaded tiles (black on a cold start with no GPS). Re-centre
  whenever a *different* map loads (e.g. after a download swaps the active map), until a GPS fix
  takes over. A blank/black downloaded map is almost always a camera-outside-coverage bug, not a
  corrupt `.map` (the extractor is verified byte-identical to `unzip`).
* **Debug-only permissions hide release bugs.** Flutter auto-adds `INTERNET` to the
  *debug/profile* manifests for tooling, so networking "works" on the emulator/debug build but
  fails instantly on a release build if `INTERNET` isn't in `src/main/AndroidManifest.xml`. It
  is now declared there. Verify networking on a **release** APK (`flutter build apk --release`,
  `aapt dump permissions`), not just the debug build.
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
* **go_router eats file:// open intents.** With Flutter deep linking enabled (the default),
  opening a `.gpx` made go_router try to route the `file://…gpx` intent URI → "Page Not Found".
  We set `flutter_deeplinking_enabled=false` in the manifest and handle opened/shared GPX via
  the `cycle/incoming_gpx` MethodChannel instead. Re-enable deep linking only if you add real
  URL routes (and then exclude the file/content intents).

## Updating this file

This file shall be kept up-to-date automatically. Update the tech stack and milestone
progress sections as features land.
