import 'package:flutter/widgets.dart';

import 'models/alert_config.dart';
import 'models/alert_event.dart';
import 'models/alert_location.dart';
import 'models/alert_result.dart';
import 'models/ready_event.dart';
import 'models/restriction_event.dart';
import 'models/vehicle_type.dart';
import 'models/voice_alert_type.dart';
import 'models/voice_event.dart';
import 'models/voice_profile.dart';
import 'platform/map_zone_speed_alert_platform.dart';

/// High-level entry point for the MapZone Speed Alert engine.
///
/// Use the [instance] singleton. Optionally call [registerLifecycleObserver]
/// once so the plugin is notified when the app moves to background/foreground.
///
/// ```dart
/// final alert = MapZoneSpeedAlert.instance;
/// await alert.initialize(AlertConfig(...));
/// alert.onAlert.listen((e) => setState(() => _event = e));
/// await alert.requestLocationPermissions();
/// await alert.start();
/// ```
///
/// Voice: the SDK speaks alerts through its built-in player. Listen to
/// [onVoice] to play the clips yourself instead; cancel every subscription to
/// hand playback back to the SDK.
///
/// The native engine is process-wide: use it from a single Flutter engine.
class MapZoneSpeedAlert with WidgetsBindingObserver {
  MapZoneSpeedAlert._();

  static final MapZoneSpeedAlert instance = MapZoneSpeedAlert._();

  MapZoneSpeedAlertPlatform get _platform => MapZoneSpeedAlertPlatform.instance;

  bool _lifecycleRegistered = false;

  Future<String?> getPlatformVersion() => _platform.getPlatformVersion();

  // MARK: - Configuration & engine lifecycle

  /// Configure the native alert engine. Call once before [start].
  Future<void> initialize(AlertConfig config) => _platform.initialize(config);

  /// Re-configure the engine with a new vehicle profile at runtime. Mute and
  /// voice-profile settings are kept.
  Future<void> configureVehicle({
    required VehicleType vehicleType,
    required int seats,
    required int weight,
  }) => _platform.configureVehicle(
    vehicleType: vehicleType,
    seats: seats,
    weight: weight,
  );

  /// Start native GPS capture and begin producing alerts (Approach A).
  Future<void> start() => _platform.start();

  /// Stop native GPS capture (engine state preserved).
  Future<void> stop() => _platform.stop();

  /// Reset the engine and free native memory.
  Future<void> reset() => _platform.reset();

  /// Feed an externally-sourced (navigation-snapped) GPS frame (Approach B).
  ///
  /// Pass the fix's own timestamp as [fixTimeMillis] (epoch milliseconds):
  /// the engine times voice throttling and stop detection against it. When
  /// null, the time of this call is used.
  Future<void> processExternalLocation({
    required double lat,
    required double lng,
    required double bearing,
    required double speedKmh,
    double accuracy = 0,
    int? fixTimeMillis,
  }) => _platform.processExternalLocation(
    lat: lat,
    lng: lng,
    bearing: bearing,
    speedKmh: speedKmh,
    accuracy: accuracy,
    fixTimeMillis: fixTimeMillis,
  );

  /// Lightweight zone-cache warm-up (native 2-arg `updateLocation`).
  Future<void> updateZoneLocation(double lat, double lng) =>
      _platform.updateZoneLocation(lat, lng);

  // MARK: - Voice alert configuration

  /// Mute the given voice-alert categories (empty list re-enables all).
  /// See [VoiceAlertType] for which categories also hide their sign.
  Future<void> setMutedAlertTypes(List<VoiceAlertType> types) =>
      _platform.setMutedAlertTypes(types);

  /// Choose full spoken phrases or short ding tones. Muted categories stay
  /// silent in both profiles.
  Future<void> setVoiceProfile(VoiceProfile profile) =>
      _platform.setVoiceProfile(profile);

  /// Set the built-in player's playback speed (`1.0` = recorded speed,
  /// clamped to `0.5..2.0`, pitch kept). No effect while [onVoice] has a
  /// listener. Persists across [reset].
  Future<void> setVoiceSpeed(double speed) => _platform.setVoiceSpeed(speed);

  // MARK: - Utilities

  /// Removed from the native SDK; always returns `null`.
  @Deprecated(
    'Removed from the native SDK; always returns null. Will be deleted in a '
    'future major release.',
  )
  Future<List<List<double>>?> getLinkCoords(int linkId) async => null;

  // MARK: - Permissions

  Future<bool> requestLocationPermissions() =>
      _platform.requestLocationPermissions();

  Future<bool> hasLocationPermissions() => _platform.hasLocationPermissions();

  // MARK: - Event streams

  /// Speed-limit, next-sign, camera and toll signs, once per processed fix.
  Stream<AlertEvent> get onAlert => _platform.onAlert;

  /// Voice clips for the host to play. While this stream has a listener the
  /// SDK's built-in player is silent; cancel every subscription to restore it.
  Stream<VoiceEvent> get onVoice => _platform.onVoice;

  /// Engine-ready notifications after zone data loads.
  Stream<ReadyEvent> get onReady => _platform.onReady;

  /// Outcome of each zone load, and native failures.
  Stream<AlertResult> get onResult => _platform.onResult;

  /// Road-restriction signs (no stopping / parking, closed road, vehicle ban,
  /// built-up area). Emitted when a slot changes; a new listener immediately
  /// receives the current state.
  Stream<RestrictionEvent> get onRestriction => _platform.onRestriction;

  /// Native GPS fixes (Approach A).
  Stream<AlertLocation> get onLocation => _platform.onLocation;

  // MARK: - App lifecycle bridging

  /// Register with [WidgetsBinding] so background/foreground transitions are
  /// forwarded to the native engine. Safe to call more than once.
  void registerLifecycleObserver() {
    if (_lifecycleRegistered) return;
    WidgetsBinding.instance.addObserver(this);
    _lifecycleRegistered = true;
  }

  void unregisterLifecycleObserver() {
    if (!_lifecycleRegistered) return;
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleRegistered = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _platform.onAppBackground();
        break;
      case AppLifecycleState.resumed:
        _platform.onAppForeground();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }
}
