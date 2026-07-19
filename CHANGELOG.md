# Changelog

All notable changes to **Cycle** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Pre-1.0 (0.x) means the app is under active development and things may still change.

## [Unreleased]

### Added
- **Bike profiles** — record against different bicycles and see stats per bike or
  in total. A coloured chip in the top-left of the home screen shows the active
  profile; tap it to switch, or manage profiles (add/rename/recolour/delete) from
  **Settings → Bikes**. No pop-up when starting a ride: the volume-up button
  starts recording with whichever profile is already active, and pressing it
  again *while already recording* cycles to the next profile — correcting the
  ride in progress if the wrong bike was active, without interrupting it. Rides
  are stamped with their bike; the Rides list gets a filter row ("All" + one chip
  per bike, only shown once you have 2+) that filters both the ride list and the
  week/month/year summary cards, plus a small colour dot on each row.
  **Correcting past rides:** a ride's detail screen shows its bike (or
  "Unassigned") — tap to change it via the same picker. To bulk-fix a whole ride
  history at once (e.g. after renaming your first profile to your bike's real
  name), **Settings → Bikes → Bike profiles → ⋮ → "Assign all rides to this
  bike"** sets every recorded ride to that bike in one go.
  **Classify rides** (Settings → Bikes → Bike profiles → filter icon) — find old
  rides matching a combination of criteria (only-unassigned, has cadence/heart-rate/
  power data, distance/average-speed/max-speed range, date range) and bulk-assign
  just the matches to a bike. ("Had a speed sensor" isn't offered as a criterion —
  unlike cadence/HR/power, that wasn't stored per point for rides recorded before
  this release, so it can't be reconstructed; new rides now record it, so it'll be
  available for those going forward.)
- **Import from OruxMaps** (Settings → Data) — bring in ride history recorded with
  OruxMaps, entirely on-device, no PC/adb. Bulk-import your whole ride history in one go by
  granting "All files access" (the same permission a file-manager app holds) — needed
  because Android 11+ otherwise blocks every other app from OruxMaps' storage entirely.
  Alternatively, share a single track's GPX export from OruxMaps' own Track Manager, no
  permission required. Either way, already-imported rides are skipped, so re-importing is
  safe.
- **Recalculate ride distances** (Settings → Data) — a one-tap maintenance action that
  recomputes every ride's distance/average/max from its recorded points using the current
  maths, for rides recorded before a distance-calculation fix (see "Fixed" below).
