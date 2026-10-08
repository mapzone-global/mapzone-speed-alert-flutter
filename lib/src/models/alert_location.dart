/// A location fix produced by the plugin's native GPS capture (Approach A) and
/// forwarded on the `location` event channel so the UI can show the current
/// position and speed.
class AlertLocation {
  const AlertLocation({
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.bearing,
    this.accuracy,
    this.timestamp,
  });

  final double latitude;
  final double longitude;

  /// Ground speed in km/h.
  final double speedKmh;

  /// Heading in degrees (0–360).
  final double bearing;

  /// Horizontal accuracy in meters, if available.
  final double? accuracy;

  /// Fix time in milliseconds since epoch, if available.
  final int? timestamp;

  factory AlertLocation.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
    return AlertLocation(
      latitude: d(json['lat'] ?? json['latitude']),
      longitude: d(json['lng'] ?? json['longitude']),
      speedKmh: d(json['speedKmh'] ?? json['speed']),
      bearing: d(json['bearing'] ?? json['heading']),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      timestamp: (json['timestamp'] as num?)?.toInt(),
    );
  }

  @override
  String toString() =>
      'AlertLocation($latitude, $longitude, ${speedKmh}km/h, $bearing°)';
}
