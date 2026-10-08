/// Configurable voice-alert categories the host app can mute via
/// [MapZoneSpeedAlert.setMutedAlertTypes].
///
/// Each value maps 1:1 to a native `VoiceTrigger` code.
///
/// Speed-limit ("current" / "next") and speeding warnings are core safety cues
/// that are always announced and intentionally have no entry here. Muting a
/// camera or toll category also hides its sign (there is a single slot for
/// each); muting any other category only silences the voice — restriction
/// signs keep showing on [MapZoneSpeedAlert.onRestriction].
enum VoiceAlertType {
  speedCamera(3),
  toll(4),
  trafficEnforcementCamera(6),
  redLightCamera(7),
  aiCamera(8),
  noLeftTurn(9),
  noRightTurn(10),
  noUTurn(11),
  noOvertaking(12),
  noOvertakingEnd(13),
  noParking(14),
  noStraight(15),
  buildUpAreaStart(16),
  buildUpAreaEnd(17),
  restStation(18),
  noStopping(19),
  roadClosed(20),
  vehicleRestricted(21);

  const VoiceAlertType(this.trigger);

  /// Native `VoiceTrigger` value (also the `VoiceEvent.trigger` code).
  final int trigger;

  /// Resolve a [VoiceAlertType] from a native trigger code, or `null` if the
  /// code is not a mutable category (e.g. speed-limit / speeding cues).
  static VoiceAlertType? fromTrigger(int trigger) {
    for (final t in VoiceAlertType.values) {
      if (t.trigger == trigger) return t;
    }
    return null;
  }
}
