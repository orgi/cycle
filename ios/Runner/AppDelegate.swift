import AudioToolbox
import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var hardwareButtons: HardwareButtons?
  private var hapticsChannel: FlutterMethodChannel?
  private var batteryChannel: FlutterMethodChannel?
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IncomingMapLinks") {
      IncomingMapLinks.register(with: registrar)
    }

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

    // Battery level for the per-ride "battery used" stat (`NativeBatteryService`
    // in Dart, sampled at ride start/stop). Whole percent like Android; nil
    // when iOS can't tell (simulator, unknown state).
    let battery = FlutterMethodChannel(name: "cycle/battery", binaryMessenger: messenger)
    battery.setMethodCallHandler { call, result in
      guard call.method == "getLevel" else { return result(FlutterMethodNotImplemented) }
      UIDevice.current.isBatteryMonitoringEnabled = true
      let level = UIDevice.current.batteryLevel
      result(level < 0 ? nil : Int((level * 100).rounded()))
    }
    batteryChannel = battery

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
/// `MainActivity.kt`, same protocol. iOS only implements the proximity half:
///   Dart → native: `setProximityEnabled(Bool)`
///   native → Dart: `onProximity(Bool covered)`
/// Volume-key start/stop is Android-only. iOS has no public API to intercept
/// the volume keys, and the workaround (pinning the volume via a hidden
/// `MPVolumeView` and watching `outputVolume`) breaks App Store guideline
/// 2.5.9, so it was removed. Dart doesn't send `setEnabled` on iOS
/// (`volumeKeysSupported` is false).
///
/// **Proximity.** `UIDevice.isProximityMonitoringEnabled` reports when the top
/// of the screen is covered (and iOS blanks the screen meanwhile). Native only
/// forwards covered/uncovered; the "hold for 2 s" rule lives in Dart
/// (`ProximityHoldDetector`) where it is unit-tested. Foreground only.
final class HardwareButtons: NSObject {
  private let channel: FlutterMethodChannel

  private var proximityWanted = false
  private var isActive = UIApplication.shared.applicationState == .active

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "cycle/hardware_buttons", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
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
    let proximityOn = proximityWanted && isActive
    if UIDevice.current.isProximityMonitoringEnabled != proximityOn {
      UIDevice.current.isProximityMonitoringEnabled = proximityOn
      // Turning monitoring off while covered never sends "uncovered".
      if !proximityOn { channel.invokeMethod("onProximity", arguments: false) }
    }
  }

  @objc private func proximityChanged() {
    guard UIDevice.current.isProximityMonitoringEnabled else { return }
    channel.invokeMethod("onProximity", arguments: UIDevice.current.proximityState)
  }
}

/// OpenAndroMaps' "Others" install button (`mf-V4-map://ftp.gwdg.de/…/X.zip`),
/// tapped on openandromaps.org in the browser. Keeps the latest such link until
/// Dart collects it over `cycle/incoming_map` (`consumePending`); Dart then
/// validates it and asks the rider before downloading anything.
///
/// The app runs with a scene delegate, so links arrive as scene events, not at
/// the app delegate. This registers through Flutter's scene-lifecycle hook
/// (`addSceneDelegate`) instead of overriding `SceneDelegate`: Flutter's own
/// `scene(_:willConnectTo:)` / `openURLContexts` aren't in its public header,
/// so a Swift subclass could neither override nor call them.
final class IncomingMapLinks: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var pending: String?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = IncomingMapLinks()
    let channel = FlutterMethodChannel(
      name: "cycle/incoming_map", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addSceneDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "consumePending" else { return result(FlutterMethodNotImplemented) }
    result(pending)
    pending = nil
  }

  /// Cold start from a link: the URL comes with the connection options.
  /// Returns false so Flutter still treats the connection as unhandled and
  /// sets up its window as usual.
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    if let contexts = connectionOptions?.urlContexts { _ = capture(contexts) }
    return false
  }

  /// A link while the app is running or in the background.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    capture(URLContexts)
  }

  private func capture(_ contexts: Set<UIOpenURLContext>) -> Bool {
    guard let url = contexts.map(\.url).first(where: { $0.scheme?.lowercased() == "mf-v4-map" })
    else { return false }
    pending = url.absoluteString
    return true
  }
}
