import Flutter
import UIKit
import CoreLocation
import MapZoneSpeedAlertSDK

/// Flutter bridge over the MapZone Speed Alert SDK (`ZoneNetworkManager`).
///
/// - MethodChannel `mapzone_speed_alert` for imperative calls.
/// - EventChannels `.../alert`, `.../voice`, `.../ready`, `.../result`,
///   `.../location`, `.../restriction` for the SDK callbacks.
///
/// The native engine is process-wide; the Swift `ZoneNetworkManager` around it
/// is rebuilt on every `initialize` / `configureVehicle`, because it remembers
/// the last restriction sign per group and neither `reset()` nor `configure`
/// clears that — a reused manager would never re-announce a sign the vehicle is
/// still under.
///
/// Voice: the SDK's built-in player speaks until Dart listens to the `voice`
/// channel; while that listener exists the clips are forwarded to Dart instead,
/// and cancelling it hands playback back to the SDK.
public class MapzoneSpeedAlertPlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {

  private static let channelName = "mapzone_speed_alert"

  // MARK: - Properties

  private var mgr = ZoneNetworkManager()
  private var locationManager: EnhancedLocationManager?
  private var methodChannel: FlutterMethodChannel?

  // Dedicated manager just for permission requests / status.
  private let permissionManager = CLLocationManager()
  private var permissionResult: FlutterResult?

  private var eventChannels: [FlutterEventChannel] = []
  private var streams: [CallbackStream] = []
  private var alertStream: CallbackStream!
  private var readyStream: CallbackStream!
  private var resultStream: CallbackStream!
  private var locationStream: CallbackStream!
  private var voiceStream: CallbackStream!
  private var restrictionStream: CallbackStream!

  // Restriction images are PNG-encoded off the main thread; this serial queue
  // keeps the group updates in order and owns `restriction`.
  private let encoder = DispatchQueue(label: "com.mapzone.speed_alert.encoder")

  // Whether this engine configured the native engine. The plugin is registered
  // on every Flutter engine, so teardown must only reset what this instance
  // set up.
  private var configured = false

  // Cached config so configureVehicle can re-configure.
  private var baseUrl = ""
  private var apiKeyId = ""
  private var apiKey = ""
  private var vehicleId = ""
  private var vehicleType = 1
  private var seats = 4
  private var weight = 1500

  // Voice preferences live here as well as in the engine and are re-applied
  // after every configure, so a configureVehicle can never silently undo what
  // Dart believes is set.
  private var mutedTypes = Set<VoiceAlertType>()
  private var voiceProfile = VoiceProfile.full
  // The built-in player (and its speed) belongs to the manager, so the speed is
  // re-applied whenever the manager is rebuilt.
  private var voiceSpeed: Float = 1

  // Last image references, for change detection (avoid re-encoding PNGs).
  private var lastCur: UIImage?
  private var lastNext: UIImage?
  private var lastCam: UIImage?
  private var lastToll: UIImage?

  // Merged restriction signs. The SDK reports each group only when it changes,
  // so the latest state is kept here and replayed to new listeners. Only
  // touched on `encoder`.
  private var restriction = RestrictionSnapshot()

