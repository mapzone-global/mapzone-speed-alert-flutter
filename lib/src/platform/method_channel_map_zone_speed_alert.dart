import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/alert_config.dart';
import '../models/alert_event.dart';
import '../models/alert_location.dart';
import '../models/alert_result.dart';
import '../models/ready_event.dart';
import '../models/restriction_event.dart';
import '../models/snapped_location.dart';
import '../models/vehicle_type.dart';
import '../models/voice_alert_type.dart';
import '../models/voice_event.dart';
import '../models/voice_profile.dart';
import 'map_zone_speed_alert_platform.dart';

/// [MethodChannel] / [EventChannel] implementation of [MapZoneSpeedAlertPlatform].
class MethodChannelMapZoneSpeedAlert extends MapZoneSpeedAlertPlatform {
  static const String _channelName = 'mapzone_speed_alert';

  final MethodChannel _method = const MethodChannel(_channelName);

  final EventChannel _alertChannel = const EventChannel('$_channelName/alert');
  final EventChannel _voiceChannel = const EventChannel('$_channelName/voice');
  final EventChannel _readyChannel = const EventChannel('$_channelName/ready');
  final EventChannel _resultChannel = const EventChannel(
    '$_channelName/result',
  );
  final EventChannel _locationChannel = const EventChannel(
    '$_channelName/location',
  );
  final EventChannel _restrictionChannel = const EventChannel(
    '$_channelName/restriction',
  );
  final EventChannel _snappedLocationChannel = const EventChannel(
    '$_channelName/snapped',
  );

  // Cached streams so multiple listeners share one native subscription.
  Stream<AlertEvent>? _onAlert;
  Stream<VoiceEvent>? _onVoice;
  Stream<ReadyEvent>? _onReady;
  Stream<AlertResult>? _onResult;
  Stream<AlertLocation>? _onLocation;
  Stream<RestrictionEvent>? _onRestriction;
  Stream<SnappedLocation>? _onSnappedLocation;

  // Native shares one subscription between every Dart listener and only
  // replays its state when that subscription opens, so the latest event is
  // kept here for listeners that join later.
  RestrictionEvent? _lastRestriction;

  // Last emitted alert event, used to reuse unchanged image bytes.
  AlertEvent? _lastAlert;

  static Map<String, dynamic> _asMap(dynamic event) =>
      Map<String, dynamic>.from(event as Map);

  // MARK: - Method invocations

  @override
  Future<String?> getPlatformVersion() =>
      _method.invokeMethod<String>('getPlatformVersion');

  @override
  Future<void> initialize(AlertConfig config) async {
    final Map<String, dynamic> payload;
    try {
      payload = config.toJson();
    } on JsonUnsupportedObjectError catch (e) {
      // Same contract as a rejection by the SDK: nothing is applied.
      throw PlatformException(
        code: 'INVALID_CONFIGURATION',
        message:
            'metadata is not JSON-encodable: ${e.unsupportedObject.runtimeType}',
      );
    }
    await _method.invokeMethod<void>('initialize', payload);
  }

  @override
  Future<void> configureVehicle({
    required VehicleType vehicleType,
    required int seats,
    required double weightTons,
  }) async {
    await _method.invokeMethod<void>('configureVehicle', <String, dynamic>{
      'vehicleType': vehicleType.value,
      'seats': seats,
      'weightTons': weightTons,
    });
  }

  @override
  Future<AlertResult> logout() async {
    final result = await _method.invokeMapMethod<String, dynamic>('logout');
    return AlertResult.fromJson(result ?? const <String, dynamic>{});
  }

  @override
  Future<void> start() => _method.invokeMethod<void>('start');

  @override
  Future<void> stop() => _method.invokeMethod<void>('stop');

  @override
  Future<void> reset() {
    _lastAlert = null;
    return _method.invokeMethod<void>('reset');
  }

