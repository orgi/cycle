import AVFoundation
import AudioToolbox
import Flutter
import MediaPlayer
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var hardwareButtons: HardwareButtons?
  private var hapticsChannel: FlutterMethodChannel?
  private var networkEvents: NetworkEvents?
  private var oauthChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    hardwareButtons = HardwareButtons(messenger: messenger)

    // Start/stop confirmation buzzes (`HapticsService` in Dart): `vibrate(n)` =
    // n distinct pulses, so start (1) / stop (2) / bike switch (3) can be told
    // apart by feel. The classic system vibrate is the strongest buzz an app
    // can trigger — a Taptic "impact" is too subtle to feel through a handlebar
    // mount — and its length is fixed (~0.4 s), so pulses are spaced 0.6 s.
    let haptics = FlutterMethodChannel(name: "cycle/haptics", binaryMessenger: messenger)
    haptics.setMethodCallHandler { call, result in
      guard call.method == "vibrate" else { return result(FlutterMethodNotImplemented) }
      let count = min(max((call.arguments as? Int) ?? 1, 1), 5)
      for i in 0..<count {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 * Double(i)) {
          AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
      }
      result(nil)
    }
    hapticsChannel = haptics

    // Ride sync: "the phone gained a network" events (see NetworkEvents).
    networkEvents = NetworkEvents(messenger: messenger)

    // `cycle/oauth` — iOS half of the Android channel: `openUrl` opens a page
    // in the browser (Nextcloud login). Capturing a `cycle://` redirect back
    // (Strava) isn't wired on iOS, so `consumeRedirect` reports none.
    let oauth = FlutterMethodChannel(name: "cycle/oauth", binaryMessenger: messenger)
    oauth.setMethodCallHandler { call, result in
      switch call.method {
      case "openUrl":
        guard let s = call.arguments as? String, let url = URL(string: s) else {
          return result(FlutterError(code: "bad_args", message: "url required", details: nil))
        }
        UIApplication.shared.open(url) { ok in
          ok ? result(nil)
            : result(FlutterError(code: "open_failed", message: "cannot open \(s)", details: nil))
        }
      case "consumeRedirect":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    oauthChannel = oauth
  }
}

/// `cycle/network` EventChannel — iOS half of `MainActivity.kt`'s network
/// callback: emits an event whenever a usable network path appears or the
/// interface changes (e.g. Wi-Fi at home), the cue for ride sync to check
/// whether its server is reachable. Monitors only while Dart listens and the
/// app is active — sync runs only while the app is open.
final class NetworkEvents: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var monitor: NWPathMonitor?
  private var isActive = UIApplication.shared.applicationState == .active
  private var lastSignature: String?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    FlutterEventChannel(name: "cycle/network", binaryMessenger: messenger)
      .setStreamHandler(self)
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(didBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(willResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    apply()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    apply()
    return nil
  }

  @objc private func didBecomeActive() {
    isActive = true
    apply()
  }

  @objc private func willResignActive() {
    isActive = false
    apply()
  }

  private func apply() {
    let wanted = sink != nil && isActive
    if wanted && monitor == nil {
      let m = NWPathMonitor()
      m.pathUpdateHandler = { [weak self] path in
        guard path.status == .satisfied else {
          DispatchQueue.main.async { self?.lastSignature = nil }
          return
        }
        let signature = path.availableInterfaces.map { $0.name }.joined(separator: ",")
        DispatchQueue.main.async {
          guard let self = self, signature != self.lastSignature else { return }
          self.lastSignature = signature
          self.sink?("available")
        }
      }
      m.start(queue: DispatchQueue(label: "cycle.network"))
      monitor = m
    } else if !wanted, let m = monitor {
      m.cancel()
      monitor = nil
      lastSignature = nil
    }
  }
}

/// iOS side of the `cycle/hardware_buttons` channel — the counterpart of
/// `MainActivity.kt`'s volume-key interception, same protocol:
///   Dart → native: `setEnabled(Bool)` (volume keys), `setProximityEnabled(Bool)`
///   native → Dart: `onVolumeKey("up"|"down")`, `onProximity(Bool covered)`
///
/// **Volume keys.** iOS has no public API to intercept them (the official
/// `AVCaptureEventInteraction` only works with a running camera session), so
/// this uses the long-standing workaround: keep an audio session active, watch
/// `AVAudioSession.outputVolume`, and after each press put the volume back to a
/// fixed middle level so the next press in either direction is visible again. A
/// tiny off-screen `MPVolumeView` both lets us set the volume and suppresses the
/// system volume HUD. While enabled, the media volume is therefore held at that
/// level; the rider's own volume is restored whenever Cycle leaves the
/// foreground. Foreground only, like Android: nothing is pinned or reported
/// while backgrounded, so a backgrounded ride can't be stopped from a pocket.
///
/// **Proximity.** `UIDevice.isProximityMonitoringEnabled` reports when the top
/// of the screen is covered (and iOS blanks the screen meanwhile). Native only
/// forwards covered/uncovered; the "hold for 2 s" rule lives in Dart
/// (`ProximityHoldDetector`) where it is unit-tested.
final class HardwareButtons: NSObject {
  private let channel: FlutterMethodChannel

