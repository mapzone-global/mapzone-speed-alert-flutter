import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

import '../env.dart';
import '../models/vehicle_profile.dart';
import '../voice_queue.dart';

/// State holder for the speed-alert engine ([MapZoneSpeedAlert]):
/// configuration and sign-in, event streams, standalone start/stop, external
/// GPS injection and per-category voice muting.
class AlertController extends ChangeNotifier {
  final MapZoneSpeedAlert _engine = MapZoneSpeedAlert.instance;
  final VoiceQueue _voiceQueue = VoiceQueue();
  final List<StreamSubscription<dynamic>> _subs = [];
  final StreamController<AlertResult> _sessionEnded =
      StreamController<AlertResult>.broadcast();
  final StreamController<AlertResult> _errors =
      StreamController<AlertResult>.broadcast();

  // Code of the last error put on [errors]; cleared by a successful zone load,
  // so the same failure coming back later is shown again.
  int? _lastAnnouncedErrorCode;

  bool initialized = false;
  bool running = false;

  /// Who is signed in (or was last). Starts as [Env.identity]; the settings
  /// dialog can switch it for this run — it is not persisted.
  String identity = Env.identity;

  /// Whether [identity] is signed in on this device. False before a
  /// successful configure and after [logout].
  bool signedIn = false;

  /// Why the SDK rejected the last configuration, if it did.
  String? configurationError;

  // Latest values from the engine's event streams.
  ReadyEvent? ready;
  AlertEvent? alert;
  RestrictionEvent? restrictions;
  AlertLocation? location;
  AlertResult? lastError;
  VoiceEvent? lastVoice;

  /// Voice-alert categories currently muted.
  final Set<VoiceAlertType> mutedTypes = <VoiceAlertType>{};

  /// Vehicle the engine is currently configured for.
  VehicleProfile vehicle = VehicleProfile(
    weightTons: 5,
    seats: Env.defaultVehicle.seats,
    type: VehicleType.car,
  );

  /// Speed of the last position we pushed in via [injectLocation].
  ///
  /// The plugin only emits `onLocation` from its own native GPS capture; a
  /// position handed to `processExternalLocation` reaches the engine but never
  /// comes back out as an event. So while a route is being driven, [location] is
  /// null and the only record of how fast we are going is the value we passed
  /// in. Reading `location?.speedKmh` alone showed a permanent 0 km/h next to a
  /// red "Vượt tốc độ!" badge — the engine knew, the UI did not.
  double _injectedSpeedKmh = 0;

  AlertConfig get config => Env.configFor(vehicle, identity: identity);

  bool get isReady => ready?.isReady ?? false;

  /// Fires when the SDK reports the identity in use on another device
  /// ([MapZoneErrorCode.sessionMoved]); the controller has already logged out.
  Stream<AlertResult> get sessionEnded => _sessionEnded.stream;

  /// Engine failures worth telling the user about, once per distinct code
  /// until the next successful zone load. [lastError] keeps the latest one.
  Stream<AlertResult> get errors => _errors.stream;

  double get speedKmh => location?.speedKmh ?? _injectedSpeedKmh;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Configure the engine and subscribe to its event streams. Call once.
  Future<void> init() async {
    if (initialized) return;
    _engine.registerLifecycleObserver();

    _subs.add(
      _engine.onReady.listen((e) {
        ready = e;
        notifyListeners();
      }),
    );
    _subs.add(
      _engine.onAlert.listen((e) {
        alert = e;
        notifyListeners();
      }),
    );
    _subs.add(
      _engine.onRestriction.listen((e) {
        restrictions = e;
        notifyListeners();
      }),
    );
    _subs.add(
      _engine.onLocation.listen((e) {
        location = e;
        notifyListeners();
      }),
    );
    _subs.add(
      _engine.onResult.listen((e) {
        _recordResult(e);
        if (e.errorCode == MapZoneErrorCode.sessionMoved) {
          // The server already closed the session: logging out completes the
          // local side (and counts as success), then the UI asks to sign in.
          unawaited(logout());
          _sessionEnded.add(e);
        }
        notifyListeners();
      }),
    );
    _subs.add(
      _engine.onVoice.listen((e) {
        lastVoice = e;
        // Muted categories are also filtered natively; this is a UI safety net.
        if (e.type == null || !mutedTypes.contains(e.type)) {
          _voiceQueue.enqueue(e);
        }
        notifyListeners();
      }),
    );

    initialized = true;
    try {
      await _engine.initialize(config);
      signedIn = true;
      configurationError = null;
      _resetErrors();
    } on PlatformException catch (e) {
      // INVALID_CONFIGURATION (e.g. the placeholder identity is empty or has a
      // bad character) or CONFIGURE_FAILED: shown on screen, fixable from the
      // settings dialog.
      configurationError = e.message ?? e.code;
    }
    notifyListeners();
  }

