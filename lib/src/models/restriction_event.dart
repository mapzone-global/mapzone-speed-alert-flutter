import 'dart:typed_data';

/// Road-restriction signs, from [MapZoneSpeedAlert.onRestriction].
///
/// The slots are independent: one stretch of road may be in a built-up area,
/// closed to your vehicle type and no-stopping at once. Each event carries the
/// full current state of every slot. A distance of `0` means the vehicle is on
/// that stretch right now; an empty slot has a `null` image.
///
/// Events arrive when a slot changes, not on every GPS frame, and a new
/// listener immediately receives the current state.
class RestrictionEvent {
  const RestrictionEvent({
    this.stop,
    this.stopDistMeters = 0,
    this.closed,
    this.closedDistMeters = 0,
    this.vehicle,
    this.vehicleDistMeters = 0,
    this.bua,
    this.buaDistMeters = 0,
    this.inBua = false,
  });

  /// Decodes the platform-channel payload. Missing keys mean an empty slot.
  factory RestrictionEvent.fromJson(Map<String, dynamic> json) {
    Uint8List? image(String key) {
      final v = json[key];
      return v is Uint8List ? v : null;
    }

    int dist(String key) => (json[key] as num?)?.toInt() ?? 0;

    return RestrictionEvent(
      stop: image('stop'),
      stopDistMeters: dist('stopDistMeters'),
      closed: image('closed'),
      closedDistMeters: dist('closedDistMeters'),
      vehicle: image('vehicle'),
      vehicleDistMeters: dist('vehicleDistMeters'),
      bua: image('bua'),
      buaDistMeters: dist('buaDistMeters'),
      inBua: json['inBua'] == true,
    );
  }

  /// No-parking / no-stopping sign (PNG).
  final Uint8List? stop;

  /// Distance to [stop] in metres.
  final int stopDistMeters;

  /// Road-closed sign (PNG).
  final Uint8List? closed;

  /// Distance to [closed] in metres.
  final int closedDistMeters;

  /// Sign for a road closed to the configured vehicle type (PNG).
  final Uint8List? vehicle;

  /// Distance to [vehicle] in metres.
  final int vehicleDistMeters;

  /// Built-up-area sign (PNG): the area entry sign, or the end-of-area sign
  /// after leaving it. The artwork is a landscape rectangle, not a circle.
  final Uint8List? bua;

  /// Distance to [bua] in metres (`0` while inside).
  final int buaDistMeters;

  /// Whether the vehicle is currently inside a built-up area.
  final bool inBua;

  /// Whether every slot is empty.
  bool get isEmpty =>
      stop == null && closed == null && vehicle == null && bua == null;

  @override
  String toString() =>
      'RestrictionEvent(stop: ${stop != null ? '${stopDistMeters}m' : '-'}, '
      'closed: ${closed != null ? '${closedDistMeters}m' : '-'}, '
      'vehicle: ${vehicle != null ? '${vehicleDistMeters}m' : '-'}, '
      'bua: ${bua != null ? '${buaDistMeters}m' : '-'}, inBua: $inBua)';
}
