/// Vehicle type passed to the MapZone Speed Alert engine.
///
/// The integer [value] is the code understood by the native SDK. These codes
/// are taken from the Android SDK's authoritative `VehicleType.getValue()`
/// (verified from `mapzone_speed_alert_android` 2.0.0):
///
/// `car=1, motorcycle=2, truck=3, coach=4, bus=5, taxi=6, bicycle=7,
/// pedestrian=8, emergency=9`.
///
/// `car`/`motorcycle`/`truck` agree with the iOS SDK documentation (1/2/3).
/// The higher codes should be re-verified against the iOS SDK enum; the server
/// reports an unsupported type through [AlertResult] error code `3003`.
enum VehicleType {
  car(1),
  motorcycle(2),
  truck(3),
  coach(4),
  bus(5),
  taxi(6),
  bicycle(7),
  pedestrian(8),
  emergency(9);

  const VehicleType(this.value);

  /// SDK vehicle-type code.
  final int value;

  /// Resolve a [VehicleType] from its native [value]. Falls back to [car].
  static VehicleType fromValue(int value) {
    return VehicleType.values.firstWhere(
      (v) => v.value == value,
      orElse: () => VehicleType.car,
    );
  }
}
