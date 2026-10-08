## 1.0.0

Native SDK upgrade and package rename. See the README section
*Migrating from mapzone_flutter_alert_plugin 0.0.x*.

**Breaking**

* Package renamed `mapzone_flutter_alert_plugin` → `mapzone_speed_alert`
  (import `package:mapzone_speed_alert/mapzone_speed_alert.dart`; iOS pod
  `mapzone_speed_alert`; Android package `com.mapzone.mapzone_speed_alert`;
  channel `mapzone_speed_alert`).
* `VietmapAlertController` → `MapZoneSpeedAlert`, `VietmapAlertPlatform` →
  `MapZoneSpeedAlertPlatform`, `MethodChannelVietmapAlert` →
  `MethodChannelMapZoneSpeedAlert`.
* Voice: the SDK now plays alerts through its built-in player. Listening to
  `onVoice` silences it and forwards every clip to Dart, as before; cancelling
  every subscription hands playback back to the SDK.
* `getLinkCoords` is deprecated and always returns `null` (removed from the
  native SDK).

**Added**

* `onRestriction` stream + `RestrictionEvent`: no stopping / parking, closed
  road, vehicle ban and built-up-area signs with distances (`inBua` while
  inside). A new listener receives the current state immediately.
* `VoiceAlertType.noStopping` (19), `roadClosed` (20), `vehicleRestricted` (21).
* `setVoiceProfile(VoiceProfile.full | dingOnly)` and `setVoiceSpeed(double)`.
* `processExternalLocation(fixTimeMillis: …)` — the fix's own timestamp, used
  by the engine for voice throttling and stop detection (defaults to the time
  of the call).

**Changed**

* Native SDK: Android `mapzone_speed_alert_android` `2.0.6` (JitPack), iOS
  `MapZoneSpeedAlertSDK` `2.0.5` (CocoaPods).
* `initialize` / `configureVehicle` reset and re-configure the native engine
  (no new Android manager; iOS rebuilds its thin manager so restriction signs
  are re-announced). Mute, voice profile and voice speed survive
  `configureVehicle`. Native callbacks are installed only by the Flutter engine
  that configures, so background engines no longer interfere.
* A non-https `baseUrl` completes `initialize` / `configureVehicle` with
  `PlatformException(CONFIGURE_FAILED)` on both platforms.
* Example app: restriction-sign row under the speed chip; the three new
  categories in the voice-mute sheet.

## 0.0.2

* Docs / metadata only — no API or behaviour change.
* Rebranded the package description, README and CHANGELOG to **MapZone Speed
  Alert SDK**; replaced the `vietmap` pub.dev topic with `mapzone`.

## 0.0.1

* Initial release of `mapzone_flutter_alert_plugin`.
* Wraps the MapZone Speed Alert SDK, resolved from the published native
  packages: Android `com.github.mapzone-global:mapzone_speed_alert_android:2.0.1`
  (JitPack) and iOS `MapZoneSpeedAlertSDK` `2.0.1` (CocoaPods).
* Two GPS modes: **standalone** (the plugin captures native GPS and drives the
  engine) and **injected** (feed snapped GPS via `processExternalLocation()` for
  navigation integration).
* Event streams: `onAlert` (speed-limit / next-sign / camera / toll signs +
  distances + speed status), `onVoice` (WAV bytes + trigger + priority),
  `onReady`, `onResult` (errors), `onLocation`.
* Sign images are delivered as PNG bytes with native change-detection caching.
* Per-category voice muting: `setMutedAlertTypes(List<VoiceAlertType>)` + the
  `VoiceAlertType` enum, on **both Android and iOS**. Muting a camera / toll
  category also hides its on-screen sign; speed-limit and speeding cues can never
  be muted.
* Utilities: `updateZoneLocation(lat, lng)` (zone warm-up) and
  `getLinkCoords(linkId)` (Android-only matched-link polyline).
* `AlertConfig` reads the app's own bundle id / package name natively — no
  `bundleId` field to pass.
* Example app: a single map screen with destination search (autocomplete /
  place v4), simulated navigation, a speed-limit / camera / toll sign HUD, a
  speed chip, per-category voice muting, and a vehicle-profile / simulation
  settings dialog.
