import 'package:flutter/foundation.dart';

import '../services/permission_service.dart';

/// State holder for the app's location permission.
///
/// [refresh] must be called when the app comes back to the foreground: the user
/// may have changed the permission from the Settings app, and iOS does not
/// notify us — without a re-read the app would keep insisting the permission is
/// missing.
class PermissionController extends ChangeNotifier {
  LocationPermissionStatus status = const LocationPermissionStatus(
    serviceEnabled: true,
    granted: false,
    always: false,
    permanentlyDenied: false,
  );

  bool get granted => status.granted;
  bool get always => status.always;
  bool get foregroundOnly => status.foregroundOnly;
  bool get serviceEnabled => status.serviceEnabled;
  bool get needsSettings => status.needsSettings;

  Future<void> refresh() async {
    status = await PermissionService.check();
    notifyListeners();
  }

  /// Show the system prompts (when-in-use, then "Change to Always Allow") and
  /// return whether we ended up with at least foreground location.
  Future<bool> request() async {
    status = await PermissionService.request();
    notifyListeners();
    return status.granted;
  }

  /// Ask only for the background upgrade.
  Future<bool> requestAlways() async {
    status = await PermissionService.requestAlways();
    notifyListeners();
    return status.always;
  }

  Future<void> openSettings() => PermissionService.openSettings();
}
