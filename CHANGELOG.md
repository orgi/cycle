# Changelog

All notable changes to **Cycle** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Pre-1.0 (0.x) means the app is under active development and things may still change.

## [Unreleased]

### Changed

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
