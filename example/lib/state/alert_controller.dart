import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

import '../env.dart';
import '../models/vehicle_profile.dart';
import '../voice_queue.dart';

/// State holder for the speed-alert engine ([MapZoneSpeedAlert]):
/// configuration, event streams, standalone start/stop, external GPS injection
/// and per-category voice muting.
class AlertController extends ChangeNotifier {
  final MapZoneSpeedAlert _engine = MapZoneSpeedAlert.instance;
  final VoiceQueue _voiceQueue = VoiceQueue();
  final List<StreamSubscription<dynamic>> _subs = [];

  bool initialized = false;
  bool running = false;

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
  VehicleProfile vehicle = Env.defaultVehicle;

  /// Speed of the last position we pushed in via [injectLocation].
  ///
  /// The plugin only emits `onLocation` from its own native GPS capture; a
  /// position handed to `processExternalLocation` reaches the engine but never
  /// comes back out as an event. So while a route is being driven, [location] is
  /// null and the only record of how fast we are going is the value we passed
  /// in. Reading `location?.speedKmh` alone showed a permanent 0 km/h next to a
  /// red "Vượt tốc độ!" badge — the engine knew, the UI did not.
  double _injectedSpeedKmh = 0;

  AlertConfig get config => Env.configFor(vehicle);
  bool get isReady => ready?.isReady ?? false;
  double get speedKmh => location?.speedKmh ?? _injectedSpeedKmh;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Configure the engine and subscribe to its event streams. Call once.
  Future<void> init() async {
    if (initialized) return;
    _engine.registerLifecycleObserver();

    _subs.add(_engine.onReady.listen((e) {
      ready = e;
      notifyListeners();
    }));
    _subs.add(_engine.onAlert.listen((e) {
      alert = e;
      notifyListeners();
    }));
    _subs.add(_engine.onRestriction.listen((e) {
      restrictions = e;
      notifyListeners();
    }));
    _subs.add(_engine.onLocation.listen((e) {
      location = e;
      notifyListeners();
    }));
    _subs.add(_engine.onResult.listen((e) {
      if (!e.success) lastError = e;
      notifyListeners();
    }));
    _subs.add(_engine.onVoice.listen((e) {
      lastVoice = e;
      // Muted categories are also filtered natively; this is a UI safety net.
      if (e.type == null || !mutedTypes.contains(e.type)) {
        _voiceQueue.enqueue(e);
      }
      notifyListeners();
    }));

    await _engine.initialize(config);
    initialized = true;
    notifyListeners();
  }

  // ── Vehicle profile ─────────────────────────────────────────────────────────

  /// Re-configure the engine for a different vehicle.
  ///
  /// Natively this resets and re-configures the engine, so the next GPS update
  /// refetches the zone with the new profile. The muted set survives — the
  /// plugin re-applies it after configuring.
  Future<void> applyVehicle(VehicleProfile v) async {
    if (v == vehicle) return;
    vehicle = v;
    await _engine.configureVehicle(
      vehicleType: v.type,
      seats: v.seats,
      weight: v.weightKg,
    );
    notifyListeners();
  }

  // ── Standalone (Approach A) ─────────────────────────────────────────────────

  Future<void> start() async {
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

  void clearError() {
    lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _voiceQueue.dispose();
    _engine.reset();
    _engine.unregisterLifecycleObserver();
    super.dispose();
  }
}