  // ── Identity & vehicle profile ──────────────────────────────────────────────

  /// Sign [newIdentity] in with vehicle [v], or only re-configure the vehicle
  /// when the identity is unchanged and still signed in.
  ///
  /// Either way the engine is reset and re-configured natively, so the next GPS
  /// update refetches the zone. The muted set survives — the plugin re-applies
  /// it. Throws [PlatformException] when the SDK rejects an input; the previous
  /// configuration then stays in effect, and so does this controller's state.
  Future<void> applySettings(VehicleProfile v, String newIdentity) async {
    final needsSignIn = !signedIn || newIdentity != identity;
    if (!needsSignIn && v == vehicle) return;
    if (needsSignIn) {
      await _engine.initialize(Env.configFor(v, identity: newIdentity));
      identity = newIdentity;
      signedIn = true;
    } else {
      await _engine.configureVehicle(
        vehicleType: v.type,
        seats: v.seats,
        weightTons: v.weightTons,
      );
    }
    vehicle = v;
    configurationError = null;
    // A new configuration: earlier failures no longer describe it, and the
    // same code failing again must be announced again.
    _resetErrors();
    notifyListeners();
  }

  /// Sign the identity out of this device. Zone fetches stop at once even
  /// when the request fails; the result tells whether to retry later.
  Future<AlertResult> logout() async {
    // The SDK stops zone fetches before the request goes out, so the UI flips
    // now: a sign-in tapped while the request is in flight must not be undone
    // by its late result.
    signedIn = false;
    notifyListeners();
    return _engine.logout();
  }

  // ── Standalone (Approach A) ─────────────────────────────────────────────────

  Future<void> start() async {
    // A fix queued on the channel just before the last stop must not count
    // as this run's first fix.
    location = null;
    await _engine.start();
    running = true;
    notifyListeners();
  }

  Future<void> stop() async {
    await _engine.stop();
    running = false;
    _injectedSpeedKmh = 0;
    location = null;
    notifyListeners();
  }

  // ── Navigation injection (Approach B) ───────────────────────────────────────

  Future<void> injectLocation({
    required double lat,
    required double lng,
    required double bearing,
    required double speedKmh,
    double accuracy = 5,
  }) {
    if (speedKmh != _injectedSpeedKmh) {
      _injectedSpeedKmh = speedKmh;
      notifyListeners();
    }
    return _engine.processExternalLocation(
      lat: lat,
      lng: lng,
      bearing: bearing,
      speedKmh: speedKmh,
      accuracy: accuracy,
    );
  }

  // ── Voice muting ────────────────────────────────────────────────────────────

  Future<void> toggleMute(VoiceAlertType type) async {
    if (mutedTypes.contains(type)) {
      mutedTypes.remove(type);
    } else {
      mutedTypes.add(type);
    }
    await _applyMutes();
  }

  /// Mute every category the SDK allows muting. The speed-limit and speeding
  /// cues are absent from [VoiceAlertType] by design, so they keep announcing.
  Future<void> muteAll() async {
    mutedTypes
      ..clear()
      ..addAll(VoiceAlertType.values);
    await _applyMutes();
  }

  Future<void> unmuteAll() async {
    mutedTypes.clear();
    await _applyMutes();
  }

  Future<void> _applyMutes() async {
    await _engine.setMutedAlertTypes(mutedTypes.toList());
    notifyListeners();
  }

  bool isMuted(VoiceAlertType type) => mutedTypes.contains(type);

  /// Keep the latest failure for the status line, log every one, and announce
  /// a code once until a zone loads again.
  void _recordResult(AlertResult result) {
    if (result.success || result.errorCode == MapZoneErrorCode.success) {
      _resetErrors();
      return;
    }
    lastError = result;
    debugPrint(
      '[MapZoneSpeedAlert] onResult error ${result.errorCode}: '
      '${result.errorMessage}',
    );
    if (result.errorCode == _lastAnnouncedErrorCode) return;
    _lastAnnouncedErrorCode = result.errorCode;
    _errors.add(result);
  }

  void _resetErrors() {
    lastError = null;
    _lastAnnouncedErrorCode = null;
  }

  void clearError() {
    _resetErrors();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _voiceQueue.dispose();
    _sessionEnded.close();
    _errors.close();
    _engine.reset();
    _engine.unregisterLifecycleObserver();
    super.dispose();
  }
}