  // MARK: - Plugin Registration

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let instance = MapzoneSpeedAlertPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    // Publishing is what makes the engine call detachFromEngine(for:) on teardown.
    registrar.publish(instance)
    instance.methodChannel = channel
    instance.registerStreams(messenger)
    instance.wireCallbacks(instance.mgr)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    methodChannel?.setMethodCallHandler(nil)
    eventChannels.forEach { $0.setStreamHandler(nil) }
    eventChannels.removeAll()
    // Drop the voice closure this engine installed so the built-in player is
    // not left muted by a detached engine.
    streams.forEach { $0.release() }
    streams.removeAll()
    stopTracking()
    unwire(mgr)
    if configured {
      mgr.reset()
      configured = false
    }
  }

  // MARK: - MethodCall Dispatcher

  private let logTag = "[MapZoneSpeedAlert]"
  private func log(_ message: String) {
    NSLog("%@ %@", logTag, message)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    log("call: \(call.method)")
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)

    case "initialize":
      readConfig(call.arguments as? [String: Any])
      applyConfig(result)

    case "configureVehicle":
      let args = call.arguments as? [String: Any]
      vehicleType = (args?["vehicleType"] as? Int) ?? vehicleType
      seats = (args?["seats"] as? Int) ?? seats
      weight = (args?["weight"] as? Int) ?? weight
      applyConfig(result)

    case "start":
      startTracking(result)

    case "stop":
      stopTracking()
      result(nil)

    case "reset":
      stopTracking()
      mgr.reset()
      configured = false
      resetImageCache()
      clearRestriction()
      result(nil)

    case "processExternalLocation":
      let args = call.arguments as? [String: Any]
      let lat = (args?["lat"] as? Double) ?? 0
      let lng = (args?["lng"] as? Double) ?? 0
      let bearing = (args?["bearing"] as? Double) ?? 0
      let speedKmh = (args?["speedKmh"] as? Double) ?? 0
      let accuracy = (args?["accuracy"] as? Double) ?? 0
      // Dart always sends the fix time; the fallback only guards against a
      // malformed call.
      let fixTime = (args?["fixTimeMillis"] as? NSNumber)?.int64Value
        ?? Int64(Date().timeIntervalSince1970 * 1000)
      // Before initialize there is no engine of ours to feed.
      if configured {
        mgr.updateLocation(lat: lat, lng: lng, speedKmh: speedKmh, bearingDeg: bearing)
        mgr.processGps(lat: lat, lng: lng, bearing: bearing, speedKmh: speedKmh,
                       accuracy: accuracy, timestampMs: fixTime)
      }
      result(nil)

    case "updateZoneLocation":
      let args = call.arguments as? [String: Any]
      let lat = (args?["lat"] as? Double) ?? 0
      let lng = (args?["lng"] as? Double) ?? 0
      if configured { mgr.updateLocation(lat: lat, lng: lng) }
      result(nil)

    case "setMutedAlertTypes":
      let triggers = (call.arguments as? [String: Any])?["triggers"] as? [Int] ?? []
      mutedTypes = Set(triggers.compactMap { VoiceAlertType(rawValue: $0) })
      log("setMutedAlertTypes \(mutedTypes.map { $0.rawValue }.sorted())")
      mgr.setMutedAlertTypes(mutedTypes)
      result(nil)

    case "setVoiceProfile":
      let value = (call.arguments as? [String: Any])?["profile"] as? Int ?? 0
      voiceProfile = VoiceProfile(rawValue: value) ?? .full
      mgr.setVoiceProfile(voiceProfile)
      result(nil)

    case "setVoiceSpeed":
      voiceSpeed = ((call.arguments as? [String: Any])?["speed"] as? NSNumber)?.floatValue ?? 1
      mgr.setVoiceSpeed(voiceSpeed)
      result(nil)

    case "getLinkCoords":
      // Not available in the native SDK; kept so old callers get null.
      result(nil)

    case "hasLocationPermissions":
      result(hasLocationPermission())

    case "requestLocationPermissions":
      requestLocationPermission(result)

    case "onAppBackground", "onAppForeground":
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Engine setup & SDK callbacks

  private func readConfig(_ args: [String: Any]?) {
    baseUrl = (args?["baseUrl"] as? String) ?? ""
    apiKeyId = (args?["apiKeyId"] as? String) ?? ""
    apiKey = (args?["apiKey"] as? String) ?? ""
    vehicleId = (args?["vehicleId"] as? String) ?? ""
    vehicleType = (args?["vehicleType"] as? Int) ?? 1
    seats = (args?["seats"] as? Int) ?? 4
    weight = (args?["weight"] as? Int) ?? 1500
  }

  /// Rebuild the manager and configure it with the cached config. The SDK
  /// reads the host bundle id itself, so it must match the id registered for
  /// the API key.
  private func applyConfig(_ result: FlutterResult) {
    // GPS capture keeps running: its closure always feeds the current `mgr`.
    unwire(mgr)
    mgr.reset()
    resetImageCache()
    clearRestriction()
    // Same rule as the SDK (and the Android plugin, which throws): the SDK
    // would only report it later through onResult.
    guard baseUrl.hasPrefix("https://") else {
      configured = false
      result(FlutterError(code: "CONFIGURE_FAILED",
                          message: "baseUrl must start with https://", details: nil))
      return
    }
    let m = ZoneNetworkManager()
    wireCallbacks(m)
    mgr = m
    log("configure baseUrl=\(baseUrl) vehicleId=\(vehicleId) type=\(vehicleType) seats=\(seats) weight=\(weight)")
    m.configure(baseUrl: baseUrl, apiKeyId: apiKeyId, apiKey: apiKey,
                vehicleId: vehicleId, vehicleType: vehicleType,
                seats: seats, weights: weight)
    // Re-apply the host's voice preferences before any GPS reaches it.
    m.setMutedAlertTypes(mutedTypes)
    m.setVoiceProfile(voiceProfile)
    m.setVoiceSpeed(voiceSpeed)
    if voiceStream.isActive { installVoiceHandler(m) }
    configured = true
    result(nil)
  }

  /// Detach every closure from a manager that is being replaced, so late
  /// callbacks from its queue cannot reach Dart (or the new snapshot).
  private func unwire(_ m: ZoneNetworkManager) {
    m.onReady = nil
    m.onResult = nil
    m.onBitmap = nil
    m.onVoice = nil
    m.onAccessRestriction = nil
    m.onStopRestriction = nil
    m.onBuildupArea = nil
    m.useBuiltInVoicePlayer = false
  }

  /// Forward voice clips to Dart; setting `onVoice` silences the built-in
  /// player (and drops its backlog).
  private func installVoiceHandler(_ m: ZoneNetworkManager) {
    m.onVoice = { [weak self] wav, trigger, priority in
      self?.voiceStream.send([
        "wav": FlutterStandardTypedData(bytes: wav),
        "trigger": trigger,
        "priority": priority,
      ])
    }
  }

  /// Register the SDK callbacks on `m` (voice is handled by the voice stream).
  private func wireCallbacks(_ m: ZoneNetworkManager) {
    // The SDK default is silent without `onVoice`; the plugin's contract is
    // that the SDK speaks unless Dart listens to the voice channel.
    m.useBuiltInVoicePlayer = true

    m.onReady = { [weak self] linkCount, alertCount in
      self?.log("onReady links=\(linkCount) alerts=\(alertCount)")
      self?.readyStream.send([
        "isReady": true,
        "linkCount": linkCount,
        "alertCount": alertCount,
      ])
    }
    m.onResult = { [weak self] success, code, message in
      self?.log("onResult success=\(success) code=\(code) message=\(message)")
      self?.resultStream.send([
        "success": success,
        "errorCode": code,
        "errorMessage": message,
      ])
    }
    m.onBitmap = { [weak self] current, status, next, nextDist, camera, cameraDist, toll, tollDist, _ in
      guard let self = self else { return }
      self.alertStream.send(self.buildAlertMap(
        current: current, status: status,
        next: next, nextDist: nextDist,
        camera: camera, cameraDist: cameraDist,
        toll: toll, tollDist: tollDist))
    }
    m.onAccessRestriction = { [weak self] image, kind, dist in
      self?.updateRestriction { $0.withAccess(png(image), kind: kind, dist: dist) }
    }
    m.onStopRestriction = { [weak self] image, kind, dist in
      self?.updateRestriction { $0.withStop(png(image), kind: kind, dist: dist) }
    }
    m.onBuildupArea = { [weak self] image, kind, dist in
      self?.updateRestriction { $0.withBuildupArea(png(image), kind: kind, dist: dist) }
    }
  }

  private func registerStreams(_ messenger: FlutterBinaryMessenger) {
    alertStream = stream(messenger, "alert")
    readyStream = stream(messenger, "ready")
    resultStream = stream(messenger, "result")
    locationStream = stream(messenger, "location")
    voiceStream = stream(messenger, "voice", open: { [weak self] in
      guard let self = self else { return }
      self.installVoiceHandler(self.mgr)
    }, close: { [weak self] in
      self?.mgr.onVoice = nil
    })
    restrictionStream = stream(messenger, "restriction", open: { [weak self] in
      guard let self = self else { return }
      self.encoder.async { self.restrictionStream.send(self.restriction.toMap()) }
    })
  }

  /// Register an event channel. `open` runs when Dart starts listening and
  /// `close` when it stops (or the engine detaches while listening).
  private func stream(_ messenger: FlutterBinaryMessenger, _ name: String,
                      open: @escaping () -> Void = {},
                      close: @escaping () -> Void = {}) -> CallbackStream {
    let channel = FlutterEventChannel(name: "\(Self.channelName)/\(name)",
                                      binaryMessenger: messenger)
    let handler = CallbackStream(open: open, close: close)
    channel.setStreamHandler(handler)
    eventChannels.append(channel)
    streams.append(handler)
    return handler
  }

  // MARK: - Restriction signs

  /// Apply one group update on `encoder` (the PNG encode inside `update` runs
  /// there too) and forward the merged snapshot.
  private func updateRestriction(_ update: @escaping (RestrictionSnapshot) -> RestrictionSnapshot) {
    encoder.async { [weak self] in
      guard let self = self else { return }
      self.restriction = update(self.restriction)
      self.restrictionStream.send(self.restriction.toMap())
    }
  }

  /// Forget every restriction sign and tell Dart the slots are now empty.
  private func clearRestriction() {
    updateRestriction { _ in RestrictionSnapshot() }
  }

  // MARK: - Sign image encoding (change-detected PNG)

  private func buildAlertMap(
    current: UIImage?, status: Int,
    next: UIImage?, nextDist: Int,
    camera: UIImage?, cameraDist: Int,
    toll: UIImage?, tollDist: Int
  ) -> [String: Any] {
    var map: [String: Any] = ["speedStatus": status]
    lastCur = putSign(&map, "cur", current, lastCur, nil)
    lastNext = putSign(&map, "next", next, lastNext, nextDist)
    lastCam = putSign(&map, "cam", camera, lastCam, cameraDist)
    lastToll = putSign(&map, "toll", toll, lastToll, tollDist)
    return map
  }

  /// Populate `map` for one sign slot, only encoding a PNG when the image
  /// reference changed since last frame. Returns the image to cache.
  private func putSign(
    _ map: inout [String: Any],
    _ key: String,
    _ img: UIImage?,
    _ last: UIImage?,
    _ dist: Int?
  ) -> UIImage? {
    let present = img != nil
    map["\(key)Present"] = present
    guard let img = img else {
      map["\(key)Changed"] = false
      return nil
    }
    let changed = img !== last
    map["\(key)Changed"] = changed
    if changed, let data = img.pngData() {
      map["\(key)Sign"] = FlutterStandardTypedData(bytes: data)
    }
    if let dist = dist {
      map["\(key)Dist"] = dist
    }
    return img
  }

  private func resetImageCache() {
    lastCur = nil
    lastNext = nil
    lastCam = nil
    lastToll = nil
  }

  // MARK: - GPS capture (Approach A)

  private func startTracking(_ result: @escaping FlutterResult) {
    guard configured else {
      result(FlutterError(code: "NOT_INITIALIZED",
                          message: "Call initialize() before start().", details: nil))
      return
    }
    guard hasLocationPermission() else {
      result(FlutterError(code: "PERMISSION_DENIED",
                          message: "Location permission not granted.", details: nil))
      return
    }
    stopTracking()
    log("startTracking: begin native GPS capture")
    let lm = EnhancedLocationManager()
    lm.onLocationUpdate = { [weak self] location, _, _ in
      guard let self = self else { return }
      let lat = location.coordinate.latitude
      let lng = location.coordinate.longitude
      let speedKmh = max(0, location.speed) * 3.6
      let bearing = location.course >= 0 ? location.course : 0
      let accuracy = location.horizontalAccuracy
      // The engine times voice throttling and stop detection against the fix's
      // own clock, never the time this callback ran.
      let fixTime = Int64(location.timestamp.timeIntervalSince1970 * 1000)
      self.log(String(format: "gps lat=%.6f lng=%.6f spd=%.1f acc=%.0f", lat, lng, speedKmh, accuracy))
      self.mgr.updateLocation(lat: lat, lng: lng, speedKmh: speedKmh, bearingDeg: bearing)
      self.mgr.processGps(lat: lat, lng: lng, bearing: bearing, speedKmh: speedKmh,
                          accuracy: accuracy, timestampMs: fixTime)
      self.locationStream.send([
        "lat": lat,
        "lng": lng,
        "speedKmh": speedKmh,
        "bearing": bearing,
        "accuracy": accuracy,
        "timestamp": fixTime,
      ])
    }
    lm.onLocationError = { [weak self] error in
      self?.log("onLocationError: \(error)")
      self?.resultStream.send([
        "success": false,
        "errorCode": -1,
        "errorMessage": error,
      ])
    }
    lm.enableBackgroundLocationUpdates(true)
    lm.startTracking(highAccuracyMode: true)
    locationManager = lm
    result(nil)
  }

  private func stopTracking() {
    locationManager?.stopTracking()
    locationManager = nil
  }

  // MARK: - Permissions

  private func hasLocationPermission() -> Bool {
    let status: CLAuthorizationStatus
    if #available(iOS 14.0, *) {
      status = permissionManager.authorizationStatus
    } else {
      status = CLLocationManager.authorizationStatus()
    }
    return status == .authorizedWhenInUse || status == .authorizedAlways
  }

  private func requestLocationPermission(_ result: @escaping FlutterResult) {
    if hasLocationPermission() {
      result(true)
      return
    }
    permissionResult = result
    permissionManager.delegate = self
    permissionManager.requestWhenInUseAuthorization()
  }

  private func resolvePermission() {
    guard let result = permissionResult else { return }
    permissionResult = nil
    result(hasLocationPermission())
  }

  public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    // iOS 14+
    if manager.authorizationStatus == .notDetermined { return }
    resolvePermission()
  }

  public func locationManager(_ manager: CLLocationManager,
                              didChangeAuthorization status: CLAuthorizationStatus) {
    // iOS < 14
    if status == .notDetermined { return }
    resolvePermission()
  }
}

