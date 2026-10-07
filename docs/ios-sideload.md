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

1. Start Impactor. Sign in with your Apple ID (a 2FA code is requested the first
   time). A separate, throw-away Apple ID works just as well if you'd rather not
   use your main one.
2. Select the connected iPhone, drop the `.ipa` in, and install.

Impactor registers the device, creates the free certificate and profile, and
re-signs the app. It keeps the bundle ID stable across installs, which is what
keeps the database when you re-install.

### 5. iPhone: first run only

1. **Developer Mode** (iOS 16+): Settings → Privacy & Security → **Developer
   Mode** → On → restart → confirm. The switch only appears after the first
   developer-signed install, so do step 4 first.
2. **Trust the developer**: Settings → General → **VPN & Device Management** →
   your Apple ID → **Trust**.
3. Open Cycle. Allow **Location → While Using the App** and **Bluetooth**.

## Optional: refresh without a computer

Impactor can also install **SideStore**, which re-signs the sideloaded apps
from the phone itself over Wi-Fi, so the weekly refresh no longer needs USB.
It takes extra one-time setup (a pairing file plus a VPN/loopback app). Try it
once the plain USB route works.

## What differs from Android

* **Start/Stop is the on-screen button.** iOS gives apps no access to the
  volume keys, so the button is always shown and the volume-key settings are
  hidden.
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

* **"Untrusted Developer"** on launch: do step 5.2.
* **App won't open after a week**: it expired. Repeat step 4 with the same
  `.ipa`; your data is kept.
* **Impactor doesn't see the phone**: unlock it, re-plug it, re-tap Trust, and
  check that `usbmuxd` is running.
* **"Maximum number of apps"**: a free Apple ID allows 3 sideloaded apps.
  Remove one you don't need (not Cycle, or you'll lose its data).
