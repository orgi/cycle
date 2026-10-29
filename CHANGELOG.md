# Changelog

All notable changes to **Radl** (called Cycle before 0.4.0) are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Pre-1.0 (0.x) means the app is under active development and things may still change.

## [Unreleased]

## [0.11.0] - 2026-10-29

### Added
- Pass-through places (Settings → Controls → Start/stop places, edit a place, "Pass
  through"): for a point on the way — the end of your street, a crossing — instead of a
  place where you stay. A stop place (or both-way place) set to pass through stops the ride
  once you've ridden through it, without stopping there; waiting there doesn't stop it.
  Starting is as before: on leaving a start place, which already includes riding straight
  through one.

## [0.10.1] - 2026-10-29

### Fixed
- Riding back the way you came — to a dead end and back, an out-and-back, turning round
  after a missed turn — counted only the straight line from the start of that stretch of
  road to where you were, not the way there and back (1.5 km out and back read 450 m).
  Both ways count now. Turning round within about 30 m still isn't counted, so GPS noise
  along the road doesn't add distance. For rides recorded before: Settings → Data →
  "Recalculate ride distances" (on 830 real rides this changed only those with a
  turn-back, by up to 1.75 km).

## [0.10.0] - 2026-10-29

### Added
- Start/stop places (Settings → Controls): rides start when you leave a place and stop
  when you arrive at one — home, work, the café at the end of the loop. Each place is a
  start place, a stop place or both, with a radius of 25–200 m, and is added where you
  stand ("Add this place"). A ride stops only once you've been at the place for 20 seconds,
  so riding past doesn't end it, and a ride started inside a stop place isn't stopped
  there. Places stay on the phone (not synced).
- Keep screen on without a ride (Settings → Controls): the screen stays on while Radl is
  open, also before a ride starts — so the phone can wait on the handlebar for a ride to
  start by leaving a place, or by auto-start. It goes off once the phone hasn't moved for
  5–60 minutes (your choice), so a phone left lying around doesn't keep its screen and GPS
  on until the battery is empty. Off by default.
- Continue a stopped ride (Settings → Controls, on by default, 30 minutes): starting a ride
  by hand — button, volume key, hand over the screen — soon after stopping one, still at
  the same place (within 200 m), continues that ride instead of starting a new one. An
  accidental stop or a short break stays one ride. A notice then offers "New ride" in case
  it should have been a new one. Rides started by a place or by auto-start are always new.

### Changed
- With "Continue a stopped ride" on, a ride is saved to Apple Health once it can no longer
  be continued (when the time is up, or when the next ride starts) instead of right at the
  stop — a workout can't be extended afterwards, and Strava imports it right away.

### Fixed
- A ride resumed after a crash is unfinished again while it records, so a second crash
  during it is recovered at the next launch too (it used to keep its old stats).

## [0.9.0] - 2026-10-27

### Added
- The home screen's tiles can be arranged right on the map: long-press any tile, then drag
  it onto another to swap them, onto a row's "+" or a "+ row" line to move it, or onto the
  bin to remove it; tap a tile to choose what it shows. Each bike profile has its own
  layout (e.g. one for hiking), and it syncs with the bike. Bike settings → Home screen
  has "Edit" and "Reset to the standard tiles".
- New tiles: ELEV (current height above sea level), CLIMB (how far up this ride has
  gone), and two elevation profiles: the ride's, from its start until now, and the
  followed route's whole profile with where you are and the climb still ahead.
- A followed route's heights are read from its GPX file.

### Changed
- The ascent shown on a ride's details is smoothed and counted with a 5 m threshold,
  like the new live CLIMB, so GPS jitter no longer adds up to a too-high number. A ride's
  ascent can therefore read lower than before.

### Fixed
- Android: heights are above sea level, as on iOS and on maps. Android reports them above
  the WGS84 ellipsoid, about 48 m higher in Bavaria; the sea-level height now comes from
  the GPS chip itself. Rides recorded before keep their old heights.

## [0.8.0] - 2026-10-26

### Added
- Each bike profile now has its own settings: wheel circumference, auto-pause (on/off and
  the speed it pauses below) and auto-start (on/off and the speed it starts above — no
  longer fixed at 8 km/h, and it can be a walking speed, e.g. for a hiking profile). They
  switch with the bike, also when you change bikes during a ride, and sync with the bike
  between phones. Open them from Settings → Bikes → "Settings for …" (the active bike),
  or "Bike settings" in a bike's menu under Bike profiles, which also has the bike's
  sensor choice.

### Changed
- Wheel circumference, auto-pause and auto-start moved from Settings into the bike
  profiles. Your bikes keep the values you had until you change them for a bike; a new
  bike starts with a copy of the active bike's.
- "Recalculate ride distances" and "Clean spikes" use the auto-pause of the bike each
  ride was recorded on.

### Fixed
- A new wheel circumference now applies to a speed sensor that is already connected,
  not only after it reconnects.

## [0.7.1] - 2026-10-23

### Fixed
- No change you'd notice: fixes a code-check failure that stopped the 0.7.0 build, so 0.7.0
  was never installed. 0.7.1 is 0.7.0's route restore with that fix.

## [0.7.0] - 2026-10-23

### Added
- The route you're following is followed again after closing the app or restarting the
  phone, until you choose "Stop following". A route opened from another app at launch
  takes precedence, and a route deleted in the meantime isn't brought back.

## [0.6.0] - 2026-10-23

### Added
- Saved routes: every route you follow from a GPX file — opened from Komoot or another
  app, or imported from the routes folder — is kept, so you can follow it again later, also
  after closing the app or restarting the phone. "Saved routes…" in the follow-route menu
  lists them: tap one to follow it, rename or delete it (with undo), or delete them all.
  The same route imported twice is kept once.
- Saved routes sync with your other phones: new routes, renames and deletions. Importing a
  route again brings it back after it was deleted on another phone.
- Backups include the saved routes; importing a backup adds the ones the phone doesn't have.

## [0.5.5] - 2026-10-23

### Fixed
- iPhone: opening a GPX file in Radl from another app (e.g. Komoot's GPX export, or the
  Files app) showed "GoException: no routes for location: file:///…" and the file was not
  loaded. It now opens as on Android: a planned route is followed right away, and a GPX
  with recorded times asks whether to follow it or add it to your rides.

## [0.5.4] - 2026-10-19

### Fixed
- After a small or interrupted pinch-zoom, the map could stay shrunk into a corner of the
  screen, with the location dot drifting off it, until the app was restarted. A pinch that
  doesn't change the zoom level now snaps back, as does one cut short (a third finger, a
  system gesture).

