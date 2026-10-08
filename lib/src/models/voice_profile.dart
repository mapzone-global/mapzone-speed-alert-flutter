/// How alerts are spoken, set with [MapZoneSpeedAlert.setVoiceProfile].
///
/// Only the audio changes: on-screen signs, when an alert is picked up and
/// the anti-repeat rules are identical in both profiles. Muted categories stay
/// silent in both (mute is applied first, so a muted alert never becomes a
/// ding).
enum VoiceProfile {
  /// Full spoken Vietnamese phrases (default).
  full(0),

  /// Short ding tones instead of speech: one ding for every camera kind and
  /// for no-parking / no-stopping, a different ding for speeding, and silence
  /// for everything else.
  dingOnly(1);

  const VoiceProfile(this.value);

  /// Native `VoiceProfile` value.
  final int value;
}
