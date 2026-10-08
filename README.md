# mapzone_speed_alert

Flutter plugin for the **MapZone Speed Alert SDK**. It delivers real-time
speed-limit signs, over-speed status, upcoming signs, speed-camera and toll-gate
alerts, road-restriction signs, and voice warnings — for Android and iOS — behind a single Dart API.

The plugin wraps the native Speed Alert engine, pulled automatically from the
published native packages:

- **Android:** `com.github.mapzone-global:mapzone_speed_alert_android:2.0.6` (JitPack)
- **iOS:** `MapZoneSpeedAlertSDK` `2.0.5` (CocoaPods)

> Upgrading from `mapzone_flutter_alert_plugin` 0.0.x? See
> [Migrating from 0.0.x](#migrating-from-mapzone_flutter_alert_plugin-00x).

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Android Setup](#android-setup)
- [iOS Setup](#ios-setup)
- [Quick Start](#quick-start)
- [GPS modes](#gps-modes)
- [Voice playback](#voice-playback)
- [Muting voice categories](#muting-voice-categories)
- [Road-restriction signs](#road-restriction-signs)
- [Vehicle types](#vehicle-types)
- [Error codes](#error-codes)
- [API Reference](#api-reference)
- [Migrating from 0.0.x](#migrating-from-mapzone_flutter_alert_plugin-00x)
- [Example](#example)
- [License](#license)

## Features

- 🚦 Current speed-limit sign + compliance status (compliant / approaching / exceeding)
- ⏭️ Next sign, speed camera and toll gate with distance-to-go
- 🚫 Road-restriction signs: no stopping / parking, closed road, vehicle ban,
  built-up area (`onRestriction`)
- 🔊 Voice alerts played by the SDK's built-in player — or, while you listen to
  `onVoice`, WAV clips forwarded to Flutter with trigger + priority
- 🗣️ Full spoken phrases or short ding tones (`setVoiceProfile`), adjustable
  playback speed (`setVoiceSpeed`)
- 🔇 Per-category voice muting (`setMutedAlertTypes`); muting a camera / toll
  category also hides its on-screen sign
- 📍 Two GPS modes:
  - **Standalone:** the plugin captures native GPS and drives the engine
  - **Injected:** feed navigation-snapped GPS via `processExternalLocation()`
- 🖼️ Sign images delivered as PNG bytes with native change-detection caching
  (no re-encoding every frame)

## Requirements

| Platform | Minimum |
|----------|---------|
| Android  | `minSdk 24`, JitPack repository (see [Android Setup](#android-setup)) |
| iOS      | `iOS 14.0` (raise to 15.0 if your app also uses a navigation SDK that requires it) |

## Installation

Add the plugin to your app:

```bash
flutter pub add mapzone_speed_alert
```

The native Speed Alert SDK (Android 2.0.6 / iOS 2.0.5) is declared by the plugin and resolved
automatically — you do **not** build it yourself. You only need to make the two
package hosts reachable from your app (below).

## Android Setup

The Android SDK is hosted on JitPack, so your app must declare that repository.
In modern Gradle the repository has to be added by the **app**, not the plugin —
add it to your `android/settings.gradle` (or `android/build.gradle`):

```kotlin
// android/settings.gradle(.kts) — inside dependencyResolutionManagement { repositories { … } }
maven { url = uri("https://jitpack.io") }
```

Permissions are already declared by the plugin (listed here for reference):
`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `INTERNET`,
`ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_LOCATION`.

The SDK authenticates with the **installed** `applicationId`, including any
`applicationIdSuffix` or flavor suffix (e.g. `com.foo.debug`). The auth server
accepts only the exact id registered for the API key, so build variants with a
different id fail with error `2003`.

## iOS Setup

The iOS SDK is a published CocoaPods pod, so a plain `pod install` resolves it —
no extra source needed.

Add the location usage descriptions to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to provide real-time speed alerts.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Keeps speed alerts running while you drive.</string>
<key>UIBackgroundModes</key>
<array><string>location</string></array>
```

Set the app deployment target to **14.0** in `ios/Podfile`:

```ruby
platform :ios, '14.0'
```

## Quick Start

```dart
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

final alert = MapZoneSpeedAlert.instance;

// 1. Configure the engine. The app's own bundle id / applicationId is read
//    natively and must match the id registered for the API key.
//    A non-https baseUrl throws PlatformException(CONFIGURE_FAILED).
await alert.initialize(const AlertConfig(
  baseUrl: 'https://driving.map.zone',
  apiKeyId: 'YOUR_API_KEY_ID',
  apiKey: 'YOUR_API_KEY',
  vehicleId: 'YOUR_VEHICLE_ID',
  vehicleType: VehicleType.car, // car=1, motorcycle=2, truck=3, … emergency=9
  seats: 4,
  weight: 1500, // kg (int)
));

// 2. Listen to the alert streams.
alert.onReady.listen((r) => print('ready: ${r.linkCount} links'));
alert.onAlert.listen((e) {
  // e.currentSpeedLimitSign is Uint8List? PNG -> Image.memory(...)
  // e.speedStatus, e.nextDistanceMeters, e.cameraDistanceMeters, e.tollDistanceMeters
});
alert.onRestriction.listen((r) {
  // r.stop / r.closed / r.vehicle / r.bua are Uint8List? PNGs (+ distances)
});
// Voice is spoken by the SDK. To play it yourself instead, listen to onVoice:
// alert.onVoice.listen((v) => playWav(v.wav, v.priority));
alert.onResult.listen((r) { if (!r.success) print('error ${r.errorCode}'); });
alert.onLocation.listen((l) => print('${l.speedKmh} km/h'));

// 3. Standalone mode — native GPS capture.
if (await alert.requestLocationPermissions()) {
  await alert.start();
}

// 4. Tear down.
await alert.stop();
await alert.reset();
```

Register `alert.registerLifecycleObserver()` once to forward
background/foreground transitions to the engine.

## GPS modes

The engine needs a stream of GPS positions. There are two ways to provide them:

- **Standalone** — call `start()` and the plugin captures native GPS itself.
  Best when the alert engine is the only thing that needs location.
- **Injected** — feed positions yourself with `processExternalLocation()`. Use
  this to reuse the snapped location from a navigation SDK so the alert and the
  map agree:

  ```dart
  await alert.processExternalLocation(
    lat: 21.02, lng: 105.83, bearing: 90, speedKmh: 45,
    fixTimeMillis: fix.timestampMs, // the fix's own time, epoch ms
  );
  ```

  Pass the fix's own timestamp: the engine times voice throttling and
  stop detection against it. When omitted, the time of the call is used.

## Voice playback

By default the SDK speaks alerts itself through its built-in player — no audio
code needed.

To play clips yourself (e.g. to mix them with navigation audio), listen to
`onVoice`. While that stream has a listener the built-in player is silent and
every clip arrives as a `VoiceEvent` (WAV PCM16 mono 22,050 Hz + trigger +
priority). Cancel every subscription to hand playback back to the SDK; clips
already queued in the built-in player may still finish.

```dart
await alert.setVoiceProfile(VoiceProfile.dingOnly); // chimes instead of speech
await alert.setVoiceSpeed(1.25); // built-in player only; 0.5..2.0
```

## Muting voice categories

`setMutedAlertTypes` silences specific `VoiceAlertType` categories (speed camera,
toll, red-light camera, no-overtaking, no-stopping, road closed, rest station,
…). Muting a **camera or toll** category also hides its on-screen sign; muting
any other category only silences the voice (restriction signs keep showing on
`onRestriction`). Core speed-limit and speeding cues can never be
muted — they are safety cues and are always announced.

```dart
await alert.setMutedAlertTypes([VoiceAlertType.speedCamera, VoiceAlertType.toll]);
await alert.setMutedAlertTypes([]); // re-enable all
```

## Road-restriction signs

`onRestriction` emits a `RestrictionEvent` holding every restriction slot at
once — the slots are independent and can co-occur:

| Slot | Sign | Distance |
|------|------|----------|
| `stop` | No parking / no stopping | `stopDistMeters` |
| `closed` | Road closed | `closedDistMeters` |
| `vehicle` | Road closed to the configured vehicle type | `vehicleDistMeters` |
| `bua` | Built-up area entry / end (landscape artwork) | `buaDistMeters`; `inBua` while inside |

A distance of `0` means the vehicle is on that stretch now; an empty slot has a
`null` image. Events arrive when a slot changes, and a new listener immediately
receives the current state.

## Vehicle types

`VehicleType` codes match the native SDK enum:

`car=1, motorcycle=2, truck=3, coach=4, bus=5, taxi=6, bicycle=7, pedestrian=8, emergency=9`.

Only some types support speed alerts; an unsupported type is reported through
`onResult` with error code `3003`.

## Error codes

`AlertResult.errorCode`:

`0` success · `1001` invalid parameter (e.g. coordinates out of bounds) ·
`2003` unauthorized (expired key, bundle id / vehicle out of scope) ·
`3003` unsupported vehicle type · `-1` response could not be verified ·
`-2` payload unusable · `-3` secure session failed · `-4` server unreachable ·
`-5` native bridge failed (e.g. rejected configuration, missing ABI).
`errorMessage` is an English sentence derived from the code — localise off the
code.

## API Reference

| Method | Description |
|--------|-------------|
| `initialize(AlertConfig)` | Configure the native engine |
| `configureVehicle(...)` | Re-configure with a new vehicle profile (mute / voice profile kept) |
| `start()` / `stop()` | Native GPS capture on / off (standalone mode) |
| `processExternalLocation(..., fixTimeMillis)` | Inject a GPS frame (injected mode) |
| `updateZoneLocation(lat, lng)` | Lightweight zone-cache warm-up |
| `setMutedAlertTypes(List<VoiceAlertType>)` | Mute voice per category |
| `setVoiceProfile(VoiceProfile)` | Full phrases or ding tones |
| `setVoiceSpeed(double)` | Built-in player speed |
| `getLinkCoords(linkId)` | **Deprecated** — removed from the native SDK, always `null` |
| `reset()` | Free native memory |
| `requestLocationPermissions()` / `hasLocationPermissions()` | Runtime permissions |
| `registerLifecycleObserver()` / `unregisterLifecycleObserver()` | App lifecycle forwarding |

**Event streams**

| Stream | Payload |
|--------|---------|
| `onAlert` | Speed-limit / next-sign / camera / toll signs (PNG) + distances + speed status |
| `onVoice` | Voice clip: WAV bytes + trigger + priority (listening silences the built-in player) |
| `onRestriction` | Restriction signs (PNG) + distances + `inBua` |
| `onReady` | Zone loaded: `linkCount`, `alertCount` |
| `onResult` | Success flag + `errorCode` + message |
| `onLocation` | Current `latitude` / `longitude` / `speedKmh` / `bearing` |

## Example

See [`example/`](example/) for a single-screen demo app: a map screen with a
**destination search box** (autocomplete / place **v4**). Pick a destination →
the route is built and drawn → start simulated navigation; the snapped GPS is
fed into the engine via
`processExternalLocation`, the speed-limit / camera / toll signs render as a HUD,
a speed chip shows the over-speed status with the restriction signs under it,
and a floating button configures voice
muting per `VoiceAlertType`. Vehicle profile and route simulation are set from a
settings dialog.

> The route / map is drawn by the example's own navigation SDK — this alert
> plugin does not render maps; it only consumes GPS and emits sign / voice
> events.

Fill your Speed Alert credentials (and the map API key) in
`example/lib/env.dart` before running.

## Migrating from mapzone_flutter_alert_plugin 0.0.x

1. `pubspec.yaml`: replace `mapzone_flutter_alert_plugin` with
   `mapzone_speed_alert: ^1.0.0`.
2. Imports: `package:mapzone_speed_alert/mapzone_speed_alert.dart`.
3. Rename `VietmapAlertController` → `MapZoneSpeedAlert` (and
   `VietmapAlertPlatform` → `MapZoneSpeedAlertPlatform` if you mock it).
4. iOS: `cd ios && pod install` (the pod is now `mapzone_speed_alert` and pulls
   `MapZoneSpeedAlertSDK` 2.0.5).
5. **Voice:** the SDK now speaks alerts by itself. If your app plays `onVoice`
   clips it keeps working — listening silences the built-in player. If you
   listened to `onVoice` without playing, remove the listener to hear the SDK.
6. `getLinkCoords` always returns `null` now (removed from the native SDK).
7. Optionally pass `fixTimeMillis` to `processExternalLocation`.

## License

MIT — see [LICENSE](LICENSE).
