import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

import 'models/vehicle_profile.dart';

class Env {
  static const String baseUrl = 'https://driving.map.zone';
  static const String apiKeyId = 'YOUR_API_KEY_ID';
  static const String apiKey = 'YOUR_API_KEY';
  static const String vehicleId = 'YOUR_VEHICLE_ID';

  /// Vehicle the engine starts with. The user can change it at runtime from the
  /// settings dialog, which re-configures the engine.
  static const VehicleProfile defaultVehicle = VehicleProfile();

  // VietMap key for map display, routing and search/autocomplete.
  static const String vietmapApiKey = 'YOUR_VIETMAP_API_KEY';
  static const String vietmapMapStyle =
      'https://maps.vietmap.vn/api/maps/light/styles.json?apikey=$vietmapApiKey';

  static AlertConfig configFor(VehicleProfile v) => AlertConfig(
        baseUrl: baseUrl,
        apiKeyId: apiKeyId,
        apiKey: apiKey,
        vehicleId: vehicleId,
        vehicleType: v.type,
        seats: v.seats,
        weight: v.weightKg,
      );

  static AlertConfig get config => configFor(defaultVehicle);
}
