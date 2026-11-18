import 'dart:convert';

import 'vehicle_type.dart';

/// Immutable configuration used to initialize the native
/// `ZoneNetworkManager` alert engine.
///
/// Passing it to `MapZoneSpeedAlert.initialize` signs [identity] in on this
/// device. Call `initialize` on every sign-in **and** on every app launch with
/// a user already signed in: the SDK does not remember the identity across
/// launches.
///
/// There is no `bundleId` field: the native SDK reads the host app's own
/// application id / bundle id (Android `applicationId` including any flavor
/// suffix, iOS `CFBundleIdentifier`). It must match the id registered for the
/// API key.
class AlertConfig {
  const AlertConfig({
    required this.baseUrl,
    required this.apiKeyId,
    required this.apiKey,
    required this.identity,
    this.vehicleType = VehicleType.car,
    this.seats = 4,
    this.weightTons = 1.5,
    this.metadata,
  });

  /// Speed-alert backend base URL, e.g. `https://driving.map.zone`. Must be
  /// `https://`.
  final String baseUrl;

  /// API key identifier issued by MapZone.
  final String apiKeyId;

  /// API key secret issued by MapZone.
  final String apiKey;

  /// Who is signed in on this device — typically the account's phone number
  /// in `+84…` form. Sent verbatim and matched exactly: `"0901234567"` and
  /// `"+84901234567"` are two different users, so pick one format and keep
  /// it. Non-empty, at most 128 characters, no `"` and no control characters.
  ///
  /// One identity is active on one device at a time: signing it in elsewhere
  /// moves the session there and this device receives
  /// `MapZoneErrorCode.sessionMoved`.
  final String identity;

  /// Vehicle type — affects which speed limits apply.
  final VehicleType vehicleType;

  /// Number of seats, 0 or more (filters applicable alerts).
  final int seats;

  /// Vehicle gross weight in **tonnes** (e.g. `1.5`), 0 or more (filters
  /// applicable alerts).
  final double weightTons;

  /// Optional information about this device / user (app version, your
  /// internal user id, …), stored with the session when it is opened. Agree
  /// the key names with Vietmap. The SDK adds `"model"` and `"os"` unless you
  /// set them.
  ///
  /// Encoded as one JSON object, at most 2048 UTF-8 bytes, nesting depth at
  /// most 16. Recorded only when a session opens (first sign-in on the device,
  /// or a new identity): re-initializing with the same identity keeps the
  /// metadata stored at sign-in.
  final Map<String, Object?>? metadata;

  /// Channel payload. [metadata] travels as its JSON text, which the native
  /// SDK validates; `null` means none.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'baseUrl': baseUrl,
        'apiKeyId': apiKeyId,
        'apiKey': apiKey,
        'identity': identity,
        'vehicleType': vehicleType.value,
        'seats': seats,
        'weightTons': weightTons,
        'metadata': metadata == null ? null : jsonEncode(metadata),
      };

  AlertConfig copyWith({
    String? baseUrl,
    String? apiKeyId,
    String? apiKey,
    String? identity,
    VehicleType? vehicleType,
    int? seats,
    double? weightTons,
    Map<String, Object?>? metadata,
  }) {
    return AlertConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKeyId: apiKeyId ?? this.apiKeyId,
      apiKey: apiKey ?? this.apiKey,
      identity: identity ?? this.identity,
      vehicleType: vehicleType ?? this.vehicleType,
      seats: seats ?? this.seats,
      weightTons: weightTons ?? this.weightTons,
      metadata: metadata ?? this.metadata,
    );
  }
}
