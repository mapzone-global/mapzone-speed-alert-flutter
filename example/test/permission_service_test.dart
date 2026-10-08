import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapzone_speed_alert_example/services/permission_service.dart';

/// permission_handler's platform channel. Faking it lets us drive the states iOS
/// actually produces — in particular the permanently-denied one, which is the
/// whole reason the Settings escape hatch exists and which cannot be reached on
/// a simulator without a human tapping "Don't Allow".
const _channel = MethodChannel('flutter.baseflow.com/permissions/methods');

// PermissionStatus indices, from permission_handler_platform_interface.
const _denied = 0;
const _granted = 1;
const _restricted = 2;
const _limited = 3;
const _permanentlyDenied = 4;

// ServiceStatus indices.
const _serviceDisabled = 0;
const _serviceEnabled = 1;

// Permission indices.
const _permissionLocationAlways = 4;
const _permissionLocationWhenInUse = 5;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Pretend the OS reports [status] for location and [service] for the
  /// location service, and record every permission we ask for.
  List<int> stub({required int status, int service = _serviceEnabled}) {
    final requested = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
          return status;
        case 'checkServiceStatus':
          return service;
        case 'requestPermissions':
          final asked = (call.arguments as List).cast<int>();
          requested.addAll(asked);
          return {for (final p in asked) p: status};
        default:
          return null;
      }
    });
    return requested;
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('granted', () async {
    stub(status: _granted);
    final s = await PermissionService.check();
    expect(s.granted, isTrue);
    expect(s.needsSettings, isFalse);
  });

  test('limited (iOS "approximate location") still counts as granted', () async {
    stub(status: _limited);
    expect((await PermissionService.check()).granted, isTrue);
  });

  test('denied is not permanent — asking again is still worth it', () async {
    stub(status: _denied);
    final s = await PermissionService.check();
    expect(s.granted, isFalse);
    expect(s.needsSettings, isFalse);
  });

  test('permanently denied demands the Settings app', () async {
    stub(status: _permanentlyDenied);
    final s = await PermissionService.check();
    expect(s.granted, isFalse);
    expect(s.needsSettings, isTrue,
        reason: 'iOS will never prompt again — re-requesting is a dead end');
  });

  test('restricted (parental controls) also demands Settings', () async {
    stub(status: _restricted);
    expect((await PermissionService.check()).needsSettings, isTrue);
  });

  test('location services switched off is reported separately', () async {
    stub(status: _granted, service: _serviceDisabled);
    final s = await PermissionService.check();
    expect(s.granted, isTrue, reason: 'the grant is real…');
    expect(s.serviceEnabled, isFalse, reason: '…but there is no GPS to read');
  });

  test('request() escalates to "Always" once when-in-use is granted', () async {
    final requested = stub(status: _granted);
    await PermissionService.request();
    // Background alerts need "Always", and iOS only shows the
    // "Change to Always Allow?" prompt after when-in-use is already granted —
    // so the order here is the whole feature.
    expect(requested, contains(_permissionLocationWhenInUse));
    expect(requested, contains(_permissionLocationAlways));
    expect(requested.indexOf(_permissionLocationWhenInUse),
        lessThan(requested.indexOf(_permissionLocationAlways)),
        reason: 'iOS drops an Always request that arrives before when-in-use');
  });

  test('request() does not ask for "Always" when when-in-use was refused',
      () async {
    final requested = stub(status: _denied);
    await PermissionService.request();
    expect(requested, contains(_permissionLocationWhenInUse));
    expect(requested, isNot(contains(_permissionLocationAlways)),
        reason: 'iOS will not show the upgrade prompt without when-in-use');
  });

  test('foregroundOnly flags a when-in-use grant with no background', () async {
    // "Allow While Using App" → when-in-use granted, Always denied.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
          final p = call.arguments as int;
          return p == _permissionLocationAlways ? _denied : _granted;
        case 'checkServiceStatus':
          return _serviceEnabled;
        default:
          return null;
      }
    });

    final s = await PermissionService.check();
    expect(s.granted, isTrue);
    expect(s.always, isFalse);
    expect(s.foregroundOnly, isTrue,
        reason: 'alerts will die the moment the screen locks — say so');
  });
}
