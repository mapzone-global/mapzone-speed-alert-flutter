/// Vehicle type passed to the MapZone Speed Alert engine.
///
/// [value] is the MapZone server's own vehicle code, sent unchanged — the same
/// numbers as the native SDK 3.0.0 `VehicleType` enum on Android and iOS.
///
/// The type must also be enabled for your API key; otherwise sign-in reports
/// `MapZoneErrorCode.invalidRequest` and zone requests
/// `MapZoneErrorCode.vehicleTypeNotAllowed`.
///
/// Coming from 1.0.x? The numbers changed: see the README section *Migrating
/// from 1.0.x to 2.0.0*. Do not feed an old stored number to [fromValue].
enum VehicleType {
  /// Car (xe ô tô).
  car(1),

  /// Taxi (xe taxi).
  taxi(2),

  /// Bus (xe bus).
  bus(3),

  /// Coach (xe khách).
  coach(4),

  /// Truck (xe tải).
  truck(5),

  /// Motorcycle (xe máy).
  motorcycle(7);

  const VehicleType(this.value);

  /// Server vehicle code.
  final int value;

  /// The type for a server vehicle code, or `null` when the SDK does not
  /// offer it.
  static VehicleType? fromValue(int value) {
    for (final type in VehicleType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}