private func png(_ image: UIImage?) -> FlutterStandardTypedData? {
  guard let data = image?.pngData() else { return nil }
  return FlutterStandardTypedData(bytes: data)
}

/// The restriction slots Dart sees, merged from the SDK's three independent
/// groups (access, stop, built-up area). An image without artwork arrives as
/// `nil` and leaves its slot empty.
private struct RestrictionSnapshot {
  // Group kinds, as documented on `ZoneNetworkManager`.
  static let roadClosed = 3
  static let vehicleRestricted = 4
  static let buildupAreaStart = 5

  var stop: FlutterStandardTypedData?
  var stopDist = 0
  var closed: FlutterStandardTypedData?
  var closedDist = 0
  var vehicle: FlutterStandardTypedData?
  var vehicleDist = 0
  var bua: FlutterStandardTypedData?
  var buaDist = 0
  var inBua = false

  /// Access group: one of road-closed / vehicle-restricted, or neither.
  func withAccess(_ png: FlutterStandardTypedData?, kind: Int, dist: Int) -> RestrictionSnapshot {
    var s = self
    s.closed = kind == Self.roadClosed ? png : nil
    s.closedDist = kind == Self.roadClosed ? dist : 0
    s.vehicle = kind == Self.vehicleRestricted ? png : nil
    s.vehicleDist = kind == Self.vehicleRestricted ? dist : 0
    return s
  }

