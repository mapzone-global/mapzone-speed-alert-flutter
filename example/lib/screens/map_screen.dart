import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';
import 'package:vietmap_flutter_navigation/vietmap_flutter_navigation.dart';

import '../env.dart';
import '../services/vietmap_search.dart';
import '../state/alert_controller.dart';
import '../state/permission_controller.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/destination_search_bar.dart';
import '../widgets/map_control_cluster.dart';
import '../widgets/mute_sheet.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/sign_widgets.dart';

/// The whole app: one map, everything else floating on top of it — the shape of
/// the MapZone Android reference app.
///
/// One Start button, two modes:
///   * no destination → speed alert on raw GPS ([AlertController.start]);
///   * destination    → build the route, navigate, and feed the snapped GPS into
///     the engine via `processExternalLocation`.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  MapNavigationViewController? _controller;
  late final MapOptions _options;

  // 197 Trần Phú, Q5 — the fallback shown before a GPS fix lands.
  static const LatLng _fallbackOrigin = LatLng(10.759222, 106.675902);

  LatLng? _currentLocation;
  LatLng? _destination;
  String? _destinationLabel;

  bool _routeBuilt = false;
  bool _buildingRoute = false;
  bool _navigating = false;
  bool _alertOnly = false;
  bool _exiting = false;

  bool _simulate = true;
  double _speedMultiplier = 1;

  // Speed fed to the engine while simulating, before the multiplier. Hard-coded
  // (not user-facing): high enough that a 2× multiplier clears a 50–80 km/h
  // limit so speeding can actually be tested. See _onProgress.
  static const double _simBaseSpeedKmh = 45;

  bool get _running => _navigating || _alertOnly;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The embedded map activates its own location component as soon as it is
    // created and prompts on its own, so deferring our request to the Start
    // button buys nothing — the first prompt has already happened by then, and
    // the "Change to Always Allow" escalation would be left dangling. Ask up
    // front so the two prompts arrive as the pair iOS expects.
    WidgetsBinding.instance.addPostFrameCallback((_) => _primePermissions());
    _options = MapOptions(
      apiKey: Env.vietmapApiKey,
      mapStyle: Env.vietmapMapStyle,
      simulateRoute: _simulate,
      initialLatitude: _fallbackOrigin.latitude,
      initialLongitude: _fallbackOrigin.longitude,
      zoom: 15,
      // The alert engine provides the Vietnamese safety voice, and this example
      // draws its own HUD — so silence the navigation SDK's own TTS and banner
      // or you get two voices and a covered-up sign column.
      voiceInstructionsEnabled: false,
      bannerInstructionsEnabled: false,
      language: 'vi',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The user may have granted the permission from the Settings app while we
  /// were backgrounded; iOS does not tell us, so re-read it on the way back in.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<PermissionController>().refresh();
    }
  }

  // ── Permission ──────────────────────────────────────────────────────────────

  /// Ask for location once, on the first frame, without any of the nagging the
  /// Start button does — a launch is the wrong moment to shove a "go to
  /// Settings" dialog at someone.
  Future<void> _primePermissions() async {
    final perm = context.read<PermissionController>();
    await perm.refresh();
    if (!mounted || !perm.serviceEnabled || perm.needsSettings) return;

    if (!perm.granted) {
      // Prompts for when-in-use, then for "Always".
      await perm.request();
    } else if (!perm.always) {
      // Foreground was granted on an earlier run; offer the background upgrade.
      await perm.requestAlways();
    }
  }

  /// Returns true when we may read location.
  ///
  /// Two prompts, in order: when-in-use, then "Change to Always Allow". iOS
  /// shows each exactly once. After a refusal `request()` keeps returning
  /// "denied" without showing anything, so asking again is a dead end — the only
  /// way back is the Settings app, which is what the dialog offers.
  ///
  /// Foreground-only is not fatal: the app still alerts while it is on screen.
  /// It is called out rather than blocked, because blocking would leave a user
  /// who tapped "Keep Only While Using" with an app that does nothing.
  Future<bool> _ensureLocationPermission() async {
    final perm = context.read<PermissionController>();
    await perm.refresh();
    if (!mounted) return false;

    if (!perm.serviceEnabled) {
      _snack('Dịch vụ vị trí đang tắt. Bật Location Services trong Cài đặt.');
      return false;
    }

    if (!perm.granted) {
      if (perm.needsSettings) {
        await _showSettingsDialog();
        return false;
      }
      // Prompts for when-in-use and then for "Always".
      final granted = await perm.request();
      if (!mounted) return false;
      if (!granted) {
        await _showSettingsDialog();
        return false;
      }
    }

    if (!mounted) return false;
    if (perm.foregroundOnly) _warnForegroundOnly();
    return true;
  }

  /// The engine keeps alerting with the screen off, but only under "Always".
  void _warnForegroundOnly() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: const Text(
            'Chỉ có quyền khi mở app — cảnh báo sẽ tắt khi khoá màn hình.'),
        action: SnackBarAction(
          label: 'Bật quyền nền',
          onPressed: () async {
            final perm = context.read<PermissionController>();
            // iOS shows the upgrade prompt only if it has never been answered;
            // once the user has said "Keep Only While Using" this is a no-op, so
            // fall through to Settings.
            if (await perm.requestAlways()) return;
            if (!mounted) return;
            await perm.openSettings();
          },
        ),
      ),
    );
  }

  Future<void> _showSettingsDialog() async {
    final perm = context.read<PermissionController>();
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cần quyền vị trí'),
        content: const Text(
          'Ứng dụng cần quyền vị trí để cảnh báo tốc độ. iOS chỉ hỏi một lần, '
          'nên bạn cần bật lại trong Cài đặt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Để sau'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Mở Cài đặt'),
          ),
        ],
      ),
    );
    if (open == true) await perm.openSettings();
  }

  // ── Start / stop ────────────────────────────────────────────────────────────

  Future<void> _start() async {
    if (!await _ensureLocationPermission()) return;
    if (!mounted) return;
    final alert = context.read<AlertController>();

    if (_destination == null) {
      // No destination: raw-GPS speed alert, no route. Same as the Android app's
      // "speed alert only" branch.
      //
      // The plugin gates start() on its own CLLocationManager check, which can
      // still disagree with permission_handler for a moment after the prompt is
      // answered, so surface the failure instead of leaving a dead button.
      try {
        await alert.start();
      } on PlatformException catch (e) {
        if (!mounted) return;
        _snack('Không bật được cảnh báo: ${e.message ?? e.code}');
        return;
      }
      if (!mounted) return;
      setState(() => _alertOnly = true);
      // Follow the GPS position (north-up) with the map SDK's own tracking, so
      // the puck and camera move with every fix.
      _fireAndForget(_controller?.recenter());
      return;
    }

    // The route was normally pre-built when the destination was picked; only
    // build here if that hasn't happened yet (e.g. a build failure earlier).
    if (!_routeBuilt) {
      setState(() => _buildingRoute = true);
      final origin = _currentLocation ?? await _resolveCurrentLocation();
      if (!mounted) return;
      _options.simulateRoute = _simulate;
      final built = await _controller?.buildRoute(
        waypoints: [origin ?? _fallbackOrigin, _destination!],
        options: _options,
      );
      if (!mounted) return;
      if (built != true) {
        setState(() => _buildingRoute = false);
        _snack('Không tạo được tuyến.');
        return;
      }
    }

    await _controller?.startNavigation(options: _options);
    if (_simulate) {
      await _controller?.setSpeedMultiplier(_speedMultiplier);
    }
    if (!mounted) return;
    setState(() {
      _buildingRoute = false;
      _navigating = true;
    });
  }

  /// User tapped Stop.
  Future<void> _stop() => _exitNavigation();

  /// The route SDK reported we reached the destination — leave navigation the
  /// same way a manual stop does. Without this the app would sit in the driving
  /// camera (tilted, following) forever after arriving.
  Future<void> _onArrival() async {
    await _exitNavigation();
    if (mounted) _snack('Đã đến nơi.');
  }

  /// Tear down whichever mode is running and bring the camera back to the user.
  ///
  /// After `finishNavigation` the map is still in the tilted follow-camera it
  /// used while driving, so recentre to hand the user a plain north-up map at
  /// their position — "quay về vị trí ban đầu".
  Future<void> _exitNavigation() async {
    if (_exiting) return; // arrival + a Stop tap could both land here
    _exiting = true;
    final alert = context.read<AlertController>();
    final wasNavigating = _navigating;
    if (_navigating) {
      // Fire-and-forget: the native side still tears navigation down, but the
      // Future never completes, so awaiting it would strand everything below —
      // the bar would never switch back to Start and the camera would never
      // recenter.
      _fireAndForget(_controller?.finishNavigation());
    }
    if (_alertOnly) {
      await alert.stop();
    }
    if (!mounted) {
      _exiting = false;
      return;
    }
    setState(() {
      _navigating = false;
      _alertOnly = false;
      _routeBuilt = false;
    });
    // Without a route, recenter() follows the GPS position north-up.
    if (wasNavigating) _fireAndForget(_controller?.recenter());
    _exiting = false;
  }

  // ── Destination ─────────────────────────────────────────────────────────────

  /// Picking a destination now does everything up front — clear the old route,
  /// move the camera, and build the new route (which draws the line and the
  /// destination pin) — so the map is ready and pressing Start jumps straight
  /// into navigation instead of stopping to build a route first.
  Future<void> _selectDestination(SearchResult r) async {
    final coord = await VietmapSearch.place(r.refId);
    if (coord == null || !mounted) {
      _snack('Không lấy được toạ độ điểm đến.');
      return;
    }
    final dest = LatLng(coord[0], coord[1]);

    // Drop the previous route before drawing the new one (plugin API).
    await _controller?.clearRoute();
    if (!mounted) return;

    setState(() {
      _destination = dest;
      _destinationLabel = r.display;
      _routeBuilt = false;
      _buildingRoute = true;
    });
    _fireAndForget(_controller?.animateCamera(latLng: dest, zoom: 15.5));

    final origin = _currentLocation ?? await _resolveCurrentLocation();
    if (!mounted) return;
    _options.simulateRoute = _simulate;
    // The route line + destination waypoint pin are drawn by the SDK on success;
    // `onRouteBuilt` / `onRouteBuildFailed` flip _routeBuilt / _buildingRoute.
    final built = await _controller?.buildRoute(
      waypoints: [origin ?? _fallbackOrigin, dest],
      options: _options,
    );
    if (mounted && built != true) {
      setState(() => _buildingRoute = false);
      _snack('Không tạo được tuyến.');
    }
  }

  void _clearDestination() {
    setState(() {
      _destination = null;
      _destinationLabel = null;
      _routeBuilt = false;
    });
    _controller?.clearRoute();
  }

  // ── Location ────────────────────────────────────────────────────────────────

  Future<LatLng?> _resolveCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Dịch vụ vị trí đang tắt.');
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      _currentLocation = latLng;
      return latLng;
    } on TimeoutException {
      _snack('Hết thời gian chờ GPS. Thử lại ngoài trời hoặc đặt vị trí giả lập.');
      return null;
    } catch (e) {
      _snack('Không lấy được vị trí: $e');
      return null;
    }
  }

  /// Recenter the camera on the user.
  ///
  /// While driving this restores the SDK's course-following camera. Without a
  /// route the SDK follows the GPS position north-up, moving its own puck with
  /// every fix; a pan stops following and this button resumes it.
  Future<void> _recenter() async {
    if (!_navigating && !await _ensureLocationPermission()) return;
    _fireAndForget(_controller?.recenter());
  }

  /// Fire a plugin call without awaiting it.
  ///
  /// Several `MapNavigationViewController` methods — `animateCamera`,
  /// `moveCamera`, `overview` and `finishNavigation` — perform their work on
  /// iOS but never call the method-channel `result`, so their Future never
  /// completes. Awaiting one hangs everything after it (that is how Stop
  /// stalled), so anything that must run afterwards has to let these go
  /// unawaited. `recenter` goes through here too so older SDK builds, which
  /// never complete it either, cannot hang the caller.
  void _fireAndForget(Future<void>? future) {
    if (future != null) unawaited(future);
  }

  void _onProgress(RouteProgressEvent e) {
    // Fallback for arrival: not every build fires the onArrival callback in
    // simulation, but the progress event still flips this flag. _exitNavigation
    // is guarded so this and onArrival cannot both act.
    if (e.arrived == true && _navigating) {
      _onArrival();
      return;
    }
    final loc = e.snappedLocation;
    if (loc?.latitude == null || loc?.longitude == null) return;

    final double speedKmh;
    if (_simulate) {
      // The replayed route speed sits below 30 km/h on city streets, which can
      // never exceed a 50–80 limit — so speeding could never be exercised in
      // simulation. Feed a fixed base instead, scaled by the multiplier, so the
      // multiplier presets straddle the limit: 45 → 67 (1.5×) → 90 (2×) → 135.
      speedKmh = _simBaseSpeedKmh * _speedMultiplier;
    } else {
      // Real GPS: CurrentLocation.speed is CLLocation.speed — metres per second,
      // and -1 when iOS cannot determine it. Feeding that negative sentinel would
      // read as driving backwards.
      final ms = loc!.speed?.toDouble() ?? 0;
      speedKmh = ms <= 0 ? 0 : ms * 3.6;
    }

    context.read<AlertController>().injectLocation(
          lat: loc!.latitude!.toDouble(),
          lng: loc.longitude!.toDouble(),
          bearing: loc.bearing?.toDouble() ?? 0,
          speedKmh: speedKmh,
        );
  }

  // ── Sheets & dialogs ────────────────────────────────────────────────────────

  void _openMuteSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          const FractionallySizedBox(heightFactor: 0.85, child: MuteSheet()),
    );
  }

  Future<void> _openSettings() async {
    final alert = context.read<AlertController>();
    final result = await showDialog<SettingsResult>(
      context: context,
      builder: (_) => SettingsDialog(
        vehicle: alert.vehicle,
        simulate: _simulate,
        speedMultiplier: _speedMultiplier,
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _simulate = result.simulate;
      _speedMultiplier = result.speedMultiplier;
    });
    _options.simulateRoute = result.simulate;

    // Re-configuring the vehicle rebuilds the native manager, so the next GPS
    // update refetches the zone for the new profile.
    await alert.applyVehicle(result.vehicle);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Deliberately NOT `context.watch<AlertController>()`: that rebuilt the whole
    // Stack — the platform-view map included — on every GPS tick, alert and voice
    // event (several per second), which is what made the screen feel heavy. This
    // build now only re-runs on local setState (start/stop/search — rare); the
    // pieces that track the engine (SignOverlay, SpeedChip, the status line
    // below) subscribe on their own and rebuild in isolation.
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          NavigationView(
            mapOptions: _options,
            onMapCreated: (c) => _controller = c,
            onRouteBuilt: (route) => setState(() {
              _routeBuilt = true;
              _buildingRoute = false;
            }),
            onRouteBuildFailed: (msg) {
              setState(() {
                _routeBuilt = false;
                _buildingRoute = false;
              });
              _snack('Tạo tuyến thất bại: $msg');
            },
            onRouteProgressChange: _onProgress,
            onArrival: _onArrival,
          ),

          // Sign column, top-left.
          Positioned(
            top: topInset + 96,
            left: 12,
            child: const SignOverlay(),
          ),

          // Speed + status, top-right — only meaningful once the engine runs.
          // Restriction signs sit under it.
          if (_running)
            Positioned(
              top: topInset + 96,
              right: 12,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SpeedChip(),
                  SizedBox(height: 8),
                  SizedBox(width: 200, child: RestrictionRow()),
                ],
              ),
            ),

          // Search, top-center. Hidden while driving, like the Android app.
          if (!_running)
            Positioned(
              top: topInset + 12,
              left: 12,
              right: 12,
              child: DestinationSearchBar(
                destinationLabel: _destinationLabel,
                onSelected: _selectDestination,
                onCleared: _clearDestination,
              ),
            ),

          Positioned(
            right: 16,
            bottom: bottomInset + 96,
            child: MapControlCluster(
              showSettings: !_running,
              showOverview: _routeBuilt,
              onSettings: _openSettings,
              onOverview: () => _controller?.overview(),
              onMute: _openMuteSheet,
              onRecenter: _recenter,
            ),
          ),

          Positioned(
            left: 16,
            right: 16,
            bottom: bottomInset + 12,
            // Only the engine-ready status inside the bar tracks the controller,
            // and `ready` changes just once per zone reload — so a Selector on it
            // keeps the per-tick storm away from this subtree entirely.
            child: Selector<AlertController, ReadyEvent?>(
              selector: (_, c) => c.ready,
              builder: (_, ready, _) => BottomActionBar(
                running: _running,
                busy: _buildingRoute,
                hasDestination: _destination != null,
                statusLine: _navigating
                    ? (_destinationLabel ?? 'Đang điều hướng')
                    : 'Cảnh báo tốc độ (GPS thật)',
                engineReady: ready?.isReady ?? false,
                engineStatus: ready == null
                    ? 'Đang tải dữ liệu vùng…'
                    : 'Sẵn sàng — ${ready.linkCount} links, ${ready.alertCount} alerts',
                onStart: _start,
                onStop: _stop,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
