/// A GPS fix moved onto the road the engine is serving, from the
/// `onSnappedLocation` stream. Draw the vehicle marker from it so the marker
/// stays on the road instead of following raw GPS noise.
class SnappedLocation {
  const SnappedLocation({
    required this.latitude,
    required this.longitude,
    required this.bearingDegrees,
  });

  /// Latitude in degrees (WGS84).
  final double latitude;

  /// Longitude in degrees (WGS84).
  final double longitude;

  /// Road bearing at this point in the direction of travel: 0 = north,
  /// clockwise, range `[0, 360)`.
  final double bearingDegrees;

  factory SnappedLocation.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
    return SnappedLocation(
      latitude: d(json['lat']),
      longitude: d(json['lng']),
      bearingDegrees: d(json['bearing']),
    );
  }

  @override
  String toString() => 'SnappedLocation($latitude, $longitude, $bearingDegrees°)';
}
