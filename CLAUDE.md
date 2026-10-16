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
  * Upload track to Strava and other online services (official APIs only — see M6)
  * Upload track to self-hosted server
* Usage features
  * Possible to start/stop track using physical buttons (where possible)
  * Local database for storing all tracks

## Versioning

For all builds that will be installed on the device, make sure to strictly follow semantic versioning. Also, every build MUST ALWAYS increase the build number.
Also, a changelog has to be maintained.

**The build number alone is NEVER enough when the change adds a feature or fixes a bug.** Every
installed build is a release: bump MINOR for new features (reset PATCH), PATCH for fixes only —
see the detailed rules in the second "Versioning" section at the end of this file.

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
  works out of the box. Render themes: our own minimal Dark/Light/B&W (`assets/render_themes/
  {dark,light,bw}.xml`, no symbol assets) are the default; the optional **Detailed** and
  **Detailed — Dark** styles are mapsforge_flutter's own LGPL-3.0 themes (`detailed.xml` =
  upstream `mapsforge_default.xml`, `detailed_dark.xml` = upstream `darkrender.xml`, both
  unmodified apart from a provenance header). Their symbols/patterns are `src="jar:…"`, which
  mapsforge's default loader resolves to `packages/mapsforge_flutter_rendertheme/assets/`; that
  package doesn't declare them, so `pubspec.yaml` lists exactly the files used and
  `test/unit/detailed_theme_assets_test.dart` loads each one from the bundle (a missing
  symbol doesn't fail the build, it just doesn't render). **Don't bundle OpenAndroMaps'
  Elevate/Elements themes** (they replaced them): their licence (CC BY-NC-SA; commercial use
  only as the complete unmodified theme, OpenAndroMaps asks for written permission) rules out
  a store release; `biker.xml` in the upstream example app is Elevate-derived too. A stored
  `elements`/`elementsDark` choice is read as `detailed`/`detailedDark`
  (`_colorSchemeFromName`). [M2]
  * **Vendored + patched** at `third_party/mapsforge_flutter` (via `dependency_overrides`,
    see `third_party/mapsforge_flutter/PATCH.md`): upstream 4.0.0's `TileJobQueue` emitted
    tilesets stamped with the render's *old* center and dropped position updates while a
    render was in flight, so a GPS-follow map left the tiles frozen and jumped ~one tile
    (~hundreds of m) at a time while the marker/track followed correctly. The patch
    re-stamps every emitted tileset to `mapModel.lastPosition` (cheap re-projection of
    already-loaded tiles) so the map pans smoothly. Drop the override if fixed upstream.
