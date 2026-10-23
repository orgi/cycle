import AudioToolbox
import CoreLocation
import Flutter
import HealthKit
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var hardwareButtons: HardwareButtons?
  private var appleHealth: AppleHealth?
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
    appleHealth = AppleHealth(messenger: messenger)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IncomingMapLinks") {
      IncomingMapLinks.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IncomingGpx") {
      IncomingGpx.register(with: registrar)
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
    // in the browser (Nextcloud login, OpenAndroMaps, the OSM credit). The
    // name dates from the removed Strava OAuth flow.
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
  /// Returns false: Flutter hands the options to the first plugin that claims
  /// them and nil to the rest, so claiming them would hide an opened GPX from
  /// IncomingGpx.
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

/// A `.gpx` opened in Radl from another app (Komoot's GPX export via the share
/// sheet, Files, Mail) — the iOS half of `MainActivity.kt`'s
/// `cycle/incoming_gpx`. The file is read as it arrives and kept until Dart
/// collects it on resume (`consumePending` → `{name, xml}`), which then follows
/// it or asks whether it's a past ride. Scene events, like IncomingMapLinks.
final class IncomingGpx: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var pending: [String: String]?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = IncomingGpx()
    let channel = FlutterMethodChannel(
      name: "cycle/incoming_gpx", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addSceneDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "consumePending" else { return result(FlutterMethodNotImplemented) }
    result(pending)
    pending = nil
  }

  /// Cold start from a file: it comes with the connection options. Returns
  /// false for the same reason as IncomingMapLinks.
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    if let contexts = connectionOptions?.urlContexts { _ = capture(contexts) }
    return false
  }

  /// A file while the app is running or in the background.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    capture(URLContexts)
  }

  /// Only GPX (and plain XML) are registered as document types, so any file URL
  /// is taken as one; Dart reports a file that doesn't parse. Claimed even when
  /// unreadable, so nothing else tries to open it.
  private func capture(_ contexts: Set<UIOpenURLContext>) -> Bool {
    guard let url = contexts.map(\.url).first(where: \.isFileURL) else { return false }
    // A file opened in place (Files app) lies outside the sandbox.
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    var data: Data?
    var error: NSError?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { readURL in
      data = try? Data(contentsOf: readURL)
    }
    guard let data = data else {
      NSLog("%@", "Radl: could not read opened file \(url.lastPathComponent): \(String(describing: error))")
      return true
    }
    pending = [
      "name": url.deletingPathExtension().lastPathComponent,
      "xml": String(decoding: data, as: UTF8.self),
    ]
    NSLog("%@", "Radl: opened GPX \(url.lastPathComponent) (\(data.count) bytes)")
    if Self.isInboxCopy(url) { try? FileManager.default.removeItem(at: url) }
    return true
  }

  /// A file shared from another app arrives as a copy in Documents/Inbox, which
  /// the Files app shows (Documents is shared) — removed once read. A file
  /// opened in place belongs to its owner and is left alone. Paths are compared
  /// with symlinks resolved: the URL says /private/var/…, Documents /var/….
  private static func isInboxCopy(_ url: URL) -> Bool {
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return false }
    let inbox = documents.appendingPathComponent("Inbox").resolvingSymlinksInPath().path + "/"
    return url.resolvingSymlinksInPath().path.hasPrefix(inbox)
  }
}

/// `cycle/health`: saves finished rides to Apple Health as cycling workouts
/// (Dart: `MethodChannelAppleHealthService`). Write-only — no read permission
/// is asked for; Dart remembers which rides it already saved.
///   `requestAccess` → Bool: shows the Health permission sheet the first time;
///     true when saving workouts is allowed.
///   `saveRide(map)`: workout (start/end, distance, heart-rate samples, the
///     ride's id as `HKMetadataKeyExternalUUID`) plus its GPS route.
/// Needs the `com.apple.developer.healthkit` entitlement (Runner.entitlements;
/// the CI build embeds it so the sideload signer enables HealthKit).
final class AppleHealth {
  private let store = HKHealthStore()
  private let channel: FlutterMethodChannel

