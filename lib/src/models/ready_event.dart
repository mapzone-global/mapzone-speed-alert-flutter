/// Emitted by the native `onReady` callback once zone data has loaded for the
/// current area.
class ReadyEvent {
  const ReadyEvent({
    required this.isReady,
    required this.linkCount,
    required this.alertCount,
  });

  /// Whether the alert engine finished loading and is ready to process GPS.
  final bool isReady;

  /// Number of road links loaded for the current zone.
  final int linkCount;

  /// Number of alert points (cameras, tolls, sign changes) loaded.
  final int alertCount;

  factory ReadyEvent.fromJson(Map<String, dynamic> json) {
    return ReadyEvent(
      isReady: json['isReady'] as bool? ?? true,
      linkCount: (json['linkCount'] as num?)?.toInt() ?? 0,
      alertCount: (json['alertCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() =>
      'ReadyEvent(isReady: $isReady, links: $linkCount, alerts: $alertCount)';
}
