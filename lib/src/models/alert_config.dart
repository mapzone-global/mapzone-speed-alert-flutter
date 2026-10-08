import 'vehicle_type.dart';

/// Immutable configuration used to initialize the native
/// `ZoneNetworkManager` alert engine.
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
    required this.vehicleId,
    this.vehicleType = VehicleType.car,
    this.seats = 4,
    this.weight = 1500,
  });

  /// Speed-alert backend base URL, e.g. `https://driving.map.zone`.
  final String baseUrl;

  /// API key identifier issued by MapZone.
  final String apiKeyId;

  /// API key secret issued by MapZone.
  final String apiKey;

  /// Vehicle identifier registered with MapZone.
  final String vehicleId;

  /// Vehicle type — affects which speed limits apply.
  final VehicleType vehicleType;

  /// Number of seats (used for some vehicle classes).
  final int seats;

  /// Vehicle weight in kilograms. Kept as [int] on the Dart/host side; the
  /// Android bridge casts it to `Double` for the native `configure`.
  final int weight;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'baseUrl': baseUrl,
        'apiKeyId': apiKeyId,
        'apiKey': apiKey,
        'vehicleId': vehicleId,
        'vehicleType': vehicleType.value,
        'seats': seats,
        'weight': weight,
      };

  AlertConfig copyWith({
    String? baseUrl,
    String? apiKeyId,
    String? apiKey,
    String? vehicleId,
    VehicleType? vehicleType,
    int? seats,
    int? weight,
  }) {
    return AlertConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKeyId: apiKeyId ?? this.apiKeyId,
      apiKey: apiKey ?? this.apiKey,
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleType: vehicleType ?? this.vehicleType,
      seats: seats ?? this.seats,
      weight: weight ?? this.weight,
    );
  }
}
