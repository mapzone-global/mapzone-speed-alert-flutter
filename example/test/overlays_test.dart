import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';
import 'package:mapzone_speed_alert_example/models/vehicle_profile.dart';
import 'package:mapzone_speed_alert_example/state/alert_controller.dart';
import 'package:mapzone_speed_alert_example/widgets/bottom_action_bar.dart';
import 'package:mapzone_speed_alert_example/widgets/mute_sheet.dart';
import 'package:mapzone_speed_alert_example/widgets/settings_dialog.dart';
import 'package:mapzone_speed_alert_example/widgets/sign_widgets.dart';

/// The overlays only ever appear on top of a live map, so a screenshot of the
/// idle screen cannot prove they lay out. These pump them in isolation — a
/// RenderFlex overflow throws and fails the test.
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('SettingsDialog lays out on a phone-width screen',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // iPhone 13/14 Pro
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      const SettingsDialog(
        vehicle: VehicleProfile(),
        simulate: true,
        speedMultiplier: 2,
      ),
    ));

    // Every vehicle type the SDK accepts is offered.
    for (final t in VehicleType.values) {
      expect(find.text(t.label), findsOneWidget);
    }
    // Simulator is on, so the multiplier presets are visible.
    expect(find.text('3×'), findsOneWidget);
  });

  testWidgets('MuteSheet lays out and locks the speed cues', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AlertController>.value(
        value: AlertController(),
        child: host(const SizedBox(height: 600, child: MuteSheet())),
      ),
    );

    // The speed-limit row exists but cannot be toggled — the SDK force-clears
    // those bits, so offering a switch would be a lie.
    final locked = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('Giới hạn tốc độ & vượt tốc'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(locked.onChanged, isNull);
    expect(locked.value, isTrue);
  });

  testWidgets('BottomActionBar switches label on destination', (tester) async {
    Widget bar({required bool hasDestination}) => host(
          BottomActionBar(
            running: false,
            busy: false,
            hasDestination: hasDestination,
            statusLine: '',
            engineReady: false,
            engineStatus: '',
            onStart: () {},
            onStop: () {},
          ),
        );

    await tester.pumpWidget(bar(hasDestination: false));
    expect(find.text('Bắt đầu cảnh báo (GPS thật)'), findsOneWidget);

    await tester.pumpWidget(bar(hasDestination: true));
    expect(find.text('Bắt đầu navigation'), findsOneWidget);
  });

  testWidgets('RestrictionRow hides when empty and shows filled slots',
      (tester) async {
    // 1×1 transparent PNG.
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
    final controller = AlertController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AlertController>.value(
        value: controller,
        child: host(const SizedBox(width: 200, child: RestrictionRow())),
      ),
    );
    expect(find.byType(Image), findsNothing);

    controller.restrictions = const RestrictionEvent();
    controller.notifyListeners();
    await tester.pump();
    expect(find.byType(Image), findsNothing);

    controller.restrictions = RestrictionEvent(
      stop: png,
      stopDistMeters: 150,
      bua: png,
      inBua: true,
    );
    controller.notifyListeners();
    await tester.pump();
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('150 m'), findsOneWidget);
  });
}
