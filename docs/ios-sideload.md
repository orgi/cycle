# Installing Cycle on an iPhone (free, no Mac)

How to get Cycle onto an iPhone **without a paid Apple Developer account and
without a Mac**, from this Linux machine. Verified target: iPhone 12 mini.

## How it works

| Step | Where | Who |
|---|---|---|
| Build an **unsigned** `.ipa` | GitHub Actions `macos-latest` runner (free for this public repo) | CI, automatic |
| Sign it with your **free Apple ID** and install over USB | Linux, [Impactor](https://github.com/khcrysalis/Impactor) | you, ~2 clicks |

iOS can't be compiled on Linux (it needs Xcode), so CI does the build. Signing
needs your Apple ID, so that happens locally. Neither step costs money.

### Free Apple ID limits (Apple's rules, not the tooling's)

* **The app expires after 7 days.** After that it won't launch until it's
  re-signed. **Your rides and maps are NOT lost.** Re-installing the same app
  over the top keeps its data, just like `adb install -r` on Android. Never
  delete the app from the iPhone to "fix" an expired install.
* At most **3** sideloaded apps at once, and **10 app IDs per 7 days**.
* No App Store / TestFlight. Those need the paid account (99 €/year), which also
  extends validity to one year.

## One-time setup

### 1. Linux: install Impactor

```bash
flatpak install flathub dev.khcrysalis.PlumeImpactor
```

It talks to the iPhone through `usbmuxd`, which most distros ship. Check with:

```bash
systemctl status usbmuxd   # or: ls /var/run/usbmuxd
# Debian/Ubuntu if missing: sudo apt install usbmuxd
```

### 2. iPhone: trust this computer

Plug the iPhone in over USB, unlock it, and tap **Trust** (then enter the passcode).

## Each install (first time and every ≤7 days)

### 3. Get the `.ipa`

1. GitHub → **Actions** → **Build** → **Run workflow**, then pick the branch
   (e.g. `iphone-pilot`). A push to `main` or a PR builds it automatically too.
2. When the run is green, download the **`ios-ipa-unsigned`** artifact (a zip)
   and unzip it. Inside is `cycle-<version>-unsigned.ipa`.

You only need a new `.ipa` when the code changes. For a plain 7-day refresh,
re-use the previous one.

### 4. Sign and install with Impactor

Install **before** touching Developer Mode: installing doesn't need it, and the
Developer Mode switch only appears on the iPhone after the first install.

Labels below are English / German. Impactor follows the desktop language.

1. **Sign in (once):** ⚙ gear icon (top right) → **Add Account** / *Account
   Hinzufügen* → Apple ID email + password → the 2FA code shown on the iPhone.
   Go back with the ‹ arrow (top right). A separate, throw-away Apple ID works
   just as well if you'd rather not use your main one.
2. **Pick the iPhone** in the dropdown at the top. It reads **No Device** until
   the phone is plugged in, unlocked and trusted.
3. **Add the `.ipa`.** There is no "add" button. Either drag the file into the
   window (**Drag & drop an IPA here** / *IPA per Drag & Drop hier ablegen*), or
   click the bottom-right button **Import .ipa / .tipa** / *Importiere eine
   .ipa / .tipa Datei*.
4. On the app screen that opens, click **Install** / *Installieren*. If it is
   greyed out, no device is selected in step 2.

The Cycle icon then appears on the home screen but won't open until step 5.

Impactor registers the device, creates the free certificate and profile, and
re-signs the app. It keeps the bundle ID stable across installs, which is what
keeps the database when you re-install.

### 5. iPhone: first run only

1. **Developer Mode** (iOS 16+): Settings → Privacy & Security → scroll to
   the very bottom (next to Lockdown Mode) → **Developer Mode** → On → restart
   → confirm. German: *Einstellungen → Datenschutz & Sicherheit → ganz unten,
   neben Blockierungsmodus → Entwicklermodus*. It is only listed once step 4
   has installed an app.
2. **Trust the developer**: Settings → General → **VPN & Device Management** →
   your Apple ID → **Trust**. German: *Allgemein → VPN & Geräteverwaltung →
   … vertrauen*.
3. Open Cycle. Allow **Location → While Using the App** and **Bluetooth**.

## Optional: refresh without a computer

Impactor can also install **SideStore**, which re-signs the sideloaded apps
from the phone itself over Wi-Fi, so the weekly refresh no longer needs USB.
It takes extra one-time setup (a pairing file plus a VPN/loopback app). Try it
once the plain USB route works.

## What differs from Android

* **Volume buttons start/stop a ride** (up = start, down = stop), as on
  Android, but through a workaround because iOS has no official API for it.
  While Cycle is open, the media volume is held at half; your own level comes
  back when you leave the app. If the buttons ever stop working (e.g. after an
  iOS update), turn off *Volume keys start/stop* in Settings and the on-screen
  Start/Stop button comes back.
* **Glove-friendly extras** in Settings → Controls (both off by default):
  *Hand over screen start/stop* (hold a hand over the top of the screen for
  2 s) and *Auto-start ride* (starts by itself once you ride above 8 km/h).
  *Vibrate on start/stop* (on by default) confirms every start (1 buzz), stop
  (2) and bike switch (3).
* **GPS** runs through one continuous Core Location request
  (`AppleLocationService`). It keeps recording with the screen off (iOS shows
  the blue location pill) and is released when the app is backgrounded with no
  ride, the same lifecycle gate as Android.
* **Not wired up on iOS yet:** opening/sharing a `.gpx` or backup *into* Cycle,
  sharing a backup out, the Strava OAuth redirect, the battery-used stat, and
  OruxMaps import. Their Android-native channels have no iOS counterpart, and
  the Dart side no-ops there.
* **Files**: the app's folder (the `routes/` folder for GPX routes to follow,
  backups, GPX exports) shows in the **Files** app under *On My iPhone →
  Cycle*. It's the counterpart of Android's external files dir, so put `.gpx`
  routes there. Downloaded maps live in the app's private storage, as on
  Android.

## Troubleshooting

* **No Developer Mode / *Entwicklermodus* entry after installing**: seen on the
  iPhone 12 mini with iOS 26.5. Reveal it over USB from Linux, then force-quit
  and reopen Settings:
  ```bash
  idevicedevmodectl reveal   # Debian/Ubuntu: apt install libimobiledevice-utils
  idevicedevmodectl list     # shows DeveloperMode enabled/disabled
  ```
* **Drag & drop into Impactor does nothing / the file isn't visible** (KDE or
  GNOME on Wayland): Impactor's UI toolkit doesn't accept dropped files under
  Wayland, and the Flatpak has no access to your files by default. Run it once
  like this:
  ```bash
  flatpak override --user --filesystem=~/Downloads:ro dev.khcrysalis.PlumeImpactor
  flatpak run --nosocket=wayland dev.khcrysalis.PlumeImpactor
  ```
* **"Untrusted Developer"** on launch: do step 5.2.
* **App won't open after a week**: it expired. Repeat step 4 with the same
  `.ipa`; your data is kept.
* **Impactor doesn't see the phone**: unlock it, re-plug it, re-tap Trust, and
  check that `usbmuxd` is running.
* **"Maximum number of apps"**: a free Apple ID allows 3 sideloaded apps.
  Remove one you don't need (not Cycle, or you'll lose its data).
