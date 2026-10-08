import 'package:audioplayers/audioplayers.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

/// Plays voice-alert WAV clips forwarded by the plugin, honouring the SDK
/// priority model:
///   priority 0 = current, 1 = normal, 2 = speeding.
///
/// A higher-priority clip interrupts the current playback and trims any lower-
/// priority backlog so the driver always hears the most important alert first.
class VoiceQueue {
  VoiceQueue();

  final AudioPlayer _player = AudioPlayer();
  final List<VoiceEvent> _queue = <VoiceEvent>[];
  VoiceEvent? _playing;
  bool _started = false;

  void _ensureStarted() {
    if (_started) return;
    _started = true;
    _player.onPlayerComplete.listen((_) {
      _playing = null;
      _playNext();
    });
  }

  Future<void> enqueue(VoiceEvent event) async {
    _ensureStarted();
    if (event.wav.isEmpty) return;

    // Interrupt lower-priority playback and drop lower-priority backlog.
    if (_playing != null && event.priority > _playing!.priority) {
      _queue.removeWhere((e) => e.priority < event.priority);
      _queue.insert(0, event);
      await _player.stop();
      _playing = null;
      await _playNext();
      return;
    }

    _queue.add(event);
    if (_playing == null) {
      await _playNext();
    }
  }

  Future<void> _playNext() async {
    if (_playing != null || _queue.isEmpty) return;
    final next = _queue.removeAt(0);
    _playing = next;
    try {
      await _player.play(BytesSource(next.wav, mimeType: 'audio/wav'));
    } catch (_) {
      _playing = null;
      await _playNext();
    }
  }

  Future<void> clear() async {
    _queue.clear();
    _playing = null;
    await _player.stop();
  }

  Future<void> dispose() async {
    _queue.clear();
    await _player.dispose();
  }
}
