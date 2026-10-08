// Basic smoke test for the example app. The full app initialises the native
// alert engine on first frame, so here we only verify the root widget can be
// constructed (the plugin has its own unit tests under ../../test).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mapzone_speed_alert_example/main.dart';

void main() {
  test('root app widget can be instantiated', () {
    expect(const MapZoneSpeedAlertExampleApp(), isA<Widget>());
  });
}