- **Resume an interrupted ride** — if a ride was cut short by a crash/kill, on
  the next launch the app offers **"Resume"**: recording continues into the same
  track with its distance/time/average carried over (the dead-time gap while the
  app was gone isn't counted).
- **Clean GPS spikes on a recorded ride** — a new wand action on the ride screen
  removes teleport outliers from an already-recorded track and recomputes its
  distance / average / max from the cleaned points (for rides recorded before the
  outlier filter below).
- **Auto-pause** — the ride timer, distance and average now pause automatically
  when you stop or slow below a threshold (default **5 km/h**), so waits at lights
  and breaks don't drag your moving average down. The TIME box shows **PAUSED**
  (amber) while paused. Configurable in **Settings → Controls** (on/off + the
  km/h threshold); max speed still records the true peak.
- **Detailed (Elements) map theme** — the full OpenAndroMaps *Elements* render
  theme (contour lines, POI symbols, named cycle routes, landuse detail) is now
  selectable in **Settings → Appearance**, alongside the minimal Dark/Light/B&W
  themes (kept as the lighter, battery-saving options). Bundles the theme + its
  ~195 symbols; a `file:` symbol loader resolves them from the app assets.
  A **dark/night** variant ("Detailed (Elements) — Dark") is also available.
- **Free-look on the map** — panning the map now pauses GPS auto-follow so you
  can scout alternative routes without it snapping back to your location on the
  next fix; a **recenter** button appears while paused — tap it to recentre and
  resume following.
- **Speed shows its source by colour** — the live SPEED value reads **green**
  when it comes from the BLE wheel sensor (accurate) and the normal accent when
  it's GPS, so you can tell at a glance which source is driving it.
- **Richer offline map (terrain + cycle routes)** — the OpenAndroMaps data you
  already download contains contour lines, signed cycle-route networks and
  mountain features; the render themes now draw them (no new assets, no
  re-download): contour lines (minor/medium/major, revealed as you zoom in),
  signed cycle routes (local→international, highlighted on the road), and named
  peaks / saddles / mountain passes. Applies to Dark/Light/B&W.

### Changed
- **Followed route is a dashed line of small arrows** — the route to follow is
  drawn as a dashed line whose every dash is a small arrow (a short shaft with a
  head no wider than the line), packed with a tiny gap. Custom-drawn in screen
  space, so the gap stays tight at any zoom and every arrow points in the actual
  travel direction (earlier approaches either spread out when you zoomed in or
  pointed backwards on half the route).
- **More sunlight readability** — the recorded track line is brighter (amber), and
  roads / streets are brighter in the Dark and Detailed (Elements) — Dark map
  themes (near-white road bodies over a dark casing) so they stay legible with the
  sun on the screen. (The map theme refreshes as tiles redraw — pan/zoom or
  restart to repaint already-cached tiles.)

### Fixed
- **Recorded distance no longer reads ~5% long from GPS jitter** — even with
  every fix passing the accuracy filter, summing the leg between *every*
  consecutive 1 Hz fix overcounted distance vs. a reference track (Komoot) with
  no spikes involved: plain positional noise adds spurious zig-zag length (the
  "coastline paradox") continuously while riding, not just when stationary.
  Distance is now integrated from the GPS chip's own reported (Doppler) speed
  over time rather than differenced from consecutive positions — Doppler
  velocity doesn't carry the position-fix noise that caused the overcount.
  Existing rides can be corrected with the new "Recalculate ride distances"
  action above.
- **GPS spikes no longer corrupt the track or the average** — occasional GPS
  "teleport" outliers (multipath reflections, worse in the evening) made the
  recorded track dart out and back, and — because the huge out/back legs are
  rejected for distance while time keeps running — dragged the average speed down
  with every spike. Such fixes are now rejected at the source (any that imply an
  impossible speed from the last good position), keeping the last good fix as the
  reference so the next real leg is measured across the gap. Cleaner track,
  correct distance and average.
- **Opening a GPX reuses the running app** — opening/sharing a `.gpx` from a file
  manager spawned a *second* instance of Cycle instead of handing the route to the
  one already running. The activity is now `singleTask`, so the intent goes to the
  existing instance (and you keep your current ride/map state).
- **Speed no longer sticks at 0 when the sensor sleeps** — a speed sensor that
  goes to sleep keeps reporting 0 while you're still moving; the display held that
  stale (green) 0 and never fell back to GPS. Now, when the BLE wheel reads ~0 but
  GPS clearly shows movement, the speed uses GPS (and shows the GPS colour). Paired
  sensors also reconnect persistently, so one that drops/sleeps re-links by itself
  when it wakes — no manual re-pair.
- **BLE sensors auto-reconnect reliably** — reconnect is now persistent
  (`autoConnect`): a paired sensor that was on standby at launch, or that drops
  out and comes back in range, re-links by itself instead of only getting one
  attempt at startup. Disconnects are also detected cleanly.
- **Losing the wheel-speed sensor falls back to GPS** — the speed display now
  forgets the BLE speed the moment that sensor disconnects, instead of holding
  the last value.
- **BLE speed/cadence no longer flicker to 0 (even at steady speed)** — a CSC
  sensor can notify *faster* than the wheel/crank turns, so several notifications
  in a row carry no new revolution even while riding; the value dropped to 0. The
  hold is now based on the **time since the last real revolution** (not a count of
  empty notifications), so speed/cadence hold steady while moving and only fall to
  0 once the wheel/crank has actually been stopped for a few seconds.
- **Map no longer blanks when the active map switches** — swapping the displayed
  map (e.g. once a position picks a more-local map) updated mapsforge's render
  model in place, which it rejects ("MapModel cannot be changed"), throwing during
  build and leaving the map blank. The map view is now keyed to the model so it
  recreates cleanly on a swap. This is the intermittent "map stuck / no location"
  on startup.
- **Location now appears on startup instead of the map staying stuck** — the
  raw GPS provider we use for accuracy needs sky view, so indoors / on a cold
  start it could take forever (or never) to lock, leaving no location dot and
  the map on its default centre. Startup now seeds the map with the last known
  position immediately, and if raw GPS can't get a fix after a few tries it
  falls back to the assisted (fused, wifi/cell) provider so a location still
  comes through; any GPS success switches back.
- **GPX export is now findable** — exported rides went to private internal
  storage (invisible to file managers); they now write to the app's external
  files dir under `exports/` (the same accessible root as the route-import
  `routes/` folder), and the "Saved …" path shows for 10 s.

- **Ride track no longer shows gray gaps when zoomed out** — the speed-coloured
  track is drawn as separate coloured segments over a gray base line. Noisy GPS
  speed split it into many very short segments; when the whole ride is fitted on
  screen those were only a few pixels long and didn't render, so the gray base
  showed through (they "appeared" only when you zoomed in). Segments are now
  merged by **length** so each is long enough to render at the fitted zoom (which
  also bounds their count and de-noises the colouring). Coincident points are
  also de-duplicated, and the renderer skips a failed marker instead of aborting
  the batch (vendored patch 4).

### Changed
- **Battery: map-follow deadband** — while following, the map now only
  re-centres once your location drifts ~45% of the way toward the nearest edge,
  instead of re-stamping/redrawing the tiles on every 1 Hz fix. The location dot
  still updates live (it drifts within the static map), so it saves a map redraw
  per second; the map jumps back to centre only as the dot nears the edge.
- **Live speed holds up under tree cover** — the GPS chip's reported speed
  regresses toward zero when the signal is weak (under canopy), so the
  speedometer read low while the distance-based average stayed correct. When a
  fix is inaccurate the live speed now falls back to the speed implied by actual
  movement over the last few seconds (a position window), so it no longer
  under-reports while you're moving; an accurate fix still uses the responsive
  chip value. A BLE wheel-speed sensor (with the wheel circumference set) remains
  the most accurate source and is still preferred when connected.

- **Map render themes** — roads now stay visible ~2 zoom levels further out when
  zooming out (lowered the `zoom-min` thresholds per road class), and paths,
  tracks and cycle lanes render as solid lines instead of dashed (railways stay
  dashed). Fixes roads appearing to fragment/disappear as you zoom out. Applies
  to all three schemes (Dark/Light/B&W).

## [0.1.0] - 2026-06-22

First tracked version. A phone-based bike computer (Android, iOS-ready) with an
always-on dark dashboard, offline maps, BLE sensors, ride recording and uploads.

### Added

- **Dashboard & map** — single always-on screen: full-screen offline vector map
  (Mapsforge) with the live location, recorded track and ride stats overlaid
  (speed, time, distance, avg, max) plus always-visible HR / cadence / power.
- **Offline maps** — full OpenAndroMaps Europe + Germany catalogue (~80 regions
  incl. Bavaria), streamed/resumable downloads to SD card or internal storage,
  per-region manage/delete. Auto-selects the map covering your location, with a
  manual picker; remembers the zoom level across launches.
- **Colour schemes** — Dark (true-black OLED), Light, and Black & white map,
  selectable in Settings.
- **BLE sensors** — pair heart-rate, speed/cadence and power sensors (standard
  GATT); GPS+BLE speed fusion; sensors auto-reconnect on launch.
- **Recording & rides** — record a ride (screen stays on), stored locally; Rides
  list + detail with the ride on the real map (track coloured by speed,
  red→violet), elevation profile, and stats incl. ascent, avg HR/cadence/power
  and battery used + drain rate (%/h). GPX export.
- **Follow a GPX route** — dashed guide line with a nav banner and ghost rider;
  open/share a `.gpx` into the app.
- **Upload** — Strava (official OAuth) and Komoot (unofficial) from a ride or
  Settings → Accounts.
- **Controls** — start/stop with the phone volume keys (Android) by default;
  optional on-screen button. Settings for units, wheel size and colour scheme.
- **Track direction** — the recorded track and followed route show travel
  direction as a dashed line with chevron arrowheads.

### Changed

- Map rotation is disabled — the map stays north-up.
- The recorded track is only drawn while a ride is recording.

### Fixed

- BLE cadence no longer flickers to 0 between sensor updates.
- Large region maps (multi-GB) download and render without running out of memory
  or freezing.

[Unreleased]: https://example.com/cycle/compare/v0.1.0...HEAD
[0.1.0]: https://example.com/cycle/releases/tag/v0.1.0