## [0.5.3] - 2026-10-19

### Fixed
- The location dot now always shows the latest GPS position, also while standing still.
  Fixes the GPS rated as inaccurate (common when stopped) used to be thrown away entirely,
  so after e.g. a wrong turn the dot stayed where you had been. They still don't count
  towards the ride's distance or its saved track.
- The live speed no longer freezes on such fixes.
- The recorded track on the map no longer re-draws parts that were already drawn, and short
  out-and-back stretches are no longer smoothed away. The line is only ever extended now,
  and drawing it no longer gets slower the longer the ride goes on.
- The direction arrows along the recorded track stay in place as the ride grows.

## [0.5.2] - 2026-10-18

### Fixed
- On Android phones with the button navigation bar, the map credit "© OpenStreetMap
  contributors" was hidden behind the bar (0.5.1). It now sits just above the bar, with the
  ride stats moved up a little to make room.

## [0.5.1] - 2026-10-18

### Changed
- On iPhones without a home button, the map credit "© OpenStreetMap contributors" now sits in
  the free strip below the ride stats instead of above them. Elsewhere it stays above.

## [0.5.0] - 2026-10-17

### Added
- **Map credit "© OpenStreetMap contributors"** on the home map, on each ride's map and in
  Settings → About. All map data comes from OpenStreetMap, whose licence (ODbL) requires it;
  tapping it opens OpenStreetMap's copyright page.
- **Save rides to Apple Health (iPhone).** Settings → Apple Health → "Save rides to Apple
  Health" saves each finished ride as a cycling workout with route, distance and heart rate;
  a ride's screen also has a "Save to Apple Health" button for older rides. Strava can import
  them from Apple Health. Each ride is saved only once.

### Removed
- **Direct Strava upload.** Strava now charges for API access and limits apps to 10 riders
  without its approval, which doesn't fit a free app. On iPhone, rides reach Strava through
  Apple Health instead; on Android, export the ride as GPX and upload it on strava.com. A
  Strava login saved by an older version is deleted on the next launch.

