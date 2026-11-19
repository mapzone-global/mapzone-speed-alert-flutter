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
Android `com.github.mapzone-global:mapzone_speed_alert_android:3.0.1` (JitPack),
iOS `MapZoneSpeedAlertSDK` `3.0.1` (CocoaPods).

> **Upgrading from 1.0.x?** 2.0.0 signs a user in (`identity` replaces
> `vehicleId`), changes the vehicle-type numbers and takes the weight in
> tonnes. See [Migrating from 1.0.x to 2.0.0](#migrating-from-10x-to-200).

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
  mapzone_speed_alert: ^2.0.0
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

### 1. Initialize — signs the user in

```dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

final alert = MapZoneSpeedAlert.instance;

try {
  await alert.initialize(AlertConfig(
    baseUrl: 'https://driving.map.zone',
    apiKeyId: 'your-api-key-id',          // from MapZone
    apiKey: 'your-api-key',               // from MapZone
    identity: signedInUser.phoneNumber,   // who is signed in — see "Identity"
    vehicleType: VehicleType.car,         // see "Vehicle types"
    seats: 4,
    weightTons: 1.5,                      // TONNES
    metadata: {'appVersion': '1.4.0'},    // optional
  ));
} on PlatformException catch (e) {
  // INVALID_CONFIGURATION: an input was rejected (e.message says which);
  // nothing was applied — the previous configuration, zone and signs stay.
  // CONFIGURE_FAILED: non-https baseUrl.
}
```

Call `initialize` when the user signs in **and on every app launch** with a
user already signed in — the SDK does not remember the identity across
launches. Signing in then runs in the background; its failures arrive on
`onResult`. Use `configureVehicle(...)` to change the vehicle profile later
(same identity), and `logout()` when the user signs out — see
[Sessions](#sessions-sign-in-and-sign-out).

#### Identity

Whoever is signed in on this device, sent verbatim — typically the account's
phone number in `+84…` form. Pick one format and keep it: `"0901234567"` and
`"+84901234567"` are two different users. Non-empty, at most 128 characters, no
`"` and no control characters.

#### Metadata

Your own information about this device / user (app version, internal user id,
…), stored with the session when it **opens** — not sent with every request.
Agree the key names with Vietmap; the SDK adds `"model"` and `"os"` unless you
set them. One JSON object, at most 2048 UTF-8 bytes, nesting depth at most 16.
Re-initializing with the same identity keeps the metadata stored at sign-in; to
record new metadata the user has to sign out and in again.

### 2. Listen to the streams

Subscribe before feeding GPS so the first event is not missed.

```dart
final subs = <StreamSubscription<Object>>[
  alert.onAlert.listen((e) => setState(() => _alert = e)),
  alert.onRestriction.listen((e) => setState(() => _restriction = e)),
  alert.onReady.listen((r) => debugPrint('zone ready: ${r.linkCount} links')),
  alert.onResult.listen((r) {
    if (r.errorCode == MapZoneErrorCode.sessionMoved) {
      // Signed in on another device: sign out here and ask to sign in again.
      alert.logout();
      showSignedInElsewhereDialog();
    } else if (!r.success) {
      debugPrint('alert ${r.errorCode}: ${r.errorMessage}');
    }
  }),
];
```

Draw a vehicle marker from `onSnappedLocation` if you show a map: each matched
fix, moved onto the road, with the road bearing.

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

Where the fixes come from:

- **Android:** Google's Fused Location (GPS + Wi-Fi + cell, so it also works
  indoors) when Play Services is usable on the device. Without Play Services the
  OS `gps` and `network` providers run together; a network fix is used only
  once GPS has been silent for more than 5 seconds. The plugin depends on
  `play-services-location` 21.x for this (it is not required at runtime); a
  plugin in your app still built against 20.x or older conflicts with it.
  Grant precise location: with only approximate location the fixes are coarse,
  without speed or heading.
- **iOS:** CoreLocation through the SDK's `EnhancedLocationManager`.
- Android: when the device reports no heading, or the vehicle moves slower than
  1 m/s, the last heading is kept instead of sending `0` (north), so the engine
  does not snap the vehicle onto the opposite carriageway while stopped.

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
otherwise rejected or ignored. `reset()` does **not** sign the user out.

### 5. Sign out

```dart
final result = await alert.logout();
if (!result.success) {
  // e.g. offline: zone fetches already stopped; call logout() again later.
}
```

## Sessions (sign in and sign out)

```
initialize(identity) ──► signed in (the SDK logs in, in the background)
        │                    │ 2006 / 2007 / 2005 / … on onResult, once ──► zone fetches stop
        │                    │                                             (loaded zone keeps alerting)
        └── logout() ────────┴─► zone fetches stop at once ─► server logout ─► AlertResult(success)
```

- One identity is active on one device at a time. Signing the same identity in
  on another device moves the session there and this device receives `2006`
  (`MapZoneErrorCode.sessionMoved`): call `logout()` (treated as success) and
  send the user back to sign in.
- Switching to a **different** identity on the same device is allowed only 20
  minutes after this device last opened a session (`2008` otherwise).
- A sign-in that fails for network or server reasons does not stop alerts; the
  SDK retries it before a later zone fetch.
- After `logout()`, `configureVehicle` throws `NOT_INITIALIZED`: signing back in
  always goes through `initialize`.

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
| `identity` | `String` | yes | Who is signed in — see [Identity](#identity). |
| `vehicleType` | `VehicleType` | no | Vehicle class, default `VehicleType.car`. |
| `seats` | `int` | no | Number of seats, 0 or more, default `4`. |
| `weightTons` | `double` | no | Gross weight in **tonnes**, 0 or more, default `1.5`. |
| `metadata` | `Map<String, Object?>?` | no | Stored with the session — see [Metadata](#metadata). |

There is no bundle-id field — see [Application id](#application-id).

### Vehicle types

| `VehicleType` | Server code |
|---|---|
| `car` | 1 |
| `taxi` | 2 |
| `bus` | 3 |
| `coach` | 4 |
| `truck` | 5 |
| `motorcycle` | 7 |

`value` is the MapZone server's own code, sent unchanged. `VehicleType.fromValue`
returns `null` for a code it does not know. The type, seats and weight decide
which speed limits apply. The type must be enabled for your API key, otherwise
sign-in reports `1001` and zone requests [`3003`](#error-codes).

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
| `initialize(AlertConfig)` | Credentials, identity (signs in) and vehicle profile. Call before providing GPS, on every sign-in and app launch. |
| `configureVehicle({vehicleType, seats, weightTons})` | Change the vehicle profile at runtime, same identity; mute and voice settings are kept. Throws `NOT_INITIALIZED` after `logout()` until the next `initialize`. |
| `logout()` | Sign the identity out of this device; returns an `AlertResult`. |
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
| `onSnappedLocation` | `SnappedLocation` | Each processed fix that matched a road: `latitude`, `longitude` on the road, `bearingDegrees` of the road in the direction of travel. Computed only while listened to. |

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
[Error codes](#error-codes) and the `MapZoneErrorCode` constants.

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

Reported in `AlertResult.errorCode`, named in `MapZoneErrorCode`. `errorMessage`
is an English sentence derived from the code alone — localise off the code.
Whatever the code, the zone already loaded keeps alerting; what changes is
whether the SDK keeps fetching new zones. Codes that stop or pause fetching are
reported **once**. Branch on the exact code — ranges no longer have one meaning.

| Code | `MapZoneErrorCode` | Meaning | SDK |
|---|---|---|---|
| `0` | `success` | Zone data loaded / logged out | — |
| `2006` | `sessionMoved` | The identity is now in use on another device | Stops until `initialize` |
| `2007` | `locked` | Device or identity locked by an administrator | Stops until `initialize` |
| `2002` / `2003` / `2004` | `invalidSignature` / `apiKeyNotAccepted` / `applicationIdNotAccepted` | Signature, API key or application id not accepted — see [Application id](#application-id) | Stops until `initialize` |
| `2005` | `planExpired` | Service plan expired | Stops until `initialize` |
| `2010` | `trialIdentityNotAllowed` | Trial key: identity is not one of its sample identities | Stops until `initialize` |
| `3003` | `vehicleTypeNotAllowed` | Vehicle type not enabled for the API key | Stops until `initialize` |
| `3011` / `3012` | `enterprisePlanRequired` / `newDeviceLimit` | Device limit of the API key reached | Stops until `initialize` |
| `4001` | `requestQuotaExceeded` | Request quota used up | Stops until `initialize` |
| `1002` | `missingParameter` | Missing parameter | Stops until `initialize` |
| `1001` | `invalidRequest` | Sign-in: identity or vehicle rejected · Zone: request rejected (e.g. outside the served area) | Sign-in: stops · Zone: keeps going |
| `2008` | `switchTooSoon` | Account on this device changed too recently | Pauses 20 minutes, then resumes |
| `4000` / `5000` / `5004` / `2009` | `tooManyRequests` / `internalError` / `serviceStarting` / `tooManyNewSessions` | Server busy or failing | Backs off |
| `2000` | `deviceClockWrong` | Device clock is wrong | Keeps going |
| `-1` | `responseNotVerified` | Response could not be verified | Keeps going |
| `-2` | `mapDataInvalid` | Map data empty, malformed or unusable | Keeps going |
| `-3` | `secureSessionFailed` | Secure session could not be established; retried | Keeps going |
| `-4` | `serverUnreachable` | Server unreachable — check connectivity | Keeps going |
| `-5` / `-99` | `bridgeFailed` / `bridgeFailedLegacy` | Native bridge failed (e.g. library missing for this device's ABI) | — |
| `-6` | `notLoggedIn` | Nobody signed in (`logout` called, or `initialize` never was) | Stops until `initialize` |
| `-8` | `deviceNotReady` | Device cannot be read yet (e.g. iPhone not unlocked since restart); show a notice | Pauses, retries about once a minute |

In mode A a native location failure is also reported on `onResult` with code
`-1` (on Android: no location source left after `start()` succeeded; on iOS:
the location error text).

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
[`example/lib/voice_queue.dart`](example/lib/voice_queue.dart)). The identity,
vehicle profile and sign-out are in the settings dialog; a `2006` shows a
"signed in elsewhere" dialog.

Fill your Speed Alert credentials, an identity enabled for your key and the map
API key in `example/lib/env.dart` before running.

## Migrating from 1.0.x to 2.0.0

2.0.0 moves to native SDK 3.0.1 (Android `3.0.1`, iOS `3.0.1`). Callbacks,
streams, `processExternalLocation`, `start`/`stop`/`reset`, muting, voice
profile and voice speed are unchanged.

```
  1.0.x                                         2.0.0
  ─────                                         ─────
  AlertConfig(vehicleId:, weight: 1500 /*kg*/) ──► AlertConfig(identity:, weightTons: 1.5, metadata:)
  VehicleType.truck.value == 3                 ──► VehicleType.truck.value == 5 (server codes)
  configureVehicle(weight:)                    ──► configureVehicle(weightTons:)
  (no sign-out)                                ──► logout() on sign-out and after 2006
  isExpiredApiKey / isNetworkError             ──► exact codes, MapZoneErrorCode
```

1. `pubspec.yaml`: `mapzone_speed_alert: ^2.0.0`; iOS: `cd ios && pod update MapZoneSpeedAlertSDK`.
2. **`vehicleId` → `identity`.** Pass who is signed in on this device (see
   [Identity](#identity)), on every sign-in and every app launch. Do not reuse a
   vehicle id shared by several devices: they would sign each other out with
   `2006`.
3. **Weight in tonnes:** `weight: 1500` (kg) → `weightTons: 1.5`. The server has
   always read the number as tonnes.
4. **Vehicle types:** the enum names stay, the numbers are now the server's
   codes. If you stored the old number, convert it with this table — do **not**
   call `VehicleType.fromValue(oldNumber)` (`fromValue(3)` is now `bus`):

   | Vehicle | Old code (1.0.x) | 2.0.0 |
   |---|---|---|
   | Car | 1 | `VehicleType.car` (1) |
   | Motorcycle | 2 | `VehicleType.motorcycle` (7) |
   | Truck | 3 | `VehicleType.truck` (5) |
   | Coach | 4 | `VehicleType.coach` (4) |
   | Bus | 5 | `VehicleType.bus` (3) |
   | Taxi | 6 | `VehicleType.taxi` (2) |
   | Bicycle / pedestrian / emergency | 7 / 8 / 9 | removed — contact Vietmap |

   `fromValue` returns `null` for an unknown code (it fell back to `car`).
   Speed limits and alerts for non-car vehicles change after upgrading: 1.0.x
   sent the old numbers, which the server read as other vehicle types.
5. **Errors:** catch `PlatformException(INVALID_CONFIGURATION)` from
   `initialize` / `configureVehicle`. In `onResult`, branch on exact codes
   (`MapZoneErrorCode`); `isExpiredApiKey`, `codeExpiredApiKey`,
   `codeInvalidParameter` and `isNetworkError` are removed (their codes changed
   meaning). Handle `2006`, `2007`, `2008`, `-6` and `-8` in your UI.
6. **Sign out:** call `logout()` when the user signs out, and after `2006`.
7. Optional: `onSnappedLocation` for an on-road vehicle marker.
8. **Store privacy forms:** the SDK now attaches a per-device identifier, and
   locations travel with the signed-in identity. Declare *Device or other IDs*
   and *Precise location* linked to the user (Google Play Data safety / App
   Store privacy details), for app functionality.

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
