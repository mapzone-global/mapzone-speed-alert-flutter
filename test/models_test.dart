import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

void main() {
  group('VehicleType', () {
    test('matches the SDK integer codes', () {
      expect(VehicleType.car.value, 1);
      expect(VehicleType.motorcycle.value, 2);
      expect(VehicleType.truck.value, 3);
      expect(VehicleType.bicycle.value, 7);
      expect(VehicleType.emergency.value, 9);
    });

    test('fromValue resolves and falls back to car', () {
      expect(VehicleType.fromValue(3), VehicleType.truck);
      expect(VehicleType.fromValue(999), VehicleType.car);
    });
  });

  group('VoiceAlertType', () {
    test('trigger codes match the SDK', () {
      expect(VoiceAlertType.speedCamera.trigger, 3);
      expect(VoiceAlertType.toll.trigger, 4);
      expect(VoiceAlertType.restStation.trigger, 18);
      expect(VoiceAlertType.noStopping.trigger, 19);
      expect(VoiceAlertType.roadClosed.trigger, 20);
      expect(VoiceAlertType.vehicleRestricted.trigger, 21);
    });

    test('fromTrigger resolves categories and null for core cues', () {
      expect(VoiceAlertType.fromTrigger(4), VoiceAlertType.toll);
      expect(VoiceAlertType.fromTrigger(21), VoiceAlertType.vehicleRestricted);
      expect(VoiceAlertType.fromTrigger(0), isNull); // speed-limit cue
      expect(VoiceAlertType.fromTrigger(1), isNull); // speeding cue
    });

    test('VoiceEvent.type maps from trigger', () {
      final cam = VoiceEvent.fromJson(
          {'wav': Uint8List(0), 'trigger': 3, 'priority': 1});
      expect(cam.type, VoiceAlertType.speedCamera);
      final speeding = VoiceEvent.fromJson(
          {'wav': Uint8List(0), 'trigger': 2, 'priority': 2});
      expect(speeding.type, isNull);
    });
  });

  group('VoiceProfile', () {
    test('values match the SDK', () {
      expect(VoiceProfile.full.value, 0);
      expect(VoiceProfile.dingOnly.value, 1);
    });
  });

  group('RestrictionEvent', () {
    test('parses every slot', () {
      final png = Uint8List.fromList([1, 2, 3]);
      final e = RestrictionEvent.fromJson({
        'stop': png,
        'stopDistMeters': 120,
        'closed': null,
        'closedDistMeters': 0,
        'vehicle': png,
        'vehicleDistMeters': 0,
        'bua': png,
        'buaDistMeters': 0,
        'inBua': true,
      });
      expect(e.stop, png);
      expect(e.stopDistMeters, 120);
      expect(e.closed, isNull);
      expect(e.vehicle, png);
      expect(e.bua, png);
      expect(e.inBua, isTrue);
      expect(e.isEmpty, isFalse);
    });

    test('missing keys give empty slots', () {
      final e = RestrictionEvent.fromJson(const {});
      expect(e.isEmpty, isTrue);
      expect(e.stopDistMeters, 0);
      expect(e.inBua, isFalse);
    });
  });

  group('SpeedStatus', () {
    test('fromValue maps codes', () {
      expect(SpeedStatus.fromValue(0), SpeedStatus.compliant);
      expect(SpeedStatus.fromValue(1), SpeedStatus.approaching);
      expect(SpeedStatus.fromValue(2), SpeedStatus.exceeding);
      expect(SpeedStatus.fromValue(null), SpeedStatus.compliant);
    });
  });

  group('AlertConfig', () {
    test('serializes weight as int and vehicleType as its value', () {
      const config = AlertConfig(
        baseUrl: 'https://x',
        apiKeyId: 'id',
        apiKey: 'key',
        vehicleId: 'v1',
        vehicleType: VehicleType.truck,
        seats: 2,
        weight: 3000,
      );
      final json = config.toJson();
      expect(json['vehicleType'], 3);
      expect(json['weight'], 3000);
      expect(json['weight'], isA<int>());
      expect(json.containsKey('bundleId'), isFalse);
    });
  });

  group('AlertEvent.merge', () {
    Uint8List bytes(int b) => Uint8List.fromList([b, b, b]);

    test('reuses previous image when unchanged', () {
      final first = AlertEvent.merge({
        'speedStatus': 2,
        'curPresent': true,
        'curChanged': true,
        'curSign': bytes(1),
        'nextPresent': true,
        'nextChanged': true,
        'nextSign': bytes(2),
        'nextDist': 120,
      }, null);

      expect(first.speedStatus, SpeedStatus.exceeding);
      expect(first.currentSpeedLimitSign, bytes(1));
      expect(first.nextDistanceMeters, 120);

      final second = AlertEvent.merge({
        'speedStatus': 0,
        'curPresent': true,
        'curChanged': false, // unchanged -> reuse
        'nextPresent': true,
        'nextChanged': false,
        'nextDist': 80,
      }, first);

      expect(second.currentSpeedLimitSign, bytes(1));
      expect(second.nextSign, bytes(2));
      expect(second.nextDistanceMeters, 80);
    });

    test('clears a slot when not present', () {
      final prev = AlertEvent.merge({
        'speedStatus': 0,
        'camPresent': true,
        'camChanged': true,
        'camSign': bytes(9),
        'camDist': 300,
      }, null);
      expect(prev.cameraSign, bytes(9));

      final next = AlertEvent.merge({
        'speedStatus': 0,
        'camPresent': false,
      }, prev);
      expect(next.cameraSign, isNull);
      expect(next.cameraDistanceMeters, isNull);
    });

    test('negative distance is treated as none', () {
      final e = AlertEvent.merge({
        'speedStatus': 0,
        'tollPresent': true,
        'tollChanged': true,
        'tollSign': bytes(4),
        'tollDist': -1,
      }, null);
      expect(e.tollDistanceMeters, isNull);
    });
  });

  group('VoiceEvent / ReadyEvent / AlertResult', () {
    test('VoiceEvent parses bytes and priority', () {
      final e = VoiceEvent.fromJson({
        'wav': Uint8List.fromList([1, 2, 3]),
        'trigger': 5,
        'priority': 2,
      });
      expect(e.wav.length, 3);
      expect(e.trigger, 5);
      expect(e.priority, 2);
    });

    test('ReadyEvent parses counts', () {
      final e = ReadyEvent.fromJson(
          {'isReady': true, 'linkCount': 10, 'alertCount': 4});
      expect(e.isReady, isTrue);
      expect(e.linkCount, 10);
      expect(e.alertCount, 4);
    });

    test('AlertResult exposes error helpers', () {
      final expired = AlertResult.fromJson(
          {'success': false, 'errorCode': 2003, 'errorMessage': 'expired'});
      expect(expired.isExpiredApiKey, isTrue);
      final net = AlertResult.fromJson(
          {'success': false, 'errorCode': -5, 'errorMessage': 'net'});
      expect(net.isNetworkError, isTrue);
    });
  });
}
