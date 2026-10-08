import 'dart:typed_data';

import 'voice_alert_type.dart';

/// A voice-alert clip emitted by the native `onVoice` callback.
///
/// Delivered only while [MapZoneSpeedAlert.onVoice] has a listener; the SDK's
/// built-in player is silent meanwhile, so the host app plays the raw WAV
/// bytes itself (e.g. with `audioplayers`/`just_audio`) using a priority-aware
/// queue.
class VoiceEvent {
  const VoiceEvent({
    required this.wav,
    required this.trigger,
    required this.priority,
  });

  /// WAV audio bytes (22,050 Hz mono PCM 16-bit).
  final Uint8List wav;

  /// Alert type code (0–21) describing what produced the clip.
  final int trigger;

  /// Playback priority: `0` = current, `1` = normal, `2` = speeding.
  /// Higher priority clips should interrupt / trim lower-priority backlog.
  final int priority;

  /// The mutable alert category this clip belongs to, or `null` for core
  /// speed-limit / speeding cues that cannot be muted.
  VoiceAlertType? get type => VoiceAlertType.fromTrigger(trigger);

  factory VoiceEvent.fromJson(Map<String, dynamic> json) {
    final bytes = json['wav'];
    return VoiceEvent(
      wav: bytes is Uint8List ? bytes : Uint8List(0),
      trigger: (json['trigger'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as num?)?.toInt() ?? 1,
    );
  }

  @override
  String toString() =>
      'VoiceEvent(trigger: $trigger, type: ${type?.name}, priority: $priority, bytes: ${wav.length})';
}
