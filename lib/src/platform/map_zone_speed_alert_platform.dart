import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models/alert_config.dart';
import '../models/alert_event.dart';
import '../models/alert_location.dart';
import '../models/alert_result.dart';
import '../models/ready_event.dart';
import '../models/restriction_event.dart';
import '../models/vehicle_type.dart';
import '../models/voice_alert_type.dart';
import '../models/voice_event.dart';
import '../models/voice_profile.dart';
import 'method_channel_map_zone_speed_alert.dart';

/// The platform interface all `mapzone_speed_alert` backends implement.
abstract class MapZoneSpeedAlertPlatform extends PlatformInterface {
  MapZoneSpeedAlertPlatform() : super(token: _token);

  static final Object _token = Object();
  static MapZoneSpeedAlertPlatform _instance = MethodChannelMapZoneSpeedAlert();

  static MapZoneSpeedAlertPlatform get instance => _instance;

  static set instance(MapZoneSpeedAlertPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  // MARK: - Lifecycle / configuration

  /// Configure the native `ZoneNetworkManager` alert engine.
  Future<void> initialize(AlertConfig config) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Re-configure the engine with a new vehicle profile (type / seats / weight).
  Future<void> configureVehicle({
    required VehicleType vehicleType,
    required int seats,
    required int weight,
  }) {
    throw UnimplementedError('configureVehicle() has not been implemented.');
  }

  /// Start native GPS capture and begin feeding the engine (Approach A).
  Future<void> start() {
    throw UnimplementedError('start() has not been implemented.');
  }

  /// Stop native GPS capture. The engine state is preserved (call [reset] to
  /// free native memory).
  Future<void> stop() {
    throw UnimplementedError('stop() has not been implemented.');
  }

  /// Reset engine state and free native memory (call before disposing).
  Future<void> reset() {
    throw UnimplementedError('reset() has not been implemented.');
  }

  /// Feed an externally-sourced (e.g. navigation-snapped) GPS frame into the
  /// engine (Approach B). Runs `updateLocation` + `processGps` natively.
  /// [fixTimeMillis] is the fix's own epoch-millisecond timestamp; when null
  /// the time of the call is used.
  Future<void> processExternalLocation({
    required double lat,
    required double lng,
    required double bearing,
    required double speedKmh,
    double accuracy = 0,
    int? fixTimeMillis,
  }) {
    throw UnimplementedError(
        'processExternalLocation() has not been implemented.');
  }

  /// Lightweight zone-cache warm-up: refreshes the zone data around
  /// ([lat], [lng]) without running map-matching. Maps to the native
  /// 2-argument `updateLocation(lat, lng)`.
  Future<void> updateZoneLocation(double lat, double lng) {
    throw UnimplementedError('updateZoneLocation() has not been implemented.');
  }

  // MARK: - Voice alert configuration

  /// Mute the given voice-alert categories (empty list re-enables all).
  Future<void> setMutedAlertTypes(List<VoiceAlertType> types) {
    throw UnimplementedError('setMutedAlertTypes() has not been implemented.');
  }

  /// Choose full spoken phrases or short ding tones.
  Future<void> setVoiceProfile(VoiceProfile profile) {
    throw UnimplementedError('setVoiceProfile() has not been implemented.');
  }

  /// Playback speed of the SDK's built-in voice player.
  Future<void> setVoiceSpeed(double speed) {
    throw UnimplementedError('setVoiceSpeed() has not been implemented.');
  }

  // MARK: - Utilities

  /// Removed from the native SDK; always `null`.
  @Deprecated('Removed from the native SDK; always returns null.')
  Future<List<List<double>>?> getLinkCoords(int linkId) {
    throw UnimplementedError('getLinkCoords() has not been implemented.');
  }

  // MARK: - Permissions

  Future<bool> requestLocationPermissions() {
    throw UnimplementedError(
        'requestLocationPermissions() has not been implemented.');
  }

  Future<bool> hasLocationPermissions() {
    throw UnimplementedError(
        'hasLocationPermissions() has not been implemented.');
  }

  // MARK: - App lifecycle bridging

  Future<void> onAppBackground() {
    throw UnimplementedError('onAppBackground() has not been implemented.');
  }

  Future<void> onAppForeground() {
    throw UnimplementedError('onAppForeground() has not been implemented.');
  }

  // MARK: - Event streams

  /// Speed-limit / next-sign / camera / toll signs, distances and speed status.
  Stream<AlertEvent> get onAlert {
    throw UnimplementedError('onAlert has not been implemented.');
  }

  /// Voice clips (WAV bytes + trigger + priority). Listening silences the
  /// SDK's built-in player.
  Stream<VoiceEvent> get onVoice {
    throw UnimplementedError('onVoice has not been implemented.');
  }

  /// Engine-ready notifications after zone data loads.
  Stream<ReadyEvent> get onReady {
    throw UnimplementedError('onReady has not been implemented.');
  }

  /// Success / error notifications from the engine.
  Stream<AlertResult> get onResult {
    throw UnimplementedError('onResult has not been implemented.');
  }

  /// Road-restriction signs (no stopping / parking, closed road, vehicle ban,
  /// built-up area).
  Stream<RestrictionEvent> get onRestriction {
    throw UnimplementedError('onRestriction has not been implemented.');
  }

  /// Native GPS fixes (Approach A).
  Stream<AlertLocation> get onLocation {
    throw UnimplementedError('onLocation has not been implemented.');
  }
}