### Changed
- **Maps now come straight from OpenAndroMaps' website.** Their terms don't allow apps to
  link to their map files, so the built-in region list is gone. Manage maps now opens their
  download page in the browser: pick a region, tap its install button for "Others", and
  confirm in Radl. The download then runs in Manage maps as before. Installed maps stay, and
  deleting one now asks first.

## [0.4.0] - 2026-10-17

### Changed
- **New name: Radl** (Bavarian for bicycle), with a new icon: a bike wheel that is also a
  speedometer. Android shows it as a modern adaptive icon, including the single-colour
  version for themed icons, and the recording notification now shows the wheel instead of a
  white blob. The update installs over the old app and keeps all rides and settings. Ride
  sync keeps using the "Cycle" folder on your server, so phones on older versions stay in
  sync.

## [0.3.3] - 2026-10-17

### Fixed
- iPhone: after unlocking the phone, a sensor could stay disconnected because releasing the
  connection at the lock and reconnecting on unlock ran into each other (new in 0.3.0).
- iPhone: the app no longer cancels and restarts a waiting sensor connection every 12–18
  seconds; iOS keeps waiting for the sensor on its own.
- iPhone: the Start/Stop button can be hidden again, while "Hand over screen start/stop" is
  on. It stays visible otherwise, so a ride can always be stopped. Since 0.3.0 removed the
  volume keys on iPhone, it couldn't be hidden at all.

## [0.3.2] - 2026-10-16

### Fixed
- A sensor whose connection dropped in the first second, while the app was still setting
  it up, was not reconnected automatically until the next retry about 30 seconds later
  (new in 0.3.0).

## [0.3.1] - 2026-10-16

Installed on one phone only, and committed together with 0.3.2, so it has no tag of its own;
both links compare 0.3.0 with 0.3.2.

### Fixed
- Coming back to the app could connect a sensor twice at once (new in 0.3.0), which kept a
  second Bluetooth connection open and set up its readings twice.

## [0.3.0] - 2026-10-16

### Changed
- **Licence: GPL-3.0-or-later** (was GPL-2.0, which couldn't legally be combined with the
  LGPL-3.0 map library or the Bluetooth library). An additional permission allows
  distribution through app stores; see `NOTICE.md`.
- **New Bluetooth library** for heart-rate, speed, cadence and power sensors (universal_ble
  instead of flutter_blue_plus, whose new licence ruled out open-source distribution).
  Sensors connect the same way as before: directly by their saved ID, never by scanning.
- **Detailed map styles now come from mapsforge.** "Detailed (Elements)" and its dark
  variant were the OpenAndroMaps Elements theme, whose licence doesn't allow it in an app
  store release. They are replaced by **Detailed** and **Detailed — Dark**, the map styles
  that ship with the mapsforge map library (POI symbols, area patterns, more labels). If you
  had picked an Elements style, you get the matching new one automatically.

### Removed
- **Komoot upload.** It signed in with your Komoot password through Komoot's unofficial,
  private API, which breaks Komoot's terms and isn't allowed in the app stores. A Komoot
  login saved by an older version is deleted from the phone on the next launch. To get a
  ride into Komoot, export it as GPX from the ride screen and import it there. Strava upload
  is unchanged.
- **Volume-button start/stop on iPhone.** iOS has no official way to use the volume
  buttons, and the workaround (holding the media volume at half and watching it change)
  breaks App Store rule 2.5.9. On iPhone, start and stop with the on-screen button (now
  always shown there), the hand-over-screen gesture or auto-start. Android keeps volume-key
  control.

## [0.2.0] - 2026-10-15

Everything since 0.1.0. These changes were installed as builds `0.1.0+2` … `0.1.0+2048`:
they added features but only the build number went up, which broke semantic versioning.
0.2.0 is the first version number that reflects them; from here on every installed build
carries the version its changes call for (see CLAUDE.md → Versioning).

### Added
- **Battery runtime test** (Settings → Data → Battery runtime test): simulates a ride until the
  battery runs out, so you learn how long the phone really lasts on the bike. The map moves
  on a zigzag through your area (staying on your installed map, always into fresh map like on a
  ride), the track is drawn and every point is saved like on a ride (to a scratch file that's
  deleted afterwards), the real GPS stays on and the screen stays on. Time and
  battery level are saved every minute, so the result survives the phone switching itself off.
  The next time you open Cycle it tells you how long the phone lasted, with the average drain
  per hour. Tests are kept separately and never appear among your rides. A real ride can't be
  started while a test runs. Charging to 100 % in one go afterwards also recalibrates the
  battery display.
  During the test the map's TIME box shows how long the test has been running (labelled TEST).
  DIST, AVG and MAX count as on a ride, and the simulated speed varies between 25 and 35 km/h.
