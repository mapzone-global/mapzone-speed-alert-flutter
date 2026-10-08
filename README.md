# mapzone_speed_alert

Speed-limit, camera, toll and road-restriction alerts with voice **around the
vehicle's position**, for Flutter apps on Android and iOS — no route needed.

The plugin loads road data for the zone the vehicle is in, matches each GPS fix
to the road, and returns ready-to-draw sign images plus voice alerts. GPS comes
either from the plugin itself or from your own navigation SDK.

## Requirements

| | Minimum |
|---|---|
| Flutter | 3.32 |
| Dart | 3.8 |
| Android | `minSdk` 24, compiled against SDK 36 |
| iOS | 14.0 |
| Network | Internet access to the alert service |

The plugin pulls the native engine automatically:
Android `com.github.mapzone-global:mapzone_speed_alert_android:2.0.6` (JitPack),
iOS `MapZoneSpeedAlertSDK` `2.0.5` (CocoaPods).

The plugin does **not** draw a map. In mode A it captures GPS and can request
location permission for you; in mode B your app owns GPS and permissions.

## Getting an integration key

Contact MapZone on [MapZone](https://zalo.me/3189066936017422854) — and provide:

- the **application id** of every build that will call the service
  (Android package name / iOS bundle id), including debug or flavour ids such
  as `com.example.app.debug` if you run them;
- the kind of vehicles you will configure (see [Vehicle types](#vehicle-types)).

You will receive the `apiKeyId` and `apiKey` used in
[`AlertConfig`](#alertconfig).

### Application id

The service authenticates your app by its **exact** application id, resolved
natively — you do not pass it in Dart. On Android this is the installed
`applicationId` including any `applicationIdSuffix` or flavour suffix; on iOS it
is `CFBundleIdentifier`. A build whose id is not registered for the key is
rejected with error [`2003`](#error-codes). Either register that id as well, or
run the build whose id is registered.

Keep `apiKey` out of source control (e.g. a git-ignored Dart file,
`--dart-define`, or your secrets pipeline).

## Installation

```yaml
dependencies:
  mapzone_speed_alert: ^1.0.0
```

### Android

The native SDK is hosted on JitPack, and Gradle resolves it with **your app's**
repositories, so JitPack must be declared in the app project.

If your project declares repositories in `android/build.gradle.kts`:

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}
```

If it uses `dependencyResolutionManagement` in `android/settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}
```

Ensure `minSdk` is at least 24. The plugin's manifest already declares the
permissions it needs, merged into your app automatically:
`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `INTERNET`,
`ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_LOCATION`.

### iOS

Set the platform to iOS 14.0 or later in `ios/Podfile` (raise it to 15.0 if
another SDK in your app, such as a navigation SDK, requires it), then:

```sh
cd ios && pod install
```

The `MapZoneSpeedAlertSDK` pod is resolved automatically. Add the location
usage descriptions to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Your location is used to show speed limits and road alerts.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Keeps speed alerts running while you drive.</string>
<key>UIBackgroundModes</key>
<array><string>location</string></array>
```

## Integration guide

### 1. Initialize once

```dart
import 'dart:async';

import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

final alert = MapZoneSpeedAlert.instance;

await alert.initialize(const AlertConfig(
  baseUrl: 'https://driving.map.zone',
  apiKeyId: 'your-api-key-id',        // from MapZone
  apiKey: 'your-api-key',             // from MapZone
  vehicleId: 'your-vehicle-id',       // your own identifier for this vehicle
  vehicleType: VehicleType.car,       // see "Vehicle types"
  seats: 4,
  weight: 1500,                       // kg
));
```

`initialize` throws `PlatformException(CONFIGURE_FAILED)` when the native SDK
rejects the configuration, for example a non-https `baseUrl`. Use
`configureVehicle(...)` to change the vehicle profile later.

### 2. Listen to the streams

Subscribe before feeding GPS so the first event is not missed.

```dart
final subs = <StreamSubscription<Object>>[
  alert.onAlert.listen((e) => setState(() => _alert = e)),
  alert.onRestriction.listen((e) => setState(() => _restriction = e)),
  alert.onReady.listen((r) => debugPrint('zone ready: ${r.linkCount} links')),
  alert.onResult.listen((r) {
    if (!r.success) debugPrint('alert ${r.errorCode}: ${r.errorMessage}');
  }),
];
```

Listen to `onVoice` only if you play clips yourself — see
[Voice alerts](#voice-alerts).

### 3. Provide GPS

Pick **one** mode.

**Mode A — standalone.** The plugin captures native GPS. Best when the alert
engine is the only thing that needs location.

```dart
if (await alert.requestLocationPermissions()) {
  await alert.start();
}
alert.onLocation.listen((l) => debugPrint('${l.speedKmh} km/h'));
```

**Mode B — injected.** Feed positions yourself, about once per second. Use this
to reuse the snapped location from a navigation SDK so the alerts and the map
agree.

```dart
await alert.processExternalLocation(
  lat: pos.latitude,
  lng: pos.longitude,
  bearing: pos.heading,
  speedKmh: pos.speed < 0 ? 0 : pos.speed * 3.6,  // m/s → km/h; iOS reports -1 when unknown
  accuracy: pos.accuracy,
  fixTimeMillis: pos.timestamp.millisecondsSinceEpoch,
);
```

Pass the fix's own timestamp: the engine times voice throttling and stop
detection against it. When omitted, the time of the call is used.

### 4. Stop

```dart
await alert.stop();                  // mode A: stop native GPS, engine state kept
await alert.reset();                 // free native memory, unconfigure the engine
for (final s in subs) { await s.cancel(); }
```

`reset()` also stops native GPS and unconfigures the engine: call
`initialize` again before `start()` or `processExternalLocation`, which are
otherwise rejected or ignored.

### Drawing signs

Every image is PNG bytes; `null` means the slot is empty. Unchanged images are
not re-sent by the native side — each event still carries the full current
state, so you can render the latest event directly. Use `gaplessPlayback` to
avoid flicker:

```dart
Widget sign(Uint8List? png, {double size = 64}) => png == null
    ? const SizedBox.shrink()
    : Image.memory(png, width: size, height: size, gaplessPlayback: true);

Row(children: [
  sign(_alert?.currentSpeedLimitSign, size: 80),
  sign(_alert?.nextSign),
  if (_alert?.nextDistanceMeters != null) Text('${_alert!.nextDistanceMeters} m'),
  sign(_alert?.cameraSign),
  sign(_alert?.tollSign),
]);
```

Use `speedStatus` to colour your own speedometer — `compliant`, `approaching`
or `exceeding`.

## Configuration reference

### AlertConfig

| Field | Type | Required | Description |
|---|---|---|---|
| `baseUrl` | `String` | yes | Service base URL, must be `https`, e.g. `https://driving.map.zone`. |
| `apiKeyId` | `String` | yes | API key id issued for your application id. |
| `apiKey` | `String` | yes | API key secret. |
| `vehicleId` | `String` | yes | Your identifier for the vehicle. |
| `vehicleType` | `VehicleType` | no | Vehicle class, default `VehicleType.car`. |
| `seats` | `int` | no | Number of seats, default `4`. |
| `weight` | `int` | no | Vehicle weight in **kilograms**, default `1500`. |

There is no bundle-id field — see [Application id](#application-id).

### Vehicle types

| `VehicleType` | Code |
|---|---|
| `car` | 1 |
| `motorcycle` | 2 |
| `truck` | 3 |
| `coach` | 4 |
| `bus` | 5 |
| `taxi` | 6 |
| `bicycle` | 7 |
| `pedestrian` | 8 |
| `emergency` | 9 |

The type, seats and weight decide which speed limits apply. Not every type
supports speed alerts; an unsupported type is reported on `onResult` with
error [`3003`](#error-codes).

### processExternalLocation

| Parameter | Unit | Notes |
|---|---|---|
| `lat`, `lng` | degrees (WGS84) | Required. |
| `bearing` | degrees | Required. `0` = north, `90` = east. |
| `speedKmh` | km/h | Required. Never negative. |
| `accuracy` | m | Horizontal accuracy; default `0`. |
| `fixTimeMillis` | ms since epoch (UTC) | The fix's own time; defaults to the time of the call. |

## API reference

All members are on `MapZoneSpeedAlert.instance`.

### Methods

| Method | Description |
|---|---|
| `initialize(AlertConfig)` | Credentials + vehicle profile. Call once before providing GPS. |
| `configureVehicle({vehicleType, seats, weight})` | Change the vehicle profile at runtime; mute and voice settings are kept. |
| `start()` / `stop()` | Mode A: native GPS capture on / off. `stop` keeps engine state. |
| `processExternalLocation(...)` | Mode B: feed one GPS fix (~1 Hz). |
| `updateZoneLocation(lat, lng)` | Lightweight zone-cache warm-up for a position. |
| `reset()` | Stop native GPS, free native memory and unconfigure the engine; call `initialize` again before reuse. |
| `setMutedAlertTypes(List<VoiceAlertType>)` | Mute voice categories; empty list = announce everything. |
| `setVoiceProfile(VoiceProfile)` | `full` phrases or `dingOnly` chimes. |
| `setVoiceSpeed(double)` | Built-in player speed, `1.0` = recorded, clamped to `0.5..2.0`, pitch kept. No effect while `onVoice` has a listener. Persists across `reset()`. |
| `requestLocationPermissions()` / `hasLocationPermissions()` | Runtime location permission (mode A). |
| `registerLifecycleObserver()` / `unregisterLifecycleObserver()` | Send app background / foreground to the native side. Reserved: the current native SDK ignores them. Safe to call more than once. |
| `getLinkCoords(linkId)` | **Deprecated** — removed from the native SDK, always returns `null`. |

### Streams

| Stream | Payload | When |
|---|---|---|
| `onAlert` | `AlertEvent` | Once per processed GPS fix. |
| `onRestriction` | `RestrictionEvent` | When a slot changes; a new listener immediately receives the current state. |
| `onVoice` | `VoiceEvent` | Per clip, **only while listened to** — the built-in player is silent for that time. |
| `onReady` | `ReadyEvent` | Zone data loaded for the current area. |
| `onResult` | `AlertResult` | Outcome of each zone load, and native failures. |
| `onLocation` | `AlertLocation` | Each native GPS fix (mode A). |

Distances are in metres. A distance of `0` means "currently on it".

#### AlertEvent

| Field | Type | Description |
|---|---|---|
| `currentSpeedLimitSign` | `Uint8List?` | Current speed-limit sign; `null` when none applies. |
| `speedStatus` | `SpeedStatus` | `compliant`, `approaching` (close to the limit) or `exceeding`. |
| `nextSign` / `nextDistanceMeters` | `Uint8List?` / `int?` | Next speed-limit sign ahead and its distance. |
| `cameraSign` / `cameraDistanceMeters` | `Uint8List?` / `int?` | Upcoming speed camera. |
| `tollSign` / `tollDistanceMeters` | `Uint8List?` / `int?` | Upcoming toll gate. |

#### RestrictionEvent

The slots are independent: one stretch of road can be in a built-up area,
closed to your vehicle and no-stopping at once.

| Field | Type | Description |
|---|---|---|
| `stop` / `stopDistMeters` | `Uint8List?` / `int` | No-parking / no-stopping sign. |
| `closed` / `closedDistMeters` | `Uint8List?` / `int` | Road-closed sign. |
| `vehicle` / `vehicleDistMeters` | `Uint8List?` / `int` | Road closed to the configured vehicle type. |
| `bua` / `buaDistMeters` | `Uint8List?` / `int` | Built-up-area sign: the entry sign while inside, then the end-of-area sign after leaving. Landscape artwork, not a circle. |
| `inBua` | `bool` | Whether the vehicle is inside a built-up area. |

#### VoiceEvent

| Field | Type | Description |
|---|---|---|
| `wav` | `Uint8List` | WAV clip, PCM 16-bit mono 22050 Hz. |
| `trigger` | `int` | Native trigger code of the announcement (see `VoiceAlertType.trigger`). |
| `priority` | `int` | `0` current speed (lowest), `1` normal, `2` speeding. |

#### ReadyEvent, AlertResult and AlertLocation

`ReadyEvent`: `isReady`, `linkCount` (road links loaded), `alertCount` (cameras,
tolls and sign changes loaded).

`AlertResult`: `success`, `errorCode`, `errorMessage` — see
[Error codes](#error-codes). `isNetworkError` is `true` for negative codes.

`AlertLocation`: `latitude`, `longitude`, `speedKmh`, `bearing`, and optional
`accuracy` (m) and `timestamp` (ms since epoch).

## Voice alerts

### Built-in player or your own

By default the native SDK speaks alerts through its built-in player — nothing
to do. To play clips yourself (mixing with navigation audio, custom ducking…),
listen to `onVoice`:

```dart
final voiceSub = alert.onVoice.listen((v) => myPlayer.play(v.wav, v.priority));
// Later: cancel every onVoice subscription to hand playback back to the SDK.
await voiceSub.cancel();
```

Use `priority` to decide whether a new clip interrupts the current one. Clips
already queued in the built-in player may still finish after you subscribe.

### Voice profile

```dart
await alert.setVoiceProfile(VoiceProfile.dingOnly);
```

- `VoiceProfile.full` (default): full spoken Vietnamese phrases.
- `VoiceProfile.dingOnly`: one chime for every camera kind and for
  no-parking / no-stopping, a distinct chime for speeding, silence for
  everything else.

On-screen signs are identical in both profiles, and muted categories stay
silent in both.

### Muting categories

```dart
await alert.setMutedAlertTypes([VoiceAlertType.toll, VoiceAlertType.noParking]);
await alert.setMutedAlertTypes([]);  // announce everything again
```

- Speed-limit and speeding announcements **cannot** be muted.
- Muting a camera or toll category **also hides its sign** — there is a single
  slot for each.
- Muting a restriction category silences the voice only; the sign still shows
  on `onRestriction`.

| `VoiceAlertType` | Code | Muting also hides the sign |
|---|---|---|
| `speedCamera` | 3 | yes |
| `toll` | 4 | yes |
| `trafficEnforcementCamera` | 6 | yes |
| `redLightCamera` | 7 | yes |
| `aiCamera` | 8 | yes |
| `noLeftTurn`, `noRightTurn`, `noUTurn`, `noStraight` | 9, 10, 11, 15 | no |
| `noOvertaking`, `noOvertakingEnd` | 12, 13 | no |
| `noParking`, `noStopping` | 14, 19 | no |
| `buildUpAreaStart`, `buildUpAreaEnd` | 16, 17 | no |
| `restStation` | 18 | no |
| `roadClosed` | 20 | no |
| `vehicleRestricted` | 21 | no |

## Error codes

Reported in `AlertResult.errorCode`. `errorMessage` is an English sentence
derived from the code — localise off the code.

| Code | Meaning | What to check |
|---|---|---|
| `0` | Success | |
| `1001` | Invalid parameter | Coordinates out of bounds or other bad input. |
| `2003` | Unauthorized | Key expired, or application id / vehicle not in the key's scope — see [Application id](#application-id). |
| `3003` | Unsupported vehicle type | `AlertConfig.vehicleType`. |
| `-1` | Response could not be verified | Retry; contact MapZone if it persists. |
| `-2` | Payload unusable | Retry; contact MapZone if it persists. |
| `-3` | Secure session failed | Retry; contact MapZone if it persists. |
| `-4` | Server unreachable | Network connection and `baseUrl`. |
| `-5` | Native bridge failed | Rejected configuration or missing native ABI. |

## Example app

[`example/`](example) is a single-screen demo built on
`vietmap_flutter_navigation` that shows both GPS modes:

- **No destination — mode A:** `start()` captures raw GPS, no route.
- **Destination picked — mode B:** search a destination, build and draw the
  route, then drive it (simulated by default; toggle in the settings dialog).
  The snapped GPS is fed in with `processExternalLocation`.

Speed-limit, camera and toll signs render as a HUD, a speed chip shows the
speed status with the restriction signs under it, and a floating button mutes
voice categories. The example plays voice clips itself by listening to
`onVoice` (priority queue on `audioplayers`, see
[`example/lib/voice_queue.dart`](example/lib/voice_queue.dart)). The vehicle
profile is set from the settings dialog.

Fill your Speed Alert credentials and the map API key in
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

## Support

- Integration key and commercial questions: [MapZone](https://zalo.me/3189066936017422854)
- Bugs and feature requests:
  [GitHub issues](https://github.com/mapzone-global/mapzone-speed-alert-flutter/issues)

## License

MIT — see [LICENSE](LICENSE).
