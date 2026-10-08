import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Where the app stands on location permission.
///
/// The engine keeps alerting while the phone is in a pocket or the screen is
/// off, which iOS only allows under "Always". That is a *second* prompt: iOS
/// refuses to show it until when-in-use has already been granted, so the two
/// have to be asked one after the other, never together.
class LocationPermissionStatus {
  const LocationPermissionStatus({
    required this.serviceEnabled,
    required this.granted,
    required this.always,
    required this.permanentlyDenied,
  });

  /// Location Services is switched on at the OS level.
  final bool serviceEnabled;

  /// The app may read location while it is in the foreground. Enough to drive
  /// with the app open.
  final bool granted;

  /// The app may read location in the background too — needed for alerts to
  /// survive a locked screen.
  final bool always;

  /// The user said no and iOS will never show the system prompt again — the only
  /// way back is the Settings app.
  final bool permanentlyDenied;

  bool get needsSettings => permanentlyDenied;

  /// Foreground works but background does not: the app runs, but alerts stop
  /// the moment the screen locks.
  bool get foregroundOnly => granted && !always;
}

class PermissionService {
  static Future<LocationPermissionStatus> check() async {
    final whenInUse = await Permission.locationWhenInUse.status;
    return LocationPermissionStatus(
      serviceEnabled: await Permission.location.serviceStatus.isEnabled,
      granted: whenInUse.isGranted || whenInUse.isLimited,
      always: await Permission.locationAlways.isGranted,
      // Both of these are dead ends for a re-request: permanentlyDenied is the
      // user's final "no" (iOS never prompts twice), and restricted means
      // parental controls or an MDM profile forbids it outright. Either way the
      // only move left is the Settings app.
      permanentlyDenied: whenInUse.isPermanentlyDenied || whenInUse.isRestricted,
    );
  }

  /// Ask for foreground location, then escalate to background.
  ///
  /// The two requests must be sequential and awaited. iOS only shows the
  /// "Change to Always Allow?" upgrade prompt when when-in-use is *already*
  /// granted at the moment `requestAlwaysAuthorization` runs — fire them both in
  /// the same run loop and the second one is silently dropped, leaving the app
  /// stuck on foreground-only with no way to ask again.
  ///
  /// Both prompts appear exactly once in the app's lifetime; afterwards every
  /// call returns the stored answer without showing anything. That is why the
  /// caller must handle [LocationPermissionStatus.permanentlyDenied] by sending
  /// the user to Settings rather than asking again.
  static Future<LocationPermissionStatus> request() async {
    await Permission.locationWhenInUse.request();

    if (await Permission.locationWhenInUse.isGranted) {
      // This is the "Change to Always Allow?" prompt.
      await Permission.locationAlways.request();
    }

    if (!Platform.isIOS) {
      // Android needs the notification permission for the foreground service
      // that keeps alerts alive; iOS does not.
      await Permission.notification.request();
    }
    return check();
  }

  /// Escalate an existing when-in-use grant to "Always", on its own.
  ///
  /// Used when the user chose "Keep Only While Using" the first time and later
  /// asks for background alerts.
  static Future<LocationPermissionStatus> requestAlways() async {
    await Permission.locationAlways.request();
    return check();
  }

  static Future<void> openSettings() => openAppSettings();
}