* **GPS: native continuous `LocationManager` on Android (NOT geolocator).** Android uses
  ONE held-open `LocationManager.requestLocationUpdates(GPS_PROVIDER, 1000ms, 0f)` in
  `MainActivity.kt`, streamed to Dart over the `cycle/location` EventChannel and consumed by
  `NativeLocationService` (`lib/core/services/native_location_service.dart`,
  `locationServiceProvider` picks it on Android). This is exactly what OruxMaps does, and —
  proven on the real A33 via `dumpsys location` — the only thing that holds a solid fix here.
  **iOS uses `AppleLocationService`** (`lib/core/services/apple_location_service.dart`): ONE
  continuous Core Location request via geolocator's `getPositionStream` (`AppleSettings`:
  `fitness`, `pauseLocationUpdatesAutomatically: false`, background updates on with
  `UIBackgroundModes: location`). The "don't use `getPositionStream`" rule below is about
  geolocator's *Android* implementation on the A33; on iOS the stream is Core Location's own
  continuous updates, the standard way to track. It also implements `LocationPowerControl`,
  so the GPS lifecycle gate below runs **in Dart** on iOS (`AppLifecycleListener` +
  recording state; `locationPowerControlProvider` returns the same instance). The
  `flutter_foreground_task` service is Android-only (`NoopRecordingForegroundService` on iOS).
  Other platforms fall back to `GeolocatorLocationService` (`location_service.dart`).
  Permission still goes through geolocator (that part is fine); only the position stream is
  native.
  * **Why native, not geolocator (both of its paths failed on the A33).** (1) One-shot
    `getCurrentPosition` polling **cold-restarts the GPS on every call** — `dumpsys`/logcat
    showed `mStarted=false → startNavigating` per poll and the request toggling ON/OFF every
    1-2s, so the receiver never settled into a lock; back-to-back polling made it *worse*
    (no fix at all). (2) `getPositionStream` **never engages the receiver** on this hardware
    (no fixes, no GPS icon). A raw `LocationManager` request registered natively holds ONE
    continuous request (dumpsys: a single `@+1s0ms HIGH_ACCURACY` that stays on for minutes,
    like OruxMaps) so the GPS keeps navigating. **Do NOT go back to geolocator for the
    position stream**, and do NOT reintroduce `getPositionStream` or `getCurrentPosition`
    polling.
  * **Verify on the real A33, via dumpsys — not the emulator, not a location dot.** The
    emulator's `geo fix` satisfies `getLastKnownLocation`, so a dot on the map (or a stale
    `last location` in dumpsys) does NOT prove live fixes are flowing. Confirm
    `dumpsys location` shows Cycle's `gps provider` request held **continuously** (not
    toggling OFF between fixes) like OruxMaps'.
  * **GPS starts at app launch, ahead of the UI.** `main()` owns the `ProviderContainer`
    and warms `currentPositionProvider` (+ `ensurePermission`) immediately, before
    `runApp`, so acquisition begins the instant the app starts rather than when the map
    screen finishes building (behind the async map load). GPS is the priority sensor.
  * **The GPS request is held only while it has a consumer** (`MainActivity.updateLocationUpdates`):
    Dart is listening AND (the app is in the foreground OR a ride is recording). It used to
    stay registered for the whole process lifetime — `removeUpdates` ran only in `onDestroy`,
    and `onCancel` never fires because Dart never cancels the stream — so the receiver kept
    navigating at 1 Hz after a ride was stopped, in the background, screen off, until Android
    reclaimed the process. That drain is invisible to the per-ride battery stat (sampled only
    between Start and Stop), which is what made Android's per-app battery usage read several
    percent higher than the recorded rides accounted for. Recording state is pushed across the
    `cycle/location_control` MethodChannel (`lib/core/services/location_power_control.dart`,
    from `RecordingController.start`/`resume`/`stop`); the foreground half the activity knows
    from `onResume`/`onPause`. **This is a lifecycle gate, not a duty cycle** — while the
    request is registered it is still the ONE continuous 1 Hz request, started/stopped only on
    a foreground/background or recording transition, never per fix. Do NOT "save more" by
    raising the interval when idle: a longer interval lets the receiver duty-cycle, which is
    the same "never settles into a lock" failure documented above, for little real saving.
    **`setRecordingActive(true)` must be the FIRST thing `start()`/`resume()` do**, before the
    wakelock/DB write/foreground-service start — starting the foreground service can push the
    activity through `onPause` (it may raise a notification-permission dialog), and a pause
    evaluated while the gate still reads "not recording" drops the GPS request one second into
    the ride. Caught on the emulator via `dumpsys location` (a `-registration` right after the
    volume-key start, with no re-registration); the four-state probe — foreground idle /
    background idle / foreground recording / background recording — is what makes this visible,
    so re-run it after touching either side of the gate.
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
* **BLE sensors:** `universal_ble` (BSD-3, Navideck; pinned to 2.x) using the standard
  Bluetooth SIG GATT profiles (HR `0x180D`, CSC `0x1816`, Power `0x1818`); modern Garmin
  dual-band sensors work over BLE with no special code. Parsers + CSC speed/cadence + GPS/BLE
  speed fusion live in `lib/core/sensors/` (pure Dart, heavily unit-tested); the universal_ble
  glue is in `ble_sensor_service.dart` behind a `SensorService` interface (fake for
  tests/emulator). Its connection logic is unit-tested against a fake universal_ble platform
  (`UniversalBle.setInstance`, `test/unit/ble_sensor_service_test.dart`) that models native GATT
  clients the way universal_ble's Android code does — only the newest client per device is
  remembered, so a second connect while one is pending leaks the older one.
  **Replaced flutter_blue_plus** (2026-10): FBP 2.x switched to a custom licence (free only for
  personal/non-profit use, relicensing forbidden), incompatible with GPL-3.0 and with ever
  earning money from the app. **Don't go back to FBP 2.x.** The on-device findings below were
  made with FBP; the strategy carried over unchanged, but re-verify them on the A33/iPhone after
  touching this code. Two universal_ble specifics: (1) a connect's `timeout` only bounds the
  *Dart* wait — the native request keeps going — so a timed-out direct attempt is cancelled with
  `UniversalBle.disconnect` before registering autoConnect, and a pending autoConnect is
  cancelled before the next direct attempt (otherwise every 30 s retry tick would add a GATT
  client); (2) names only come with scan results, so they're cached from scans and, for a
  sensor linked without a scan, looked up via `getSystemDevices` (with our service filter on
  iOS, where it's required; *without* one on Android, where a filter makes universal_ble connect
  to every system device); (3) it doesn't merge duplicate connects the way FBP did, so
  `_directInFlight` allows one direct attempt per sensor at a time — `resumeConnections()`
  connects and then runs a retry tick at once, which opened two GATT clients to the same HR
  strap on the A33 (two `clientConnect … isDirect=true` 50 ms apart in `dumpsys
  bluetooth_manager`); (4) "was this a real link?" (re-register autoConnect after a drop, but
  not after a failed attempt) is `_linkUp`, set on the radio-level connection event — not
  `_connected[id].connected`, which only flips after service discovery: on the A33 a link
  left over from a killed app process connected in 80 ms and was torn down mid-discovery,
  leaving nothing pending; (5) `suspendConnections`/`resumeConnections` are serialized
  (`_transition`): `SensorPowerGate` fires them unawaited, and on iOS (no grace, the app frozen
  at the lock) both run on unlock — the suspension's teardown then cancelled the connect the
  resume had just started and dropped the target (seen in `idevicesyslog`: two
  `CBMsgIdConnectPeripheral` then two `CBMsgIdCancelPeripheralConnection`, then silence);
  (6) on iOS a CoreBluetooth connect never times out, so retry ticks leave a pending
  autoConnect alone (`_pendingConnectWaits`) instead of cancelling and re-issuing it every
  12-18 s. Bluetooth runtime permissions are requested in `ensureReady()` (FBP did that
  implicitly). On iOS, Bluetooth and GPS start in parallel at launch (both at the same second
  in the log); a sensor that links late was out of reach, not waiting for the GPS.
  **Reconnection: one-shot DIRECT connect, no app-level BLE scanning.**
  `BleSensorService.connect()`/`setActiveTargets()` do a one-shot
  `UniversalBle.connect(autoConnect: false)` per target (`_attemptDirectConnect`) — a direct
  connect links fast when the sensor is advertising (a worn HR strap, a spinning cadence
  sensor), whereas passive `autoConnect: true` frequently **never links a present sensor**
  (confirmed on-device: the app registered autoConnect for a worn HR sensor and it stayed
  disconnected — the library made the connect call, no link; switching to a direct connect linked it
  in ~2s). Crucially a direct connect does NOT scan, so — unlike the removed active-scan
  loop — it doesn't disturb the GPS radio. If the sensor isn't reachable now, it falls back
  to passive `autoConnect: true` (quiet on the radio) for later; a **mid-ride drop** of an
  active target also re-registers passive autoConnect (a direct retry could fight a brief
  out-of-range blip). The manual reconnect tap uses the same direct-connect path.
  **Do NOT reintroduce an app-driven active-scan retry loop.** An earlier version
  did exactly that (a periodic `startScan` — targeted `withRemoteIds`, then service-filtered
  — backing off 10s→60s while a paired sensor was missing) to make reconnection fast/
  deterministic. It **wrecked the GPS fix**: on the Galaxy A33's shared Wi-Fi/BT/GPS radio,
  an 8s BLE scan every 60s (which ran the whole ride whenever a profile listed a sensor the
  rider wasn't carrying) competed with the GNSS receiver — confirmed on-device via
  `dumpsys location` (Cycle's GPS request cold-restarting) and `logcat` (`BluetoothLeScanner
  Start/Stop Scan` every minute) next to OruxMaps holding a rock-solid continuous fix with
  zero scanning. GPS is the priority sensor; passive autoConnect is quiet on the radio. The
  trade-off — autoConnect can be slow/non-deterministic to re-link a sensor that went idle —
  is accepted; revisit sensor-reconnect speed only with an approach that does not actively
  scan during a ride. Pairing persists each sensor's `SensorKind`s alongside its id
  (`PairedSensorsStore`, migrated from the old id-only list) so callers — e.g. which
  dashboard tiles to show — know what a paired sensor *is* without needing a live connection.
  A bike profile can restrict which paired sensors it actively pursues
  (`BikeProfile.sensorIds`, `null` = all paired — see bike profiles below); `SensorService`
  exposes this as `setActiveTargets(ids)`, and `SensorConnectionController` recomputes/applies
  it whenever the active bike or its sensor selection changes.
  **Manual quick reconnect:** tapping a sensor stat tile on the home screen kicks a one-shot
  direct connect (same `_attemptDirectConnect` path) for that stat's sensor — HR/power via
  `reconnectKind(kind)`, and **SPEED vs CAD via `reconnectCsc(wantSpeed:)`**. A speed sensor
  and a cadence sensor are the *same* GATT type (CSC), so they can't be told apart by kind;
  `reconnectCsc` distinguishes them **by name** (SPD/SPEED vs CAD/RPM/CADENCE) when more than
  one CSC sensor is paired (a single one is unambiguous; unclear names → reconnect all CSC).
  Without this, both the SPEED and CAD taps reconnected *both* CSC sensors, which read as the
  two being "mixed up".
  **Bounded retry window (no scan):** `SensorService.retryConnections()` (re)arms a ~5-minute
  timer that re-issues a direct connect to any not-yet-linked target every 30s, stopping
  early once all are connected. It's armed on startup and again on **ride start/resume**
  (`RecordingController.start`/`resume`), so a sensor that wasn't ready at launch (just
  mounted / waking on the bike) still links without a tap. Direct connect only — NEVER a
  scan — so it stays clear of the GPS radio; it's bounded, not the removed perpetual loop.
  **Links are released while the app is backgrounded with no ride**
  (`SensorService.suspendConnections`/`resumeConnections`, driven by `SensorPowerGate` in
  `lib/features/sensors/application/sensor_power_gate.dart`, owned from `main()`) — the
  Bluetooth counterpart of the GPS lifecycle gate. A pending `autoConnect` registration never
  expires, so a paired sensor the rider isn't carrying keeps the BT controller reaching for it
  as long as the process lives: measured on the real A33 after a weekend of app-open standby as
  **~169 mAh (~3% of the battery) blamed on Cycle, nearly all of it screen-off**, with six GATT
  client registrations held open and — importantly — *zero* BLE scan time, so this is the cost
  of passive autoConnect itself, not of scanning. The gate condition is background AND not
  recording (a backgrounded recording ride keeps everything), with a 3s grace period (short on purpose: Android's cached-app freezer can freeze a
  backgrounded process within seconds, and a timer that loses that race never fires) so a
  quick app-switch doesn't churn registrations. **iOS gets no grace at all**
  (`SensorPowerGate.platformGrace()`): iOS suspends a backgrounded app within ~2 s, so the 3 s
  timer never fired there — verified on the iPhone 12 mini via `idevicesyslog`: locked
  22:58:41, suspended 22:58:43, and the `CBMsgIdCancelPeripheralConnection` only went out
  when iOS next woke the app (~3 min later; pending connects meanwhile stayed in
  `bluetoothd`). The same log showed `locationd` `stopLocation` 1 s after the lock, i.e. the
  Dart GPS gate (`AppleLocationService`) works. Re-check both with `idevicesyslog | grep
  cycleapp` (look for `stopLocation` and `CancelPeripheralConnection` right at the lock). `BleSensorService` keeps the desired target set
  separately from the live one, so a bike-profile switch while suspended updates the plan
  without waking the radio; resuming goes through the ordinary direct-connect path plus the
  bounded retry window, adding no scan. Verify with
  `adb shell dumpsys bluetooth_manager | grep -c "app: com.cycleapp.cycle"` — the GATT client
  count should fall to zero shortly after backgrounding without a ride, and come back on resume.
  With flutter_blue_plus there was a **~1-minute tail** before it reached zero (FBP queued
  connect calls and couldn't abort one in flight; verified on a real A33: `SUSPEND` at 00:51:35,
  last client unregistered 00:52:31). universal_ble doesn't queue connects and its `disconnect`
  aborts an in-flight one, which `_removeTarget` now does, so the count **should drop to zero
  within seconds** — not yet verified on the A33. Still sample repeatedly over ~90 s rather than
  trusting one reading.
  **Sensor values live only as long as their sensor's link** (`SensorSnapshotMerger`,
  `lib/core/sensors/sensor_snapshot_merger.dart`, pure + unit-tested; used by both
  `BleSensorService` and the test fake). Each linked device keeps its own partial snapshot; the
  merged one is recomputed from the devices present, and a disconnect/removal drops that
  device's contribution and **re-emits**. It used to be one global snapshot built with
  `copyWith(x ?? this.x)` — which can never set a field back to null — and nothing cleared or
  re-emitted on disconnect, so (a) a removed HR strap's last bpm stayed on the dashboard and was
  stamped onto every point of the *next* ride (`RideController._latestSnapshot` →
  `recordPoint`), corrupting its average; same for cadence and power; and (b) a cadence-only
  CSC sensor's results always carry `speed = null` ("hold"), so with one global snapshot every
  cadence notification re-broadcast a departed speed sensor's last wheel speed, which
  `RideController._onSnapshot` fed to `SpeedFusion.updateBle` stamped *now* — a fresh BLE
  reading — keeping the speed tile "from sensor" green. (RideController's "speed sensor
  dropped → clearBle" check can't help: speed and cadence sensors are the same
  `SensorKind.speedCadence`.) The CSC hold is preserved — *within* a live link a null field
  keeps that device's last value — but it ends with the link. `stale_sensor_values_test.dart`
  reproduces all three field symptoms end-to-end; mutation-checked (making `remove` a no-op
  fails exactly those three, with the linked-sensor control still passing).
* **Local DB:** `drift` (SQLite) for tracks/trackpoints. [M4]
  **Deleting a ride is a soft delete** (schema v5): `AppDatabase.deleteTrack` sets
  `deletedAt` (the "Recently deleted" trash, `RecentlyDeletedScreen`); `allTracks`/
  `watchTracks`/`tracksMatching` hide trashed rows, `allTracksIncludingDeleted` doesn't (use it
  for import dedup, so an old backup can't resurrect a deleted ride). `restoreTrack` undoes it;
  `purgeTrack` drops the points and keeps the row as a `pointsPurged` deletion marker for sync
  (or erases it outright for a duplicate whose start time is still live, or an unfinished crash
  artefact). `purgeExpiredTrash` runs at launch with `AppSettings.retentionDays` (default 30).
  **Never migrate the only copy:** `AppDatabase._open` calls `backupBeforeMigration`
  (`lib/core/db/migration_backup.dart`), which `VACUUM INTO`s `backups/cycle_backup_pre_v<N>_…`
  through a raw sqlite3 connection before drift opens/migrates an older-schema DB — bump
  `AppDatabase.kSchemaVersion` and this happens automatically for every future migration.
  **Migrations must be idempotent** (`_addColumnIfMissing` / `_createTableIfMissing`, never a
  bare `m.addColumn`): drift runs `onUpgrade` on *any* version mismatch — including an older
  build opening a newer DB — and then stamps its own `schemaVersion`. So installing a `main`
  build (v4) over a sync build (v5) reset `user_version` to 4 while the v5 columns stayed, and
  the next v5 build's plain `ADD COLUMN` died with "duplicate column name: name_clock" — the
  app couldn't open its DB at all (real iPhone, 2038 → main → 2045). Builds from different
  branches get installed on the same phones, so assume any up/down order.
* **Ride sync (WebDAV / Nextcloud):** `lib/core/sync/` (pure Dart, no plugin) + `features/sync/`.
  Settings → Data → Sync. Syncs through a `Cycle/` folder on the user's own WebDAV server
  (Nextcloud first-class: Login Flow v2 in `nextcloud_login_flow.dart` gets an app password via
  the browser; any WebDAV works with user + app password).
  * **Data model:** a ride's identity is its `startedAt` in whole seconds (same key every import
    dedups on). It syncs as four separately-versioned parts — name, bike, geometry (points +
    stats), deleted — each with a `SyncClock` (`<15-digit epoch ms>@<deviceId>`, string-ordered;
    `null` = pre-sync, oldest). Every `AppDatabase` edit method stamps its part's clock
    (`renameTrack`→name, `setTrackBikeProfile`/`assign*`→bike, `finalizeTrack`/
    `updateTrackStats`/`touchGeometry`→geometry, `deleteTrack`/`restoreTrack`→deleted); a new
    edit path that bypasses these won't sync — stamp it. The device id lives in the DB
    (`SyncMeta`).
  * **Merge (`RideDoc.merge`)** is per-part last-writer-wins over a total order (clock, then a
    content tie-break), so it's commutative + associative and phones converge in any order. An
    edit newer than the deletion clears `deletedAt` **without rewriting the deleted clock** —
    rewriting it made the result order-dependent (caught by the "order independent" unit test).
    Comparison keys use `\u0001` as separator so a missing clock sorts *below* real ones (a `|`
    separator sorted it above — conflict resolution was inverted until a test caught it). A
    purged copy beats an unpurged one with the same geometry clock (the purge spreads); restore
    re-stamps geometry so restored points beat a purged copy.
  * **Server layout — no shared index:** `rides/<startSec>~<deviceId>.json.gz` (each device
    writes only its own file names) + `profiles/<deviceId>.json`. A round (`SyncService`):
    PROPFIND → download only files whose ETag changed (cache: `SyncRemoteFiles` with the
    file's points-less doc) → merge into the DB (`LocalRideStore.apply`) → upload a ride only if
    no remote file already has exactly its signature → delete other copies the merged state
    `covers`, with `If-Match` so a copy changed meanwhile survives. Steady state is one file per
    ride. Unfinished rides (`endedAt == null`) and anything during recording are never synced.
  * **When:** only while the app is open (no background scheduler, by decision): startup (after
    `SyncController.startupDelay`, behind GPS), native network-change events (`cycle/network`
    EventChannel — `ConnectivityManager.registerDefaultNetworkCallback` in `MainActivity.kt`,
    `NWPathMonitor` in `AppDelegate.swift`, both registered only while foregrounded), app
    resume, ride stop, "Sync now"; debounced 30 s, single-flight. Each round first probes the
    configured addresses in order (primary/LAN, then optional fallback/public) with a ~3 s
    PROPFIND; none answering = `SyncUnreachable`, shown quietly, not as an error.
  * **LAN servers:** plain `http://` only with the explicit "Allow http" switch; self-signed
    TLS by pinning the cert's SHA-256 (`WebDavClient` `badCertificateCallback`, fingerprint
    shown in a trust dialog). `dart:io` sockets aren't subject to Android's network-security
    config or iOS ATS; iOS needs `NSLocalNetworkUsageDescription` (Info.plist) for LAN hosts.
  * **Safety backups:** `backups/cycle_backup_pre_first_sync_…` before a device's first sync;
    `cycle_backup_auto_…` (at most daily) before a round that would delete/replace data on the
    phone; only the `auto` ones are pruned after `retentionDays`.
  * **Same name = same bike.** Bikes created separately on two phones have different ids
    (timestamp ids), so the first real sync showed every bike twice on every phone.
    `ProfilesDoc.merge` now merges live profiles with the same normalized name (trim +
    lowercase) into the smallest id and records the others as `aliases` (synced, only ever
    added to; chains resolved by `ProfilesDoc.resolve`). Profiles sync **before** rides each
    round; rides are read through the aliases (`SyncService._aliased`) and the DB is remapped
    with `remapBikeProfiles`, **without** stamping the bike clock (same bike, new id — stamping
    would make every phone re-upload every ride). Add/rename to an existing name is refused in
    `BikeProfilesController` for the same reason.
  * **Sensors sync by name** (`lib/core/sensors/sensor_catalog.dart`). A BLE id isn't portable:
    Android's is the sensor's address (same on every Android phone), iOS gives each iPhone its
    own random UUID. So the synced `SensorCatalog` (inside the profiles file) is keyed by
    `KnownSensor.keyOf(name)` (trim + lowercase; sensor names carry serials) with name, kinds,
    `address` (only when an Android phone paired it — `sensorIdsPortableProvider`), clock and a
    `removed` marker. A bike's choice syncs as `BikeProfile.sensorKeys` + `sensorsClock` (its own
    part, merged independently of name/colour); each phone derives its local `sensorIds` from
    it (`SensorConnectionController._reconcileBikes`, no clock). Android links catalog sensors
    with an address immediately (no scan); iOS links them when a **manual** scan finds the name
    (`_linkKnown`) — never a background scan (GPS radio, see BLE section). Remove = synced
    removal. Pre-sync sensors/choices are adopted with an epoch-0 clock (`_adoptLegacy`), so
    any real choice wins. The UI path for a bike's sensors is `setBikeSensors` (stamps a clock,
    keeps names of sensors only another phone has linked); `setSensorIds` is local-only.
  * **Bike profiles** sync name/colour/deletion (`ProfilesDoc`, per-profile clock) but not
    `sensorIds` (sensor ids differ per phone — see sensor sync above) or the active profile. A
    fresh install's untouched "Bike 1" is dropped on its first sync if the server already has
    profiles and no local ride uses it.
  * Tests: `test/support/fake_webdav_server.dart` (real sockets, ETag/If-Match) drives
    multi-phone convergence (`sync_service_test.dart`), widget tests and the emulator GUI test
    (`integration_test/sync_test.dart`). Widget tests must set `HttpOverrides.global = null` —
    flutter_test answers every real HTTP request with 400 otherwise.