  private let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceCycling)!
  private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "cycle/health", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "requestAccess":
        self.requestAccess(result)
      case "saveRide":
        guard let args = call.arguments as? [String: Any] else {
          return result(FlutterError(code: "bad_args", message: "ride expected", details: nil))
        }
        self.saveRide(args, result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private var shareTypes: Set<HKSampleType> {
    [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), distanceType, heartRateType]
  }

  /// FlutterResult must be called on the main thread; HealthKit calls back on
  /// its own queues.
  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func fail(_ result: @escaping FlutterResult, _ message: String) {
    reply(result, FlutterError(code: "health_failed", message: message, details: nil))
  }

  private func requestAccess(_ result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else { return reply(result, false) }
    store.requestAuthorization(toShare: shareTypes, read: nil) { [weak self] _, error in
      guard let self = self else { return }
      if let error = error { return self.fail(result, error.localizedDescription) }
      // Write permission is visible to the app (read permission never is).
      self.reply(result,
        self.store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized)
    }
  }

  private func date(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

  private func saveRide(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      return fail(result, "Apple Health is not available on this device")
    }
    guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
      return fail(result, "Radl may not save to Apple Health. Allow it in the Health app → Sharing → Apps → Radl.")
    }
    guard let startMs = (args["startMs"] as? NSNumber)?.doubleValue,
      let endMs = (args["endMs"] as? NSNumber)?.doubleValue,
      let externalId = args["externalId"] as? String
    else { return fail(result, "Incomplete ride") }
    let start = date(startMs), end = date(endMs)
    let distance = (args["distanceMeters"] as? NSNumber)?.doubleValue ?? 0
    let route = (args["route"] as? [[NSNumber]]) ?? []
    let heartRates = (args["heartRates"] as? [[NSNumber]]) ?? []

    var samples: [HKSample] = []
    if distance > 0 {
      samples.append(HKQuantitySample(
        type: distanceType, quantity: HKQuantity(unit: .meter(), doubleValue: distance),
        start: start, end: end))
    }
    let bpm = HKUnit.count().unitDivided(by: .minute())
    for hr in heartRates where hr.count >= 2 {
      let t = date(hr[0].doubleValue)
      guard t >= start, t <= end else { continue }
      samples.append(HKQuantitySample(
        type: heartRateType, quantity: HKQuantity(unit: bpm, doubleValue: hr[1].doubleValue),
        start: t, end: t))
    }

    let config = HKWorkoutConfiguration()
    config.activityType = .cycling
    config.locationType = .outdoor
    let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
    builder.beginCollection(withStart: start) { [weak self] ok, error in
      guard let self = self else { return }
      guard ok else { return self.fail(result, error?.localizedDescription ?? "Could not start the workout") }
      let afterSamples = {
        builder.addMetadata([HKMetadataKeyExternalUUID: externalId,
                             HKMetadataKeyIndoorWorkout: false]) { _, _ in
          builder.endCollection(withEnd: end) { ok, error in
            guard ok else { return self.fail(result, error?.localizedDescription ?? "Could not end the workout") }
            builder.finishWorkout { workout, error in
              guard let workout = workout else {
                return self.fail(result, error?.localizedDescription ?? "Could not save the workout")
              }
              self.saveRoute(route, to: workout, result)
            }
          }
        }
      }
      if samples.isEmpty { return afterSamples() }
      builder.add(samples) { ok, error in
        guard ok else { return self.fail(result, error?.localizedDescription ?? "Could not add distance/heart rate") }
        afterSamples()
      }
    }
  }

  /// Attaches the GPS route (in batches, as HealthKit recommends) to the saved
  /// workout. A ride without a usable route is still a saved workout.
  private func saveRoute(_ route: [[NSNumber]], to workout: HKWorkout,
                         _ result: @escaping FlutterResult) {
    let locations: [CLLocation] = route.compactMap { p in
      guard p.count >= 3 else { return nil }
      let alt = p.count > 3 ? p[3].doubleValue : Double.nan
      let speed = p.count > 4 ? p[4].doubleValue : -1
      return CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: p[1].doubleValue, longitude: p[2].doubleValue),
        altitude: alt.isNaN ? 0 : alt,
        horizontalAccuracy: 5,
        verticalAccuracy: alt.isNaN ? -1 : 10,
        course: -1,
        speed: speed,
        timestamp: date(p[0].doubleValue))
    }
    guard locations.count >= 2 else { return reply(result, nil) }
    let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
    let batches = stride(from: 0, to: locations.count, by: 500).map {
      Array(locations[$0..<min($0 + 500, locations.count)])
    }
    func insert(_ i: Int) {
      if i == batches.count {
        routeBuilder.finishRoute(with: workout, metadata: nil) { [weak self] _, error in
          guard let self = self else { return }
          if let error = error { return self.fail(result, "Workout saved, route not: \(error.localizedDescription)") }
          self.reply(result, nil)
        }
        return
      }
      routeBuilder.insertRouteData(batches[i]) { [weak self] ok, error in
        guard let self = self else { return }
        guard ok else { return self.fail(result, "Workout saved, route not: \(error?.localizedDescription ?? "unknown error")") }
        insert(i + 1)
      }
    }
    insert(0)
  }
}

