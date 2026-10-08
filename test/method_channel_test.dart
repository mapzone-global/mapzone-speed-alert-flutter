import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapzone_speed_alert/src/platform/method_channel_map_zone_speed_alert.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mapzone_speed_alert');
  final platform = MethodChannelMapZoneSpeedAlert();
  final calls = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getPlatformVersion') return 'Android 14';
      if (call.method == 'hasLocationPermissions') return true;
      return null;
    });
  });

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initialize sends the full config payload', () async {
    await platform.initialize(const AlertConfig(
      baseUrl: 'https://x',
      apiKeyId: 'id',
      apiKey: 'key',
      vehicleId: 'v1',
      vehicleType: VehicleType.bus,
      seats: 30,
      weight: 8000,
    ));
    expect(calls.single.method, 'initialize');
    final args = Map<String, dynamic>.from(calls.single.arguments as Map);
    expect(args['baseUrl'], 'https://x');
    expect(args['vehicleType'], 5);
    expect(args['weight'], 8000);
    expect(args.containsKey('bundleId'), isFalse);
  });

  test('processExternalLocation forwards coordinates', () async {
    await platform.processExternalLocation(
      lat: 21.0,
      lng: 105.0,
      bearing: 90,
      speedKmh: 50,
      accuracy: 3,
    );
    expect(calls.single.method, 'processExternalLocation');
    final args = Map<String, dynamic>.from(calls.single.arguments as Map);
    expect(args['lat'], 21.0);
    expect(args['speedKmh'], 50);
  });

  test('processExternalLocation sends the given fix time', () async {
    await platform.processExternalLocation(
      lat: 21.0,
      lng: 105.0,
      bearing: 90,
      speedKmh: 50,
      fixTimeMillis: 1700000000123,
    );
    final args = Map<String, dynamic>.from(calls.single.arguments as Map);
    expect(args['fixTimeMillis'], 1700000000123);
  });

  test('processExternalLocation defaults the fix time to now', () async {
    final before = DateTime.now().millisecondsSinceEpoch;
    await platform.processExternalLocation(
        lat: 21.0, lng: 105.0, bearing: 0, speedKmh: 0);
    final after = DateTime.now().millisecondsSinceEpoch;
    final args = Map<String, dynamic>.from(calls.single.arguments as Map);
    final sent = args['fixTimeMillis'] as int;
    expect(sent, inInclusiveRange(before, after));
  });

  test('setMutedAlertTypes sends the trigger codes', () async {
    await platform.setMutedAlertTypes(
        [VoiceAlertType.speedCamera, VoiceAlertType.toll]);
    expect(calls.single.method, 'setMutedAlertTypes');
    final args = Map<String, dynamic>.from(calls.single.arguments as Map);
    expect(args['triggers'], [3, 4]);
  });

  test('setMutedAlertTypes sends the restriction trigger codes', () async {
    await platform.setMutedAlertTypes([
      VoiceAlertType.noStopping,
      VoiceAlertType.roadClosed,
      VoiceAlertType.vehicleRestricted,
    ]);
    final args = Map<String, dynamic>.from(calls.single.arguments as Map);
    expect(args['triggers'], [19, 20, 21]);
  });

  test('setVoiceProfile sends the native profile value', () async {
    await platform.setVoiceProfile(VoiceProfile.dingOnly);
    await platform.setVoiceProfile(VoiceProfile.full);
    expect(calls.map((c) => c.method), ['setVoiceProfile', 'setVoiceProfile']);
    expect((calls[0].arguments as Map)['profile'], 1);
    expect((calls[1].arguments as Map)['profile'], 0);
  });

  test('setVoiceSpeed sends the speed', () async {
    await platform.setVoiceSpeed(1.5);
    expect(calls.single.method, 'setVoiceSpeed');
    expect((calls.single.arguments as Map)['speed'], 1.5);
  });

  test('updateZoneLocation forwards lat/lng', () async {
    await platform.updateZoneLocation(21.0, 105.0);
    expect(calls.single.method, 'updateZoneLocation');
    final args = Map<String, dynamic>.from(calls.single.arguments as Map);
    expect(args['lat'], 21.0);
    expect(args['lng'], 105.0);
  });

  test('getLinkCoords returns null without calling native', () async {
    // ignore: deprecated_member_use_from_same_package
    expect(await platform.getLinkCoords(42), isNull);
    expect(calls, isEmpty);
  });

  test('getPlatformVersion / permission relay through the channel', () async {
    expect(await platform.getPlatformVersion(), 'Android 14');
    expect(await platform.hasLocationPermissions(), isTrue);
  });

  test('onRestriction replays the latest event to a later listener', () async {
    const events = EventChannel('mapzone_speed_alert/restriction');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (args, sink) {
        sink.success({'stopDistMeters': 80, 'inBua': true});
      }),
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockStreamHandler(events, null));

    final local = MethodChannelMapZoneSpeedAlert();
    final first = await local.onRestriction.first;
    expect(first.stopDistMeters, 80);

    // The native subscription is already open for this listener; it must
    // still see the current state.
    final keepAlive = local.onRestriction.listen((_) {});
    addTearDown(keepAlive.cancel);
    final second = await local.onRestriction.first;
    expect(second.inBua, isTrue);
  });
}