* **GPX:** `gpx` package — used for both ride export [M4] and follow-route import [M5].
* **Follow route [M5]:** `lib/features/routing/` — parse a GPX into a `FollowRoute`
  (cumulative distances), `RouteNavigator` does nearest-segment projection for
  cross-track/off-route + remaining distance (pure Dart, unit-tested). The route shows as a
  dashed-blue overlay on the map with a nav banner (name · km left · OFF-ROUTE). Import is
  **folder-based, not a system picker**: users drop `.gpx` files into the app's
  `routes/` folder (Android external files dir / iOS documents) and pick from an in-app list;
  a bundled `assets/routes/monaco_loop.gpx` is the "Follow demo route". We deliberately do
  **not** use `file_picker` — see Known gotchas.
* **Keep-awake:** `wakelock_plus` — note this is `FLAG_KEEP_SCREEN_ON` on the activity
  window, NOT a `PowerManager` wakelock, so it is inert while the app is backgrounded and
  dies with the process; there is nothing to "leak" and no battery to save by releasing it
  on pause. It has **more than one owner** (a recording ride, an in-flight map download), so
  `ScreenWakeService` reference-counts by owner key and only calls the platform on a
  transition — a single global flag meant `RecordingController.stop()` released the screen
  out from under a running region download (screen sleeps → OS suspends the app → download
  drops, resuming from its `.part` file only on retry).

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
  code and `ios/` config cross-platform. iOS builds come from **GitHub Actions**
  (`.github/workflows/build.yml` `ios` job, `macos-latest`, free since the repo is public):
  an **unsigned** `.ipa` artifact (`ios-ipa-unsigned`) that the user signs with a **free
  Apple ID** and installs over USB from Linux with **Impactor** (Flatpak
  `dev.khcrysalis.PlumeImpactor`); full steps in `docs/ios-sideload.md`. Free signing expires
  after **7 days**: re-install the same `.ipa` over the top (data is kept, the same rule as
  `adb install -r`) and never tell the user to delete the app. Test iPhone: **iPhone 12 mini**.
  The `test` job (analyze + tests) gates the `ios`/`android` jobs, so a lint failure silently
  means no iOS build; `third_party/**` is excluded from analysis for that reason.
  CI runs on **every push to any branch** (no `pull_request` trigger — it doubled every run
  for a branch with an open PR; the PR shows the push run's checks), skipped only for pushes
  that touch nothing but `docs/**`/`*.md`. Artifacts keep 30 days.
* **Release signing (stable key):** release builds are signed with a fixed key
  (`android/app/cycle-release.jks` + `android/key.properties`, **both gitignored**) wired in
  `android/app/build.gradle.kts`. This lets a release APK be updated in place (`adb install -r`)
  **without uninstalling**, so downloaded maps + other app data survive updates. Back up the
  keystore — losing it forces an uninstall to update again. The build falls back to the debug
  key when the keystore is absent (so a fresh clone still builds).

## Store release & monetisation (decided 2026-10-16)

Preparing for Google Play + the App Store. **The app stays free with no in-app purchases,
ads or subscriptions; donations happen outside the app only** (GitHub/website). Reason: any
in-app earning (even an IAP tip jar) most likely makes the publisher a "trader" under the EU
Digital Services Act, and the stores then show their address and phone to EU users. A free
app with no in-app monetisation can be listed as a non-trader. So: **don't add IAP/tips, ads, or a
donation link/button inside the app** (Apple only allows external donation links for
registered nonprofits; mentioning one in the store listing is risky too). Revisit only
together with an address service (ladungsfähige Anschrift).
Store-readiness work so far: Komoot upload removed (unofficial API), iOS volume keys removed
(guideline 2.5.9), Elements map themes replaced by mapsforge's LGPL ones (licence). Still open
(see the store-launch plan): new name + icon, OSM attribution,
open-source licences screen, OpenAndroMaps permission for in-app downloads, a store build
without `MANAGE_EXTERNAL_STORAGE`, privacy policy.
**Licence: GPL-3.0-or-later** (`LICENSE` is the verbatim FSF text, so GitHub detects it; keep
it that way) **plus one GPL §7 additional permission in `NOTICE.md`**: app-store
distribution (the App Store's terms add restrictions the GPL forbids; allowed as long as the
Corresponding Source stays public). A second one, for linking with flutter_blue_plus, was
dropped when that library was replaced by universal_ble. Only valid while the user is the sole copyright holder of
the app code: before accepting outside contributions, get them under the same permissions
(e.g. a short CLA or a contributor note). A new dependency must be GPL-3.0-compatible (MIT,
BSD, Apache-2.0, LGPL, MPL-2.0 are fine; GPL-2.0-only and "non-commercial" licences are not)
or needs its own exception — list it in `NOTICE.md`'s third-party table.

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
* **M6 — Upload (Strava):** done (self-hosted skipped per user). `lib/core/services/upload/`:
  `StravaClient` (official OAuth2 + multipart `/uploads` + poll), `UploadStore` (creds/token in
  `shared_preferences`), `RideUploader` (token/refresh/
  interactive-OAuth orchestration). OAuth is plugin-free: native `MainActivity` `cycle/oauth`
  channel (`openUrl` + capture `cycle://strava-callback` redirect) + manifest intent-filter;
  `NativeOAuthAuthenticator` polls it. UI: Rides → "Upload accounts" settings (`/upload-accounts`)
  + cloud-upload action on ride detail. Verified: 23 unit/widget tests + a real-socket
  mock-server Strava test; build/launch on the emulator. **Real OAuth + a real upload need the
  user's own Strava API app (client_id/secret) + account, done once on a device — see the M6
  device checklist.**
  **Komoot upload was removed** (store readiness): Komoot's official API is partner-only, so it
  logged in with the rider's email + password against Komoot's private endpoints — against
  Komoot's terms and App Store guideline 5.2.2. `SharedPrefsUploadStore.forgetKomootLogin()`
  (run from `main()`) deletes a password an older build saved. Don't re-add an unofficial
  upload; GPX export is the route into Komoot unless they grant API access.
* **M7 — Physical buttons & polish:** done. **Volume-key start/stop:** native `MainActivity`
  intercepts VOLUME_UP (start) / VOLUME_DOWN (stop) in **`dispatchKeyEvent`** (NOT `onKeyDown`
  — a FlutterActivity routes keys through the FlutterView first, which swallows the volume keys
  before `onKeyDown`; `dispatchKeyEvent` is the activity's first look, before the view hierarchy
  / default volume handling) and routes them over the `cycle/hardware_buttons` MethodChannel
  (plugin-free). Consumes both down+up (ignores key-repeat) so the volume neither changes nor
  shows its UI. `HardwareButtonService`/`HardwareButtonController` toggle recording, gated by a
  setting. **Foreground+screen-on only** (capturing keys with the screen off needs a media
  session / accessibility service — out of scope).
  **Volume keys are Android-only.** iOS has no public API to intercept them
  (`AVCaptureEventInteraction` needs a running camera session). An earlier iOS workaround —
  pin the media volume at 0.5 via an off-screen `MPVolumeView` and KVO-observe
  `AVAudioSession.outputVolume` — worked, but **was removed because it breaks App Store
  guideline 2.5.9** (apps must not alter the volume buttons). Don't bring it back for store
  builds. `volumeKeysSupported` (Android only) gates the settings switches, the
  `setEnabled` call (`HardwareButtonController` never sends it on iOS) and
  `AppSettings.startStopButtonVisible`: the button may be hidden only while a hands-free control
  that can both start AND stop is on — volume keys (Android) or the proximity hold (iOS);
  auto-start doesn't count (it can't stop). iOS's `HardwareButtons` in `AppDelegate.swift` now only serves the
  proximity half of the `cycle/hardware_buttons` channel.
  **Glove-friendly extras (both opt-in, `AppSettings`):** (1) **proximity hold** (iOS only,
  `proximityHoldSupported`): native forwards raw covered/uncovered edges as `onProximity` over
  the same channel (`UIDevice.isProximityMonitoringEnabled`, active only while foreground +
  enabled); the "covered ≥2s, once per cover" rule is Dart (`lib/core/controls/
  proximity_hold_detector.dart`), and `HardwareButtonController` toggles recording on a hold.
  (2) **auto-start** (`lib/core/controls/auto_start_detector.dart` + `AutoStartController` in
  `features/dashboard/application/auto_start_providers.dart`, watched by the map screen):
  ≥8 km/h sustained 5s on the shared GPS stream (no extra GPS cost) starts a ride; after a
  ride it stays disarmed until <3 km/h for 60s, so stopping while rolling doesn't instantly
  restart. Stop stays manual.
  **Vibration confirmation** (`AppSettings.vibrateOnStartStop`, default on): `RecordingController`
  calls `_confirm(RideFeedback…)` — started = 1 pulse, stopped = 2, bike switched via
  `cycleBikeProfile` = 3 — at the *start* of `start()`/`stop()` (unawaited, after the
  already-recording guard), so it's felt instantly for every trigger (volume, proximity hold —
  where it's the "you can take your hand away" cue, since the screen is dark — auto-start, the
  on-screen button). Not on `resume()` (automatic crash recovery). Native `cycle/haptics`
  `vibrate(n)`: Android `VibrationEffect.createWaveform` (350 ms on / 250 ms off, `VIBRATE`
  permission); iOS repeats `kSystemSoundID_Vibrate` every 0.6 s — the strongest buzz an app can
  trigger (a Taptic impact or Flutter's `HapticFeedback` is too subtle to feel through a
  handlebar mount). Front-camera gestures and accelerometer "knock" detection were
  considered and rejected (camera battery/heat/indicator; handlebar vibration false triggers).
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
  (`AppColorScheme` Dark/Light/B&W + Detailed/Detailed — Dark, Settings → Appearance): each
  restyles the app `ThemeData` (`buildAppTheme`), the offline map render theme (`dark.xml`/
  `light.xml`/`bw.xml`/`detailed.xml`/`detailed_dark.xml`, swapped via `activeMapModelProvider` reloading), and the overlay accents
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
    only; iOS (`AppDelegate.swift`, `UIDevice.batteryLevel`) is rounded to **5 %** by iOS since
    iOS 17 — not fixable by the app — so short iOS rides read 0 %). The map **zoom is remembered** (`AppSettings.mapZoom`, saved on app pause, restored
    as the initial/first-fix zoom). The recorded track + followed route render as a **dashed
    line with chevron arrowheads** (`Icons.keyboard_arrow_up` `IconMarker`s). Map **rotation is
    disabled** (vendored patch 2, `generic_gesture_detector` drops `RotationHandler`).
