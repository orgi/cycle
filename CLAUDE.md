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
* **GPS:** `geolocator`. **BLE sensors:** `flutter_blue_plus` using the standard
  Bluetooth SIG GATT profiles (HR `0x180D`, CSC `0x1816`, Power `0x1818`); modern Garmin
  dual-band sensors work over BLE with no special code. [M3]
* **Local DB:** `drift` (SQLite) for tracks/trackpoints. [M4]
* **GPX:** `gpx` package. **Keep-awake:** `wakelock_plus`.

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

* **M1 — Skeleton & always-on dashboard:** done. OLED-black dashboard (fixed non-scrolling
  layout) with live speed/avg/max/distance/time from GPS, start/stop + wakelock. Tests green.
* **M2 — Offline map + region download manager:** done. Mapsforge map screen (dark theme,
  live location marker) + OpenAndroMaps "Manage maps" downloader (catalogue, download with
  progress, delete). Bundled `monaco.map` demo. Host + emulator GUI tests green.
* **M3** BLE sensors · **M4** recording & track DB · **M5** follow-GPX · **M6** upload
  (self-hosted/Strava/Komoot) · **M7** physical buttons & polish — pending. Full plan:
  `~/.claude/plans/please-plan-an-implementation-zany-shannon.md`.

## Updating this file

This file shall be kept up-to-date automatically. Update the tech stack and milestone
progress sections as features land.
