import 'package:flutter/material.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

/// The vehicle the engine is configured for: type + seats + gross weight.
///
/// [VehicleType] is the plugin's enum, whose values are the MapZone server's
/// vehicle codes (car = 1, taxi = 2, bus = 3, coach = 4, truck = 5,
/// motorcycle = 7). The weight is in tonnes, the unit the server reads.
@immutable
class VehicleProfile {
  const VehicleProfile({
    this.type = VehicleType.car,
    this.seats = 5,
    this.weightTons = 1.5,
  });

  final VehicleType type;
  final int seats;
  final double weightTons;

  VehicleProfile copyWith({
    VehicleType? type,
    int? seats,
    double? weightTons,
  }) => VehicleProfile(
    type: type ?? this.type,
    seats: seats ?? this.seats,
    weightTons: weightTons ?? this.weightTons,
  );

  @override
  bool operator ==(Object other) =>
      other is VehicleProfile &&
      other.type == type &&
      other.seats == seats &&
      other.weightTons == weightTons;

  @override
  int get hashCode => Object.hash(type, seats, weightTons);

  @override
  String toString() =>
      'VehicleProfile(${type.name}, seats: $seats, weight: ${weightTons}t)';
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
    }
  }
}
