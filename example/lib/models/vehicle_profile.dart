import 'package:flutter/material.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

/// The vehicle the engine is configured for: type + seats + kerb weight.
///
/// [VehicleType] is the plugin's enum, whose values are the codes the MapZone
/// SDK actually documents (car = 1 … emergency = 9). The MapZone Android
/// reference app instead derives a 1–5 "vehicle class" from seats/weight and
/// sends *that* as the vehicle type while hard-coding seats = 1 and weight = 1.
/// The two readings disagree (its "motorcycle" lands on 1, which the SDK calls
/// a car), so this example follows the SDK enum and sends the real seats and
/// weight the user typed.
@immutable
class VehicleProfile {
  const VehicleProfile({
    this.type = VehicleType.car,
    this.seats = 5,
    this.weightKg = 1500,
  });

  final VehicleType type;
  final int seats;
  final int weightKg;

  VehicleProfile copyWith({VehicleType? type, int? seats, int? weightKg}) =>
      VehicleProfile(
        type: type ?? this.type,
        seats: seats ?? this.seats,
        weightKg: weightKg ?? this.weightKg,
      );

  @override
  bool operator ==(Object other) =>
      other is VehicleProfile &&
      other.type == type &&
      other.seats == seats &&
      other.weightKg == weightKg;

  @override
  int get hashCode => Object.hash(type, seats, weightKg);

  @override
  String toString() =>
      'VehicleProfile(${type.name}, seats: $seats, weight: ${weightKg}kg)';
}

/// Vietnamese label + icon for each vehicle type the SDK accepts.
extension VehicleTypeUi on VehicleType {
  String get label {
    switch (this) {
      case VehicleType.car:
        return 'Ô tô';
      case VehicleType.motorcycle:
        return 'Xe máy';
      case VehicleType.truck:
        return 'Xe tải';
      case VehicleType.coach:
        return 'Xe khách';
      case VehicleType.bus:
        return 'Xe buýt';
      case VehicleType.taxi:
        return 'Taxi';
      case VehicleType.bicycle:
        return 'Xe đạp';
      case VehicleType.pedestrian:
        return 'Đi bộ';
      case VehicleType.emergency:
        return 'Xe ưu tiên';
    }
  }

  IconData get icon {
    switch (this) {
      case VehicleType.car:
        return Icons.directions_car;
      case VehicleType.motorcycle:
        return Icons.two_wheeler;
      case VehicleType.truck:
        return Icons.local_shipping;
      case VehicleType.coach:
        return Icons.airport_shuttle;
      case VehicleType.bus:
        return Icons.directions_bus;
      case VehicleType.taxi:
        return Icons.local_taxi;
      case VehicleType.bicycle:
        return Icons.directions_bike;
      case VehicleType.pedestrian:
        return Icons.directions_walk;
      case VehicleType.emergency:
        return Icons.emergency;
    }
  }
}