* **OruxMaps import** (Settings → Data → "Import from OruxMaps",
  `oruxmaps_import_screen.dart`). `lib/features/tracks/application/oruxmaps_import_service.dart`
  reads OruxMaps' `oruxmapstracks.db` (SQLite, `tracks`/`segments`/`trackpoints`; the
  position/time columns match the schema confirmed by github.com/wolfgangasdf/oruxtool, but
  heart rate/cadence/speed are packed into a `trkptsen` BLOB that reader doesn't document —
  see the sensor-decoding bullet below, and the file's doc comment) and merges its rides into
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
  * **Manual pick, for when bulk still can't reach the file.** Some Android versions/OEM
    skins block `Android/data/<pkg>/…` from every app, including a granted one — confirmed
    on a real device where `File.exists()` returned false for the exact verified path even
    with "All files access" granted (`appops` showing `allow`), and Samsung's own file
    manager failed identically on the same folder with an explicit "only viewable from a
    computer" message. Since `file_picker` doesn't build here (AGP 9, see Known gotchas), a
    plugin-free SAF (`ACTION_OPEN_DOCUMENT`) picker is wired natively: `cycle/pick_document`
    in `MainActivity.kt` (`startActivityForResult`/`onActivityResult`, no plugin) →
    `lib/core/services/document_picker_service.dart` → a **"Pick database file"** button on
    the import screen. The screen's instructions tell users to copy `oruxmapstracks.db` out
    via a PC/USB connection (or any file manager that *can* browse it) into an ordinary
    folder like Downloads, then pick that copy. Both this and the share-intent path
    (`cycle/incoming_oruxmaps`) hand Dart a **path to a native cache-file copy, not raw
    bytes** — an early version returned the picked file's bytes as a single MethodChannel
    argument, which for an 80+ MB `oruxmapstracks.db` produced a **silently truncated**
    in-memory copy on a real device (the import "succeeded" but only covered the file's
    oldest rides, since it only got partway through before the transfer broke down);
    streaming straight to a cache file on the native side and handing back the path avoids
    marshalling the whole file through the channel at all.
  * **Import performance: one transaction per track, not one commit per point.**
    `OruxMapsImportService.importFrom`'s per-track/per-point insert loop originally awaited
    each `createTrack`/`addPoint`/`finalizeTrack` call individually, with **no transaction**
    wrapping them — every insert commits (fsyncs) on its own. A real multi-year OruxMaps
    history (hundreds of tracks, hundreds of thousands of points) made this take **well over
    an hour** on a real device, which looked indistinguishable from "the import silently
    stopped partway" if you checked before it finished (this is what actually produced the
    apparent "missing 2025/2026 rides" bug report — the import hadn't stopped, it just
    hadn't gotten there yet). Wrapping each **track's** inserts in one `_db.transaction()`
    (not one giant transaction for the whole import, so an interrupted run still keeps
    whatever it already finished) cut the same real-device import from 60+ minutes to
    ~3.5 minutes.
  * **Concurrent imports double-insert — guarded at both the UI and service layer.**
    `importFrom`'s dedup reads "already imported" once per call; two overlapping calls (e.g.
    a double-tap, or an impatient re-tap on the several-minutes-long import before it
    finishes) both see the same pre-import snapshot and neither sees the other's in-flight
    inserts, so every track in the overlap gets imported twice — confirmed on a real device
    (duplicate rows, same ride/start-time, after re-triggering the picker while a previous
    import was still running). `OruxMapsImportScreen` now shows a progress indicator and
    disables its import buttons while `_isImporting`; `OruxMapsImportService` itself also
    throws if a second `importFrom` is called while one is already in flight, as a backstop
    for any other caller. See "Remove duplicate rides" below for cleaning up duplicates a
    pre-fix import already left behind.
    Verified end-to-end on a real device (Galaxy A33) by simulating a user's manual-copy
    workflow: `adb`-pulling the on-device OruxMaps db (via its group-readable `.backup`
    file — the live db is owner-only 600, the rotating `.backup`/`.backup2` are 660, and
    even `adb shell`'s `cat` was blocked on the primary file by the same OS-level
    restriction as the app itself, though `ls` still listed it) to the host, `adb push`ing
    it back into `/sdcard/Download/` to stand in for a manual copy, then driving the actual
    picker UI (`am start` + `input tap`/`swipe`, bounds read via `uiautomator dump` —
    screenshot pixel coords need ×1.2 to map to real device coords, `uiautomator` bounds
    don't) through the system Files app to select it, and cross-checking the result via a
    fresh **Backup & restore → Export backup** pulled and inspected directly (`sqlite3`) —
    confirming the full 746/746 tracks (2023 through 2026) landed with zero duplicates
    after the fix, versus a silently-still-running partial import and later duplicate rows
    before it.
  * **Heart rate/cadence: packed into a `trkptsen` BLOB, not named columns.** A real device
    export's `trackpoints` table has no `heartrate`/`cadence`/`power` columns at all — an
    earlier version of this importer only looked for named columns (plus a doc comment
    claiming it read them "opportunistically", which was aspirational text that was never
    actually implemented) and so silently imported zero sensor data, even though the source
    had plenty. Reverse engineered against a real 746-track/420k-point export
    (`_decodeSensorBlob`): `trkptsen` is always exactly 16 bytes, four **big-endian
    float32s** `[heartRateBpm, cadenceRpm, temperatureCelsius, speedMps]`, `-1.0` as the "no
    data" sentinel (confirmed against real ranges: heart rate 56–181 with never exactly 0,
    cadence 0–~90 with genuine zeros while coasting) and thermodynamic absolute zero
    (-273.15°C) as temperature's sentinel (never populated in this export — no temperature
    sensor was ever paired). The blob's own speed is preferred over any named speed column
    too, since the real export had no separate speed column either (so speed was *also*
    silently never imported before this). Power isn't present in this blob at all — may
    simply not have been recorded for a rider with no power meter, unconfirmed either way.
    **Backfill for rides imported before this fix:** `importFrom` no longer just skips a
    track it's already seen — for an existing match (same start time) it now runs
    `_backfillSensorData`, filling in heart rate/cadence on that ride's already-saved points
    (matched 1:1 by position, existing non-null values left alone) via a new
    `AppDatabase.updatePointSensor`. So re-running "Pick database file" / "Import OruxMaps
    database now" after upgrading past this fix repairs already-imported rides too, not just
    new ones — `importFrom`'s return changed from a plain `int` to `({int imported, int
    backfilledRides})`, and `summarizeOruxImport` (shared by the import screen and the
    incoming-share auto-import) surfaces both counts, so a re-run that finds nothing new to
    import but fixes 746 existing rides doesn't read as "No new rides" with no other
    indication anything happened.
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
* **Remove duplicate rides** (Settings → Data): `removeDuplicateTracks` (`track_repair.dart`)
  groups rides by exact start time and deletes every copy but the first-inserted (lowest id)
  one. Added alongside the OruxMaps import concurrency fix above, to clean up duplicates a
  pre-fix (or a future double-tapped) import already left behind — a one-tap, on-device fix,
  no adb/DB surgery needed. Safe to run any time; a no-op with no duplicates present.
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
  * **Per-bike sensor selection:** each profile's ⋮ menu has "Sensors for this bike" — a
    checklist (sourced from `sensorConnectionProvider`'s full paired-sensor list) that sets
    `BikeProfile.sensorIds` (`null` = all paired sensors, the default). Only sensors checked
    for the *active* bike are actively pursued (see the BLE sensors reconnection note above)
    and shown as dashboard tiles — so a second bike with no cadence/speed sensor doesn't
    endlessly retry connecting ones that live on a different bike, and doesn't show empty
    tiles for them either. Pairing a new sensor from the Sensors screen adds it to the active
    profile's selection too (if that profile has a restrictive one), so it isn't immediately
    dropped as out-of-scope.
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

* **Battery runtime test** (`lib/features/battery_test/`, Settings → Data, `/battery-test`):
  answers "how long does the phone last on a ride" without riding. While running, the app's
  `locationServiceProvider` returns a `SimulatedRideLocationService`: a `SimulatedZigzag`
  (`lib/core/battery_test/simulated_zigzag.dart`, 1 fix/s, speed varying 25-35 km/h as two
  overlapping sine waves with an exact integral for the distance), a lawn-mower pattern of
  3 km east/west rows 300 m apart advancing north, starting at the last real fix (else the shown
  map's centre) and kept inside the shown map's bounds (`installedMapBoundsProvider`, minus
  200 m; ±20 km when unknown, ~1 km for the demo map), turning back onto rows *between* the
  earlier ones (van der Corput offsets). **Why not a loop** (the first version was an 800 m
  circle): a loop re-draws the same cached tiles lap after lap, while a ride keeps rendering
  fresh map, so the loop overstated the runtime; 450 km (15 h at 30 km/h) of zigzag still spans only
  ~40 km, so it stays on a regional map. **DIST/AVG/MAX run during a test**
  (`RideController._accumulating` = recording OR `simulatedRideProvider != null`; reset by the
  test's start/stop), but `recordPoint` still only runs for a real recording. Like a ride, the test also **draws the track**
  (`map_screen` grows `_path` while `batteryTestProvider != null`, cleared when a test starts or
  ends) and **writes every fix to a database** — a throwaway `AppDatabase` on
  `battery_tests/scratch_ride.sqlite` (`BatteryTestStore.openScratchDb`), same schema and
  insert path as `recordPoint`, deleted on stop and before the next test. Both are real per-fix
  costs of a ride; leaving them out (as the first version did) also overstated the runtime. A
  track is one `PolylineMarker` whose whole path is re-projected on every fix (the library only
  culls by the *whole* track's bbox), so its cost grows with point count, not visible length.
  The **real GPS stays
  subscribed underneath** (`deviceLocationServiceProvider`; fixes are only counted) and the
  screen is held on (`ScreenWakeService.ownerBatteryTest`). The platform GPS is now
  `deviceLocationServiceProvider`; `locationServiceProvider` is the effective one everything
  reads, and tests keep overriding that. `locationPowerControlProvider` unwraps the simulation
  to reach the real service's gate. **`RecordingController.start()` refuses while a test runs**
  (`simulatedRideProvider != null`), so simulated positions can never become a ride (volume
  keys, auto-start and the button all go through it). Results are **not in the ride DB**
  (deliberately, which also avoids a schema bump): one JSON-lines file per test in
  `<appSupport>/battery_tests/` (`BatteryTestLog`), appended with a flush every minute, so it
  survives the phone dying. No `stop` line means the phone switched off, and the last sample is
  the time of death (±1 sample). The map screen announces an unseen shutdown result once
  (`unseenShutdownResultProvider`, then a `seen` line). On iOS the levels are 5 % steps, so the
  **runtime** is the reliable number and %/h is only shown from 10 min on.

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
`versionCode`).

**Every build that gets installed on a phone (adb, sideloaded `.ipa`, CI artifact handed to the
user) is a release.** There are no "just a new build" installs of an unchanged version that
carry new features. For each one, decide the bump from the changes since the last version:

| Changes since the last version | Bump | Example |
| --- | --- | --- |
| Any new user-visible feature/capability (with or without fixes) | **MINOR**, PATCH → 0 | 0.2.3 → 0.3.0 |
| Only bug fixes / internal changes, no new feature | **PATCH** | 0.2.3 → 0.2.4 |
| Breaking change (incompatible data/sync format, removed feature) | pre-1.0: **MINOR**; from 1.0 on: **MAJOR** | 0.2.3 → 0.3.0 |
| Rebuild of the *same* code (e.g. re-signing, a reinstall) | build number only | 0.2.3+2050 → +2051 |

* The **build number increases on every build, always**, and is never reset (it's Android's
  `versionCode` — a lower one can't be installed over a higher one without uninstalling).
  `--split-per-abi` APKs add an ABI offset (arm64 = +2000, so `+2049` shows as `versionCode`
  4049 on the A33) — keep building the phones' APKs the same way, or a lower code won't install.
* Several commits can share one version **only if none of them was installed** in between.
  Once a version has been installed, the next installed build with new changes gets a new
  version number per the table above.
* A feature branch that adds a feature bumps MINOR on its first installed build; further
  fixes on the same branch before merge stay in that version (build number still increases).
  If `main` has meanwhile moved to a higher version, re-bump on merge.

On each release:
1. Set `version:` in `pubspec.yaml` (`X.Y.Z+build`, build = previous build + 1).
2. Move the `CHANGELOG.md` `[Unreleased]` items into a new dated `## [X.Y.Z] - YYYY-MM-DD`
   section and add its compare link at the bottom (`[Unreleased]` then compares from it).
3. Run `tool/fl python3 tool/gen_version.py` to regenerate `lib/core/app_version.dart` (shown in
   Settings → About; never hand-edit it).
4. **Commit before installing** — the release commit holds exactly the code that goes onto the
   phone, with the new version in `pubspec.yaml`. Never install from a dirty working tree:
   0.3.1 was, its fix got committed together with 0.3.2's, and so no commit (and no tag)
   matches what was installed.
5. Tag that commit with an annotated tag `vX.Y.Z` (`git tag -a vX.Y.Z -m "Cycle X.Y.Z"`) and push
   the tag with the branch — the `CHANGELOG.md` compare links point at these tags. A release
   made on a feature branch is tagged there; the tag stays valid after a merge commit.

Keep `CHANGELOG.md` in [Keep a Changelog] form. History note: builds `0.1.0+2` … `0.1.0+2048`
added features while only the build number went up; they were rolled up into **0.2.0** (+2049).
Don't repeat that.

## Updating this file

This file shall be kept up-to-date automatically. Update the tech stack and milestone
progress sections as features land.