  private var volumeWanted = false
  private var proximityWanted = false
  private var isActive = UIApplication.shared.applicationState == .active

  // Volume-key state.
  private static let pinnedVolume: Float = 0.5
  private var volumeObservation: NSKeyValueObservation?
  private var volumeView: MPVolumeView?
  private var savedVolume: Float?
  /// Last volume change of any kind. A held key repeats every ~0.1-0.2 s, so
  /// ignoring changes that arrive within this window of the previous one makes
  /// a long press count once (Android likewise ignores key-repeat).
  private var lastChange = Date.distantPast
  private static let repeatWindow: TimeInterval = 0.6

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "cycle/hardware_buttons", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "setEnabled":
        self.volumeWanted = (call.arguments as? Bool) ?? false
        self.apply()
        result(nil)
      case "setProximityEnabled":
        self.proximityWanted = (call.arguments as? Bool) ?? false
        self.apply()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(didBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(willResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(proximityChanged),
      name: UIDevice.proximityStateDidChangeNotification, object: nil)
  }

  @objc private func didBecomeActive() {
    isActive = true
    apply()
  }

  @objc private func willResignActive() {
    isActive = false
    apply()
  }

  private func apply() {
    if volumeWanted && isActive { attachVolume() } else { detachVolume() }
    let proximityOn = proximityWanted && isActive
    if UIDevice.current.isProximityMonitoringEnabled != proximityOn {
      UIDevice.current.isProximityMonitoringEnabled = proximityOn
      // Turning monitoring off while covered never sends "uncovered".
      if !proximityOn { channel.invokeMethod("onProximity", arguments: false) }
    }
  }

  // MARK: Proximity

  @objc private func proximityChanged() {
    guard UIDevice.current.isProximityMonitoringEnabled else { return }
    channel.invokeMethod("onProximity", arguments: UIDevice.current.proximityState)
  }

  // MARK: Volume keys

  private func attachVolume() {
    guard volumeObservation == nil else { return }
    let session = AVAudioSession.sharedInstance()
    // Ambient + mixWithOthers: never interrupts the rider's music/podcast.
    try? session.setCategory(.ambient, options: [.mixWithOthers])
    try? session.setActive(true)
    installVolumeView()
    savedVolume = session.outputVolume
    lastChange = Date()
    setSystemVolume(Self.pinnedVolume)
    volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
      guard let volume = change.newValue else { return }
      DispatchQueue.main.async { self?.volumeChanged(to: volume) }
    }
  }

  private func detachVolume() {
    guard volumeObservation != nil else { return }
    volumeObservation?.invalidate()
    volumeObservation = nil
    // Restore the rider's own volume through the view, then remove it once
    // the restore has had a moment to apply.
    let view = volumeView
    volumeView = nil
    if let saved = savedVolume { setSystemVolume(saved, via: view) }
    savedVolume = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      view?.removeFromSuperview()
      try? AVAudioSession.sharedInstance().setActive(
        false, options: .notifyOthersOnDeactivation)
    }
  }

  private func volumeChanged(to volume: Float) {
    guard volumeObservation != nil else { return }
    // Our own reset back to the pinned level.
    if abs(volume - Self.pinnedVolume) < 0.01 { return }
    let now = Date()
    let isRepeat = now.timeIntervalSince(lastChange) < Self.repeatWindow
    lastChange = now
    if !isRepeat {
      channel.invokeMethod("onVolumeKey", arguments: volume > Self.pinnedVolume ? "up" : "down")
    }
    setSystemVolume(Self.pinnedVolume)
  }

  private func installVolumeView() {
    guard volumeView == nil, let window = keyWindow() else { return }
    // Must be in the view hierarchy and not hidden to suppress the system HUD;
    // off-screen and near-transparent keeps it invisible.
    let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
    view.alpha = 0.01
    view.isUserInteractionEnabled = false
    window.addSubview(view)
    volumeView = view
  }

  private func setSystemVolume(_ volume: Float, via view: MPVolumeView? = nil) {
    // The slider is created lazily by MPVolumeView; set it shortly after so it
    // exists and the change is applied.
    let target = view ?? volumeView
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      guard let slider = target?.subviews.compactMap({ $0 as? UISlider }).first else { return }
      slider.value = volume
    }
  }

  private func keyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    return windows.first { $0.isKeyWindow } ?? windows.first
  }
}