  @override
  Future<void> processExternalLocation({
    required double lat,
    required double lng,
    required double bearing,
    required double speedKmh,
    double accuracy = 0,
    int? fixTimeMillis,
  }) async {
    await _method.invokeMethod<void>(
      'processExternalLocation',
      <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'bearing': bearing,
        'speedKmh': speedKmh,
        'accuracy': accuracy,
        'fixTimeMillis': fixTimeMillis ?? DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  @override
  Future<void> updateZoneLocation(double lat, double lng) async {
    await _method.invokeMethod<void>('updateZoneLocation', <String, dynamic>{
      'lat': lat,
      'lng': lng,
    });
  }

  @override
  Future<void> setMutedAlertTypes(List<VoiceAlertType> types) async {
    await _method.invokeMethod<void>('setMutedAlertTypes', <String, dynamic>{
      'triggers': types.map((t) => t.trigger).toList(),
    });
  }

  @override
  Future<void> setVoiceProfile(VoiceProfile profile) =>
      _method.invokeMethod<void>('setVoiceProfile', <String, dynamic>{
        'profile': profile.value,
      });

  @override
  Future<void> setVoiceSpeed(double speed) => _method.invokeMethod<void>(
    'setVoiceSpeed',
    <String, dynamic>{'speed': speed},
  );

  @override
  @Deprecated('Removed from the native SDK; always returns null.')
  Future<List<List<double>>?> getLinkCoords(int linkId) async => null;

  @override
  Future<bool> requestLocationPermissions() async {
    final granted = await _method.invokeMethod<bool>(
      'requestLocationPermissions',
    );
    return granted ?? false;
  }

  @override
  Future<bool> hasLocationPermissions() async {
    final granted = await _method.invokeMethod<bool>('hasLocationPermissions');
    return granted ?? false;
  }

  @override
  Future<void> onAppBackground() =>
      _method.invokeMethod<void>('onAppBackground');

  @override
  Future<void> onAppForeground() =>
      _method.invokeMethod<void>('onAppForeground');

  // MARK: - Event streams

  @override
  Stream<AlertEvent> get onAlert {
    _onAlert ??= _alertChannel.receiveBroadcastStream().map((event) {
      final merged = AlertEvent.merge(_asMap(event), _lastAlert);
      _lastAlert = merged;
      return merged;
    });
    return _onAlert!;
  }

  @override
  Stream<VoiceEvent> get onVoice {
    _onVoice ??= _voiceChannel.receiveBroadcastStream().map(
      (event) => VoiceEvent.fromJson(_asMap(event)),
    );
    return _onVoice!;
  }

  @override
  Stream<ReadyEvent> get onReady {
    _onReady ??= _readyChannel.receiveBroadcastStream().map(
      (event) => ReadyEvent.fromJson(_asMap(event)),
    );
    return _onReady!;
  }

  @override
  Stream<AlertResult> get onResult {
    _onResult ??= _resultChannel.receiveBroadcastStream().map(
      (event) => AlertResult.fromJson(_asMap(event)),
    );
    return _onResult!;
  }

  @override
  Stream<RestrictionEvent> get onRestriction {
    final shared = _onRestriction ??= _restrictionChannel
        .receiveBroadcastStream()
        .map(
          (event) =>
              _lastRestriction = RestrictionEvent.fromJson(_asMap(event)),
        );
    return Stream<RestrictionEvent>.multi((controller) {
      final last = _lastRestriction;
      if (last != null) controller.add(last);
      final sub = shared.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Stream<AlertLocation> get onLocation {
    _onLocation ??= _locationChannel.receiveBroadcastStream().map(
      (event) => AlertLocation.fromJson(_asMap(event)),
    );
    return _onLocation!;
  }

  @override
  Stream<SnappedLocation> get onSnappedLocation {
    _onSnappedLocation ??= _snappedLocationChannel.receiveBroadcastStream().map(
      (event) => SnappedLocation.fromJson(_asMap(event)),
    );
    return _onSnappedLocation!;
  }
}
