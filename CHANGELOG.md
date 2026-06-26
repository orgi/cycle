# Changelog

All notable changes to **Cycle** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Pre-1.0 (0.x) means the app is under active development and things may still change.

## [Unreleased]

### Added
- **Richer offline map (terrain + cycle routes)** — the OpenAndroMaps data you
  already download contains contour lines, signed cycle-route networks and
  mountain features; the render themes now draw them (no new assets, no
  re-download): contour lines (minor/medium/major, revealed as you zoom in),
  signed cycle routes (local→international, highlighted on the road), and named
  peaks / saddles / mountain passes. Applies to Dark/Light/B&W.

### Fixed
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
