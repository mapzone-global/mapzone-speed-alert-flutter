import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapzone_speed_alert_example/state/alert_controller.dart';

/// The plugin's method channel. `processExternalLocation` has to be stubbed or
/// AlertController would throw MissingPluginException.
const _channels = [
  MethodChannel('mapzone_speed_alert'),
  // AlertController builds a VoiceQueue, which reaches for audioplayers on
  // construction.
  MethodChannel('xyz.luan/audioplayers.global'),
  MethodChannel('xyz.luan/audioplayers'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    for (final c in _channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, (_) async => null);
    }
  });

  tearDown(() {
    for (final c in _channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  test('speed comes from the injected position while a route is driven', () async {
    final c = AlertController();
    expect(c.speedKmh, 0);

    await c.injectLocation(
        lat: 10.76, lng: 106.69, bearing: 90, speedKmh: 72.5);

    // `onLocation` never fires for an externally-injected position — the plugin
    // only emits it from its own native GPS capture. Reading the location stream
    // alone left the HUD stuck at 0 km/h next to a red "exceeding" badge.
    expect(c.location, isNull);
    expect(c.speedKmh, 72.5);
  });

  test('stopping clears the speed', () async {
    final c = AlertController();
    await c.injectLocation(lat: 10.76, lng: 106.69, bearing: 0, speedKmh: 50);
    expect(c.speedKmh, 50);

    await c.stop();
    expect(c.speedKmh, 0, reason: 'a stopped engine is not doing 50 km/h');
  });
}