- **"Battery used" per ride on iPhone**, like on Android. iOS only reports the battery level in
  5 % steps (since iOS 17), so on short rides it may read 0 %. It's meaningful on longer rides.
- **Ride sync across phones, Android ⇄ iPhone (Settings → Data → Sync).** Rides, edits (name,
  bike, cleaned/recalculated tracks), deletions and bike names are kept in step through a
  folder `Cycle` on **your own server**: self-hosted **Nextcloud** (one-tap "Log in with
  Nextcloud", which creates a revocable app password) or any WebDAV storage (e.g. Koofr).
  No Cycle account and no cloud of ours.
  - **Works with phones that are usually offline.** Everything is saved on the phone first;
    sync catches up whenever the server can be reached: on app start, when the phone joins a
    network (e.g. home Wi-Fi), when the app comes back to the front, after a ride, and with
    **Sync now**. Never during a ride, and only while the app is open.
  - **Servers only reachable at home are fine.** Up to two addresses (e.g. the LAN address,
    then the public one) are tried in order with a short timeout; when neither answers, the
    status just says "not reachable" and it tries again later. Plain `http://` can be allowed
    for a home server, and a self-signed certificate can be trusted once by its fingerprint.
  - **Conflicts resolve themselves without losing edits.** Each ride's name, bike, track and
    deleted state are versioned separately, so renaming a ride on one phone and changing its
    bike on another keeps both. Only the same detail changed on two phones before they synced
    keeps the newer change. An edit made after a deletion keeps the ride.
  - **The Nextcloud login dialog remembers what you typed.** A mistyped address or a missing
    "Allow http" no longer means typing it all again: problems are shown inside the dialog
    (with the "Allow unencrypted http://" switch right there for an `http://` address), and
    the next attempt starts with the address you typed last time. Error messages also appear
    at once instead of waiting behind the "Approve Cycle in the browser" hint.
- **Sensors sync across your phones, with their bikes.** The list of your sensors and which bike
  uses which sensor now travel with sync. A sensor is recognised on every phone by its name
  (e.g. "HRM-Pro:123456"), because iPhones give each sensor a different Bluetooth id on every
  phone.
  - **Android phones** link a sensor another Android phone paired by themselves, without a scan.
  - **iPhones** list sensors from your other phones under Sensors → "On your other phones". Tap
    scan with the sensor awake nearby (wear the strap, spin the crank) and it links by itself,
    already on the right bikes.
  - Removing a sensor now removes it from all your phones (you're asked first). The button on
    the Sensors screen is now called **Remove**.
- **Recently deleted (Settings → Data).** Deleting a ride now moves it to a trash for 30 days
  (adjustable) where it can be restored, also on the other phones, instead of erasing it at
  once. Deleting from the ride list offers **Undo**.
- **Automatic safety backups.** A full backup is taken before the database is upgraded for this
  version, before the first sync, and (at most once a day) before any sync that would remove or
  replace rides on the phone. They appear under Backup & restore. The automatic daily ones are
  removed after the same 30 days; the others are kept until you delete them.
- **Start/stop with gloves on.** Three new ways to start or stop a ride without touching the screen:
  - **Volume buttons on iPhone** (up = start, down = stop), like on Android. iOS has no official
    way to read them, so Cycle watches the volume level and resets it after each press. While
    Cycle is open the media volume stays at half; your own level comes back when you leave the
    app. Only while Cycle is open, like on Android. The Start/Stop button is now hidden by
    default on iPhone too; turn off "Volume keys start/stop" in Settings to get it back.
  - **Hand over the screen** (iPhone, Settings → Controls, off by default): hold a hand over the
    top of the screen for 2 seconds to start or stop a ride. A brief cover does nothing. The
    screen goes dark while covered.
  - **Auto-start** (Settings → Controls, off by default): a ride starts by itself once you ride
    faster than 8 km/h for 5 seconds. Stopping stays manual. After a ride ends it only re-arms
    once you've stood still for a minute, so it doesn't instantly restart the ride you just
    stopped.
  - **Vibration confirms it** (Settings → Controls, on by default): 1 buzz = ride started,
    2 = stopped, 3 = bike switched (volume up during a ride), whatever triggered it. With the
    hand over the screen, the buzz comes the moment the 2 seconds are reached, while the screen
    is still dark, so you know you can take your hand away.
- **iPhone support (sideload pilot).** CI now builds an unsigned `.ipa` on every run (artifact
  `ios-ipa-unsigned`), which can be signed with a free Apple ID and installed from Linux with
  Impactor. No Mac or paid developer account needed. Step-by-step guide:
  `docs/ios-sideload.md`.
  - GPS on iOS uses one continuous Core Location request (cycling-tuned, never auto-paused),
    not the one-shot polling fallback. It keeps recording with the screen off and is released
    when the app is backgrounded with no ride, the same lifecycle gate as on Android.
  - The Start/Stop button is always shown on iOS (apps can't use the volume keys there), and
    the Android-only volume-key settings are hidden.
  - The app's folder (`routes/`, backups, GPX exports) appears in the iOS Files app.

### Fixed
- **Every bike showed up twice after syncing.** A bike created on each phone separately (e.g.
  "Road" on the A33 and "Road" on the iPhone) counted as two different bikes. Bikes with the same
  name (ignoring upper/lower case and spaces) are now merged into one on every phone, with all
  their rides, their colour and the active-bike choice moved over; each phone keeps its own
  sensor choice for the bike. Adding or renaming a bike to a name another bike already has is
  now refused, since sync would merge the two.
- **Cycle could not open its ride database after switching between builds** ("SQL logic error
  … ALTER TABLE "tracks" ADD COLUMN "name_clock""). Installing an older build over a sync build
  and then a sync build again made the database upgrade try to add columns that were already
  there, so the app stopped at startup. The upgrade now only adds what's missing, so any
  order of installs works. No rides were affected (the failed step changed nothing, and a
  backup is taken before every upgrade).
- **iPhone: Bluetooth sensors weren't released when the app went to the background.** iOS
  suspends a backgrounded app within about 2 seconds, so the 3-second delay before letting go
  of the sensors never ran. Pending sensor connections then stayed registered until iOS
  happened to wake Cycle again, sometimes minutes or hours later. On iPhone they're now
  released immediately. (The GPS was already released correctly, confirmed in the device log.)
- **Restoring a backup lost the bike and sensor details.** Imported rides came in without their
  bike profile and without the per-point "speed from sensor" flag. Both are kept now. A ride that
  is in Recently deleted is no longer brought back by importing an older backup.
- **CI never got past `flutter analyze`.** The analyzer also linted the vendored
  `third_party/mapsforge_flutter` copy and failed on upstream's own warnings, so the Android
  and iOS CI builds were always skipped. Vendored code is now excluded from analysis.
- **Stale sensor values after a sensor disconnects.** When a sensor's link dropped (heart-rate
  strap taken off, sensor out of range or asleep), its last value stayed on the dashboard
  indefinitely — and was **recorded onto every point of the next ride**, so a ride without the
  strap got the old heart rate as its average. Cadence and power were affected the same way.
  The speed tile could also stay "from sensor" green with no speed sensor connected: a cadence
  sensor's notifications kept re-broadcasting the departed speed sensor's last wheel speed,
  which the speed fusion took as a fresh reading. Sensor values now live only as long as their
  sensor's link; on disconnect the tile falls back to "—" and nothing is recorded for it. Rides
  recorded before this fix keep whatever values they were given.
- **Bluetooth drain while the app sits open in standby.** Paired sensors kept a pending
  connection registration for as long as the app was alive, so a phone left in standby over a
  weekend with Cycle open still had the Bluetooth controller trying to reach sensors that
  weren't there — measured on a Galaxy A33 as ~169 mAh (about 3% of the battery) blamed on
  Cycle, almost all of it with the screen off, with six GATT client registrations held open.
  Sensor links are now released when the app is backgrounded with no ride running, and
  restored when it returns to the foreground (after a 3-second grace period, so flicking to
  another app and back changes nothing). A ride recording in the background keeps its sensors,
  exactly like the GPS gate, and restoring uses the existing direct-connect path — still no
  scanning. (Connection attempts already in flight run to their ~10s timeout, so the last
  registrations clear up to a minute after the app is backgrounded.)
- **Battery drain with no ride running.** The GPS receiver was kept running continuously
  from app launch until Android killed the process — including after a ride was stopped and
  while the app sat in the background with the screen off. That drain is invisible to the
  per-ride battery stat (which is only sampled between Start and Stop), which is why
  Android's per-app battery usage read noticeably higher than the recorded rides accounted
  for. The GPS request is now held only while the app is in the foreground **or** a ride is
  recording; a backgrounded recording ride is unaffected and keeps exactly the same single,
  continuously-held request as before.
- **Keep-screen-on released out from under a map download.** Keep-awake was a single global
  flag with two owners, so stopping a ride while a region download was in flight let the
  screen sleep — the OS then suspended the app and the download dropped (it resumed from its
  `.part` file on retry). Keep-awake is now reference-counted per owner and stays on until
  the last owner releases it.
- **Sensors auto-connect on launch again (direct connect).** After the switch to passive
  reconnection, a paired sensor that was present and advertising (e.g. a worn HR strap)
  often would not link on launch — passive Android `autoConnect` frequently never connects a
  present sensor. The app now does a one-shot **direct connect** per sensor (the same path
  the manual "tap to reconnect" uses, which worked), which links a present sensor in a couple
  of seconds; it still doesn't scan, so it doesn't disturb the GPS. Absent sensors fall back
  to passive autoConnect. Verified on-device: a worn HR sensor now connects ~2s after launch
  with no tap.
- **GPS now uses a continuous native location request (real fix, no more toggling).** The
  GPS was read by polling one-shot position requests, which cold-restarted the receiver on
  every poll — the status-bar GPS icon toggled on/off and, on the Galaxy A33, often never
  got a fix at all. Android now holds a single continuous native `LocationManager` request
  (the same approach OruxMaps uses), so the GPS keeps its lock. (geolocator's polling and
  its position-stream both proved unable to hold the receiver on this hardware.)
- **GPS fix regression from BLE scanning.** Sensor reconnection had been changed to run an
  app-level active BLE scan loop (an ~8-second scan every minute while a paired sensor was
  missing — i.e. the whole ride, on a bike without that sensor). On phones with a combined
  Wi-Fi/BT/GPS radio (e.g. Galaxy A33) that scanning competed with the GPS receiver and
  degraded/prevented the fix. Reconnection is back to passive Android `autoConnect` (no
  app scanning), so the GPS is no longer starved. GPS acquisition also now starts at app
  launch (ahead of the UI) for a faster first fix.
  - Trade-off: reconnecting a sensor that went idle mid-ride again relies on the OS, which
    can be slower — to be revisited with an approach that doesn't scan during a ride.
- **BLE sensor reconnection.** Reconnecting a paired sensor (on app launch or after a
  mid-ride drop) previously relied entirely on Android's native `autoConnect=true` GATT
  mode with no app-level retry, timeout, or fallback — on real devices with 2-3 sensors
  paired at once this was wildly non-deterministic (one sensor reconnecting instantly,
  another sitting for 20+ minutes with no error and no indication anything was stuck).
  `BleSensorService` now runs its own scan-and-connect retry loop: a short targeted scan
  (`withRemoteIds`) for whichever paired sensors aren't yet linked, connecting the moment
  one is seen, retrying on a backoff (10s → 20s → 40s → 60s) if it isn't found, with the
  passive `autoConnect=true` link kept as a low-cost backstop between rounds.

### Fixed
- **Tap-to-reconnect no longer mixes up speed and cadence.** A speed sensor and a cadence
  sensor are the same Bluetooth type, so tapping SPEED and tapping CAD both reconnected both
  of them. The taps now target the right one, distinguished by the sensor's name
  (SPD/SPEED vs CAD/RPM/CADENCE).

### Added
- **Sensors keep trying to connect for a few minutes.** After app start — and again when a
  ride starts — the app re-tries connecting any not-yet-linked sensor every 30s for ~5
  minutes (a direct connect, no scanning, so it doesn't affect GPS), then stops once all are
  connected. So a sensor that wasn't ready at launch (just mounted on the bike / waking up)
  links on its own without you tapping.
- **Tap a stat to reconnect its sensor.** Tapping the SPEED / HR / cadence / power stat on
  the home screen triggers a quick one-shot manual reconnect of that sensor (a direct
  connect, no background scanning — so it doesn't disturb the GPS), for when a paired sensor
  hasn't auto-linked yet. The **SPEED** stat reconnects the BLE speed sensor (which has no
  tile of its own — its data feeds the speed reading), and reconnect also works for a sensor
  whose type the app hasn't learned yet (a flaky one that never linked cleanly). The Sensors
  screen also gets a per-sensor **Reconnect** button (by name), for unambiguous control.
- **Per-bike sensor selection.** Each bike profile can now be restricted to a subset of
  paired sensors (Settings → Bikes → Bike profiles → ⋮ → "Sensors for this bike") — e.g. a
  second bike with no cadence/speed sensor won't have the app endlessly retry connecting
  ones that only exist on another bike. Left unconfigured (the default), a profile keeps
  today's behaviour of pursuing every paired sensor. Switching the active bike disconnects
  now out-of-scope sensors and starts pursuing newly in-scope ones automatically. The home
  screen's HR/cadence/power tiles are shown based purely on "paired and selected for this
  bike", independent of live connection state — a sensor that's temporarily disconnected or
  reconnecting keeps its tile instead of disappearing.
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
  permission required. If bulk import still can't reach the database (some devices block it
  even with the permission granted), a "Pick database file" button opens the system file
  picker so you can import a copy you've moved somewhere ordinary yourself (e.g. via a PC/USB
  connection). Either way, already-imported rides are skipped, so re-importing is safe.
- **Remove duplicate rides** (Settings → Data) — a one-tap maintenance action that removes
  rides sharing the exact same start time as another ride, keeping the first-recorded copy.
  For duplicates left behind by an OruxMaps import that ran twice at once (see "Fixed" below).
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
- **OruxMaps bulk import no longer silently misses newer rides, and no longer
  double-imports on a re-tap** — a real multi-year ride history (hundreds of
  tracks/hundreds of thousands of points) made the import commit to disk on
  every single point instead of batching, taking well over an hour on a real
  device — easily mistaken for "it silently stopped partway" (the actual
  cause of newer, e.g. 2025/2026, rides appearing to be missing) when it was
  simply still running. Now batches each ride's points into one transaction,
  cutting a real-device import from 60+ minutes to a few minutes. Also
  guarded against a second import starting while one is still running (which
  otherwise imported the overlapping rides twice) — the import screen now
  shows a progress state and disables its buttons while busy. See "Remove
  duplicate rides" above for cleaning up rides a pre-fix import already
  duplicated. Also fixed a related bug in the manual file-picker path where
  an 80+ MB database sent as a single method-channel argument silently
  truncated to a partial copy on a real device — it's now streamed to a
  local file instead.
- **OruxMaps import now actually brings in heart rate and cadence** —
  OruxMaps packs those into a binary blob the importer wasn't reading at
  all (it only looked for named columns, which don't exist for these on a
  real export), so every previous import silently added zero sensor data
  even though the source had it. Re-running the import (Settings →
  "Import from OruxMaps") after updating backfills heart rate/cadence onto
  rides you already imported, not just new ones — you don't need to
  re-import from scratch.
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

[Unreleased]: https://github.com/orgi/cycle/compare/v0.11.0...HEAD
[0.11.0]: https://github.com/orgi/cycle/compare/v0.10.1...v0.11.0
[0.10.1]: https://github.com/orgi/cycle/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/orgi/cycle/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/orgi/cycle/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/orgi/cycle/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/orgi/cycle/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/orgi/cycle/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/orgi/cycle/compare/v0.5.5...v0.6.0
[0.5.5]: https://github.com/orgi/cycle/compare/v0.5.4...v0.5.5
[0.5.4]: https://github.com/orgi/cycle/compare/v0.5.3...v0.5.4
[0.5.3]: https://github.com/orgi/cycle/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/orgi/cycle/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/orgi/cycle/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/orgi/cycle/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/orgi/cycle/compare/v0.3.3...v0.4.0
[0.3.3]: https://github.com/orgi/cycle/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/orgi/cycle/compare/v0.3.0...v0.3.2
[0.3.1]: https://github.com/orgi/cycle/compare/v0.3.0...v0.3.2
[0.3.0]: https://github.com/orgi/cycle/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/orgi/cycle/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/orgi/cycle/releases/tag/v0.1.0
