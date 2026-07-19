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
* Build for Android 32 & 64 bit shall ALWWAYS be done to verify a change.

The actual phones available for manual testing will be

* A Galaxy A33 5G (64 bit)
* Possibly a Galaxy A3 2017 (32 bit)

If either (or both) phones are connected while you are implementing a new feature / bugfix or any other changes, ALWAYS install the latest app w/o uninstalling the previous one to keep the database intact.

When installing the app using adb, NEVER uninstall the existing app to avoid data loss.

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
  * **Bad-fix rejection is accuracy-based, not speed-based.** Live fixes are dropped
    at the source when the GPS chip's own accuracy estimate is worse than 10 m
    (`lib/core/utils/gps_accuracy_filter.dart`, `isAccurateEnough`; a fix with no
    reported accuracy is kept). An earlier approach rejected fixes by *implied speed*
    (`GpsOutlierFilter`, live in `location_service.dart` + a flat 200 m per-leg cap in
    `RideMetricsAccumulator`) — field data on the Galaxy A3 2017 showed this didn't
    work: a slow sustained drift (e.g. multipath under tree cover) never looks "too
    fast" so it sailed through un-flagged and showed up as the track wandering off
    the real road for a stretch (the "clean spikes" tool couldn't fix it either, since
    none of those points individually look like a spike to that same algorithm) —
    while a *genuine* fast/sparse-fix descent after a real GPS gap of tens of seconds
    produced a large-but-plausible-speed leg that got its **entire distance silently
    discarded** by the flat 200 m cap, undercounting real rides. `GpsOutlierFilter`
    and the 200 m cap were reverted from the live path; `GpsOutlierFilter` itself is
    kept only as the manual "clean spikes" repair tool on the ride-detail screen and
    for crash-interrupted-track recovery (`track_repair.dart`) — deliberately a
    legacy/manual path, since GPS accuracy isn't persisted per point (no schema
    change), so old tracks can't be re-judged by accuracy after the fact.
  * **Distance is accumulated via streaming path simplification, not raw position
    summing and not speed integration (jitter, not spikes).** Even with every fix
    passing the accuracy filter above, summing the haversine leg between *every*
    consecutive 1 Hz fix reads several percent long vs. a reference track (Komoot)
    with no spikes/outliers involved — plain GPS jitter around the true position
    adds spurious zig-zag length (the "coastline paradox"), and it does so
    *continuously while riding*, not just when stationary: a first attempt at a fix
    gated out only small (near-stationary) legs, which turned out to do nothing in
    practice, since real per-sample movement at riding speed already clears any sane
    minimum-leg-length gate on its own. A **second** attempt integrated the GPS
    chip's own Doppler-measured speed (`GeoSample.speedMps`) over elapsed time
    instead of differencing positions — this avoided the jitter bias but traded it
    for a larger one in the other direction: field data from two real rides against
    known (Komoot-planned) route distances showed it **undercounting by 4-6%**, and
    every geometric alternative tried at the time (raw sum, fixed-time-window
    displacement, batch Douglas-Peucker) came out *higher*, not lower, ruling out
    "just needs more smoothing" — the reported speed itself isn't a reliable basis
    for distance. `RideMetricsAccumulator` (`lib/core/metrics/ride_metrics_accumulator.dart`)
    now instead runs an **incremental, buffered Douglas-Peucker-style streaming
    simplifier**: every point since the last committed anchor is buffered, and on
    each new point *all* buffered points are re-tested against the line from the
    anchor to the new point; if all stay within `_simplifyEpsilonMeters` (5 m,
    swept 3-10 m against the same two real rides — independently re-planned in
    Komoot to 27.20 km / 40.80 km, ~1000-1600 points each — landing within
    -0.74%/+0.64%) they're absorbed as
    noise on one straight bit of path with no added zig-zag length, otherwise the
    line up to the last still-valid point is committed as real distance and a new
    run starts there. Testing every buffered point against the anchor→newest line
    (not just the immediately-preceding point) matters: a naive two-point "sleeve"
    that only compares against the prior candidate lets one noisy point corrupt the
    reference line for the next comparison ("noise chasing noise") — verified to
    overcount by 60%+ against synthetic alternating jitter of just 1.5-2m: the
    buffered/re-tested version resolves cleanly up to ~3.5m of the same synthetic
    jitter. This is the streaming (single-pass, small bounded state) form of what a
    batch Douglas-Peucker would produce, so it can drive the live distance display
    incrementally — the batch algorithm needs the whole path to recursively find the
    worst-deviating point, which live recording doesn't have yet. Applies to both
    live recording and `track_repair.dart`'s replay (same accumulator) — existing
    rides recorded under either earlier approach can be corrected via Settings →
    Data → "Recalculate ride distances".
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
  + detail (stats, route-sketch, elevation chart) with GPX export. The Rides list also shows
  rolling **week/month/year summary cards** above the ride list (rides count, distance, time;
  `lib/core/utils/ride_summary.dart`, pure + unit-tested). **Backup & restore** (Settings →
  Backup & restore, `lib/core/services/backup_service.dart` +
  `lib/features/backup/`): exports the whole ride DB to a portable `.sqlite` snapshot
  (`VACUUM INTO`, so it's a live consistent copy without closing the DB) into the app's
  external files folder (adb/USB/Files-app reachable, no root needed); import **merges** by
  matching `startedAt`, so re-importing or importing on a phone that already has some of the
  same rides is safe. Moving a backup to another phone goes through the **OS share sheet**,
  not an in-app cloud integration: a "Share" action per backup hands the file to
  `ACTION_SEND` (`cycle/share` native channel + a `FileProvider`, `android/app/src/main/res/xml/file_paths.xml`)
  so the user picks whatever app (OneDrive, Drive, email, Bluetooth, …) to send it through —
  that app handles its own login, so Cycle itself has zero OAuth/account plumbing. Receiving
  is symmetric: opening/sharing a `.sqlite` into Cycle (`cycle/incoming_backup` channel +
  manifest intent-filters, mirroring the GPX open/share handling below) auto-imports it on
  resume. (An earlier direct-OneDrive OAuth integration — Azure app registration, PKCE,
  Microsoft Graph API — was built, tested, then deliberately dropped in favour of this: the
  Azure registration/tenant setup was disproportionate ceremony for what is fundamentally a
  personal file transfer between two owned phones, and the share-sheet works with *any*
  storage app, not just OneDrive.) DB/GPX/persistence
  unit-tested; list/detail widget-tested; record→stop→Rides verified on the emulator.
  **Background recording (real foreground service).** `flutter_foreground_task` was
  originally removed here — its engine-startup registration caused a main-thread ANR on
  Android 14 — and recording ran on the wakelock alone (screen-on only) for a while. It's
  since been **re-added and wired in** (`lib/core/services/fg_task_recording_service.dart`,
  `FgTaskRecordingService`, the default `recordingForegroundServiceProvider`): a real
  Android foreground service (persistent notification, `location` service type) starts on
  `RecordingController.start()`/`resume()` and stops on `stop()`, so the OS won't reclaim
  Cycle for RAM while backgrounded mid-ride. The ANR is avoided by starting the service
  **without a `callback`/`TaskHandler`** — that's what makes the plugin spin up a second
  Flutter engine/callback dispatcher, which is what caused the original hang; without one,
  we only keep the *main* isolate's process alive, no background Dart execution needed.
  Verified on a real device (Galaxy A33): start/stop round-trip cleanly via the volume-key
  path, the service starts/stops with no ANR, and the process survives being backgrounded.
  `NoopRecordingForegroundService` remains for tests/platforms without it.
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
* **Post-M7 polish.** Home screen also shows **HR/Cadence/Power** boxes (live BLE
  `sensorSnapshotProvider`, always visible, "—" with no data). **Colour schemes**
  (`AppColorScheme` Dark/Light/B&W, Settings → Appearance): each restyles the app
  `ThemeData` (`buildAppTheme`), the offline map render theme (`dark.xml`/`light.xml`/
  `bw.xml`, swapped via `activeMapModelProvider` reloading), and the overlay accents
  (`MapAccents`). The app theme + accents switch live; the **map render theme** applies on the
  next map (re)load (cold start, or as tiles redraw on pan) — already-rendered tiles stay in
  mapsforge's cache, and force-purging them (`MemoryTileCache.purgeAllCaches`) ANRs the main
  thread with a synchronous re-raster, so don't. **Direction arrows** on the recorded track +
  followed route: rotated
  `IconMarker(Icons.navigation)` glyphs (no image assets) oriented by `geo.bearingDegrees`,
  spaced adaptively (~60 max). Marker rotation only works via `IconMarker` (icon-font glyph) —
  the vendored `CaptionMarker`'s `rotation` arg is a no-op and the caption renderer ignores
  theta, so text can't be rotated.
  * The recorded track only accumulates **while recording** (cleared on start/stop). BLE
    sensors **auto-reconnect** on launch (`paired_sensors_store` + `SensorConnectionController`,
    read at startup from the home screen). CSC **cadence** holds through brief gaps (a 1 Hz
    notification with no new crank rev returns null → consumer keeps the last value; only drops
    to 0 after a few empty intervals) to stop the 0-flicker. The on-screen **Start/Stop button
    is hidden by default** (volume keys; `showStartStopButton` setting, and always shown when
    volume keys are off). Recording keeps the screen on (wakelock enabled in `RecordingController.start`).
  * **Ride detail** (`track_detail_screen`) shows the ride on the **real offline map**
    (`rideMapProvider`, an autoDispose mapsforge model fitted to the track) with the track
    **coloured by speed** (red ≤10 → violet ≥60 km/h, `speed_color.dart`, segments merged by
    colour bucket) + legend; the map pinch-zooms natively and the elevation chart is wrapped in
    an `InteractiveViewer` (its `LineChartData.lineTouchData` must stay **disabled** — fl_chart's
    own touch handling otherwise wins the gesture arena and the pinch/pan never reaches the
    viewer). The map and elevation sections each sit in a `Listener`-based "isolated region"
    (`_BodyState._isolate`) that disables the outer page's scroll physics for as long as any
    finger is down on them, so a one-finger drag or pinch on the map/chart never fights the
    page scroll for the gesture (scoped per-widget, not the whole page, so the rest of the ride
    detail still scrolls normally). Stats include distance/time/avg/max + ascent + avg HR/cadence/power
    + **battery used** (`tracks.batteryStart/EndPercent`, schema v2; read via the native
    `cycle/battery` channel → `BatteryService` at recording start/stop; Android exposes whole-%
    only). The map **zoom is remembered** (`AppSettings.mapZoom`, saved on app pause, restored
    as the initial/first-fix zoom). The recorded track + followed route render as a **dashed
    line with chevron arrowheads** (`Icons.keyboard_arrow_up` `IconMarker`s). Map **rotation is
    disabled** (vendored patch 2, `generic_gesture_detector` drops `RotationHandler`).
* **OruxMaps import** (Settings → Data → "Import from OruxMaps",
  `oruxmaps_import_screen.dart`). `lib/features/tracks/application/oruxmaps_import_service.dart`
  reads OruxMaps' `oruxmapstracks.db` (SQLite, `tracks`/`segments`/`trackpoints`, schema
  unverified against a real device export — built against the one confirmed by
  github.com/wolfgangasdf/oruxtool; see the file's doc comment) and merges its rides into
  Cycle's own database with the same "safe to run twice" start-time dedup as
  `BackupService.importBackup`. Distance/duration/avg/max are **recomputed** with
  `computeStatsFromPoints` rather than trusting OruxMaps' own segment stats. Entirely on-device,
  no PC/adb, via two paths:
  * **Bulk (recommended for a full ride history).** OruxMaps' database normally lives in its
    own private storage (`Android/data/com.orux.oruxmaps/…`), which Android 11+ blocks every
    other app — including file managers — from browsing (confirmed against a real device: the
    folder is simply inaccessible from a file-manager app). `lib/core/services/file_access_service.dart`
    checks/requests the **"All files access"** special permission (`MANAGE_EXTERNAL_STORAGE`;
    manifest + native `cycle/file_access` channel in `MainActivity.kt`, opens
    `Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`) — the same permission a file-manager
    app holds, so once granted it lifts the block for Cycle too. This is a personal sideload, not
    Play-distributed, so Play's policy restricting who may hold this permission doesn't apply.
    Once granted, `OruxMapsImportService.findDatabaseOnDevice` locates `oruxmapstracks.db` itself
    (checks OruxMaps' known storage paths across every volume — same
    `getExternalStorageDirectories`-derived volume-root technique `MapStorageService` uses for
    maps — then falls back to a depth-bounded recursive search) and `importFromDeviceStorage`
    imports it directly; no manual file hunting needed. **OruxMaps ships as (at least) two
    separate Android package ids** — `com.orux.oruxmaps` (free) and `com.orux.oruxmapsDonate`
    (paid "Donate" version, same app) — each with its own storage folder; verified on a real
    device with the Donate variant installed (`_knownPackageIds` checks both).
  * **Per-track GPX (no permission needed).** OruxMaps' own Track Manager can Export/Share a
    single ride as a `.gpx`, which — since OruxMaps owns that file — it can share directly
    regardless of the storage restriction above. `lib/features/tracks/application/gpx_ride_import_service.dart`
    (`GpxRideImportService.importRide`) imports a GPX's own timestamped track points as a past
    ride (same recompute + dedup as the bulk import). Because the existing `cycle/incoming_gpx`
    channel already treats every incoming GPX as a route to follow, `map_screen.dart`'s
    `_checkIncomingGpx` now checks `FollowRoute.isTimed` (a GPX with real per-point timestamps
    could be either): an untimed GPX still follows directly as before, but a timed one prompts
    "Follow route" vs. "Import as ride" before doing either.
* **Recalculate ride distances** (Settings → Data): a maintenance action —
  `recalculateAllTrackStats`/`recalculateTrackStats` (`track_repair.dart`) reruns
  `computeStatsFromPoints` over every finalised ride's already-recorded points and saves
  the result, without touching the points. For rides recorded before a change to
  `RideMetricsAccumulator`'s maths (e.g. the speed-integration distance fix above) so old
  rides read consistently with new ones — a one-tap, on-device fix, no adb/DB surgery needed.
* **Bike profiles** — record against different bicycles and view stats per bike or in
  total, without a pop-up on every ride. `BikeProfile` (`lib/core/models/bike_profile.dart`,
  `id`/`name`/`colorArgb`, colours from `kBikeProfileColors`) + `BikeProfilesState`
  (profiles list + `activeId`) persisted outside the SQL DB via
  `lib/core/services/bike_profiles/bike_profiles_store.dart` (`shared_preferences` JSON,
  same pattern as `SettingsStore`), managed by `BikeProfilesController`
  (`lib/features/settings/application/bike_profile_providers.dart`; a fresh install
  auto-seeds one default profile, "Bike 1", so there's always an active one — no setup
  dialog). `Tracks` gained a nullable `bikeProfileId` `TextColumn` (schema v3, plain
  `addColumn` migration, same shape as the v1→v2 one) — **not a SQL foreign key**, since
  profiles live in prefs, not the DB; a deleted profile just leaves old rides pointing at
  an id that matches nothing (same as a pre-feature ride with a null id).
  * **No pop-up, but still correctable:** `RecordingController.start()` stamps the new
    track with whichever profile is currently active — no prompt. Volume-up while **not**
    recording starts the ride as before; volume-up again *while already recording*
    (`HardwareButtonController`) calls `RecordingController.cycleBikeProfile()`, which
    advances to the next profile and **live-corrects the DB row** for the ride in progress
    (`AppDatabase.setTrackBikeProfile`) — so a wrong bike picked at the start can be fixed
    from the saddle without stopping. `setBikeProfile`/`cycleBikeProfile` are the single
    path both the hardware-button cycling and the on-screen picker go through.
  * **Display + manual pick:** a coloured chip (`_BikeProfileChip` in `map_screen.dart`)
    shows the active profile's colour + name. It sits in the **AppBar's `leading` slot**
    (a fixed-width reservation), not the title — an earlier attempt put it in the title
    `Row` alongside "Cycle" and it overflowed once the 5 action icons + title + chip all
    competed for the same narrow app-bar width (only caught by an emulator screenshot;
    plain `flutter analyze`/tests don't render real widths). Tapping the chip opens a
    bottom sheet to explicitly pick a profile (works without hardware buttons too, e.g.
    iOS) or jump to **Settings → Bikes → Bike profiles** (`/bike-profiles`,
    `BikeProfilesScreen`) to add/rename/recolour/delete profiles and set the active one.
  * **Rides list filtering:** `TracksScreen` gets an "All" + per-bike `ChoiceChip` row
    (`selectedBikeProfileFilterProvider`, a plain in-memory `Notifier`, not persisted —
    only shown once you have 2+ profiles, since one bike has nothing to filter), which
    filters both the ride rows and the existing week/month/year summary cards
    (`computeRideSummaries` already takes a plain `List<Track>`, so filtering before
    calling it gives per-bike or total summaries for free) — plus a small colour dot per
    row (also only shown with 2+ profiles, since a single bike's colour carries no
    distinguishing information).
  * **Correcting past rides:** the picker bottom sheet is shared
    (`lib/features/settings/presentation/widgets/bike_profile_picker.dart`,
    `showBikeProfilePicker`) between the home-screen chip and a "Bike" row on
    `track_detail_screen.dart` (shows the ride's current bike, or "Unassigned"; tap
    to change — writes straight to `AppDatabase.setTrackBikeProfile` and invalidates
    `trackProvider`/`tracksProvider`, since this is a past/finalised ride, not the
    live one `RecordingController` owns). For fixing a whole history at once (e.g.
    after renaming the auto-seeded "Bike 1" to your actual bike), each profile's
    menu on `BikeProfilesScreen` has **"Assign all rides to this bike"** —
    `AppDatabase.assignAllTracksToBikeProfile` (`update(tracks)` with no `where`)
    unconditionally overwrites every ride's bike, behind a confirm dialog that
    states the ride count.
  * **Classify rides** (`RideClassifierScreen`, `/classify-rides`, reached via the
    filter icon on `TracksScreen` — the Rides/trip-history list, not Settings) —
    finds old rides matching a combination
    of criteria and bulk-assigns just the matches to a bike, for classifying a
    ride history recorded before profiles existed. `RideClassifierFilter` +
    `filterTracksForClassification` (`lib/features/tracks/application/
    ride_classifier.dart`) split the work in two: cheap criteria that live
    directly on `Tracks` (only-unassigned, distance/avg-speed/max-speed/date
    range) run as SQL via `AppDatabase.tracksMatching`; criteria that only exist
    on `TrackPoints` (has cadence/heart-rate/power data) then narrow that result
    by loading points **only for the already-filtered candidates** — not the whole
    ride history — checking `points.any((p) => p.<field> != null)`. Matches are
    bulk-assigned via `AppDatabase.assignTracksToBikeProfile(ids, bikeProfileId)`
    (distinct from `assignAllTracksToBikeProfile` — this one takes a specific id
    list rather than unconditionally touching every ride).
    **"Had a speed sensor" is deliberately not offered** as a criterion: unlike
    cadence/HR/power, the recorded `speedMps` never distinguished GPS from a BLE
    sensor — only the resulting number was stored, not its source — so it can't be
    reconstructed for rides recorded before this shipped. `TrackPoints` gained a
    nullable `speedFromSensor` `BoolColumn` (schema v4, plain `addColumn`
    migration) fed from `RideController`'s already-computed `_fusion.isUsingBle`
    through `RecordingController.recordPoint`, so **new** rides going forward can
    be classified by it; old points stay `null` (unknown, not "false").

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
  boot the emulator and screenshot the app. Two packages broke launch despite green tests:
  `flutter_foreground_task` (main-thread ANR — since fixed and **re-added**, see the M4
  background-recording note above: the ANR was specifically from starting it *with* a
  callback/TaskHandler; starting it without one avoids the second-engine registration that
  caused the hang) and `dashboard` (first-frame hang, splash forever) — the latter was for
  the customisable dashboard, now **deferred**; build any editor from first-party widgets.
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

## Versioning

[Semantic versioning](https://semver.org) (currently **0.x** = pre-1.0, active dev). The single
source of truth is `version:` in `pubspec.yaml` (`X.Y.Z+build`, where `+build` = Android
`versionCode` — bump it every release). On each release: update `pubspec.yaml`, move the
`CHANGELOG.md` `[Unreleased]` items into a new dated `[X.Y.Z]` section, and run
`tool/fl python3 tool/gen_version.py` to regenerate `lib/core/app_version.dart` (shown in
Settings → About; never hand-edit it). Keep `CHANGELOG.md` in [Keep a Changelog] form.

## Updating this file

This file shall be kept up-to-date automatically. Update the tech stack and milestone
progress sections as features land.