  /// Stop group: no-parking or no-stopping share the one slot.
  func withStop(_ png: FlutterStandardTypedData?, kind: Int, dist: Int) -> RestrictionSnapshot {
    var s = self
    s.stop = kind != 0 ? png : nil
    s.stopDist = kind != 0 ? dist : 0
    return s
  }

  /// Built-up area: entry or end sign; `dist == 0` with START means inside.
  func withBuildupArea(_ png: FlutterStandardTypedData?, kind: Int, dist: Int) -> RestrictionSnapshot {
    var s = self
    s.bua = kind != 0 ? png : nil
    s.buaDist = kind != 0 ? dist : 0
    s.inBua = kind == Self.buildupAreaStart && dist == 0
    return s
  }

  func toMap() -> [String: Any] {
    return [
      "stop": stop ?? NSNull(),
      "stopDistMeters": stopDist,
      "closed": closed ?? NSNull(),
      "closedDistMeters": closedDist,
      "vehicle": vehicle ?? NSNull(),
      "vehicleDistMeters": vehicleDist,
      "bua": bua ?? NSNull(),
      "buaDistMeters": buaDist,
      "inBua": inBua,
    ]
  }
}

/// `FlutterStreamHandler` that keeps a sink, delivers events on the main
/// thread, and runs open/close hooks around the Dart subscription.
private class CallbackStream: NSObject, FlutterStreamHandler {
  private let open: () -> Void
  private let close: () -> Void
  private var sink: FlutterEventSink?
  // Whether `open` ran without a matching `close`.
  private(set) var isActive = false

  init(open: @escaping () -> Void, close: @escaping () -> Void) {
    self.open = open
    self.close = close
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError? {
    sink = events
    isActive = true
    open()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    release()
    return nil
  }

  /// Undo `open` if it is still in effect.
  func release() {
    sink = nil
    if isActive {
      isActive = false
      close()
    }
  }

  func send(_ data: Any) {
    if Thread.isMainThread {
      sink?(data)
    } else {
      DispatchQueue.main.async { [weak self] in self?.sink?(data) }
    }
  }
}
