import 'dart:typed_data';

import 'speed_status.dart';

/// A fully-populated snapshot of the current alert state, emitted on every
/// processed GPS frame by the native `onBitmap` callback.
///
/// Sign images are PNG-encoded bytes. To avoid re-encoding and re-sending the
/// same PNG on every ~1 Hz frame, the native layer only ships image bytes when
/// an image *changes*; [AlertEvent.merge] reuses the previous event's bytes
/// when native signals "unchanged". Each emitted [AlertEvent] is therefore
/// self-contained — the UI can render the latest event directly.
class AlertEvent {
  const AlertEvent({
    this.speedStatus = SpeedStatus.compliant,
    this.currentSpeedLimitSign,
    this.nextSign,
    this.nextDistanceMeters,
    this.cameraSign,
    this.cameraDistanceMeters,
    this.tollSign,
    this.tollDistanceMeters,
  });

  /// Speed compliance status for the current speed limit.
  final SpeedStatus speedStatus;

  /// PNG bytes of the currently applicable speed-limit sign (null if none).
  final Uint8List? currentSpeedLimitSign;

  /// PNG bytes of the next speed-limit sign ahead (null if none).
  final Uint8List? nextSign;

  /// Distance in meters to [nextSign] (null if none).
  final int? nextDistanceMeters;

  /// PNG bytes of the upcoming speed-camera sign (null if none).
  final Uint8List? cameraSign;

  /// Distance in meters to [cameraSign] (null if none).
  final int? cameraDistanceMeters;

  /// PNG bytes of the upcoming toll-gate sign (null if none).
  final Uint8List? tollSign;

  /// Distance in meters to [tollSign] (null if none).
  final int? tollDistanceMeters;

  /// Build an [AlertEvent] from the raw native payload, reusing image bytes
  /// from [previous] when the native layer reports a sign as unchanged.
  factory AlertEvent.merge(Map<String, dynamic> raw, AlertEvent? previous) {
    Uint8List? resolveImage(String key, Uint8List? prevBytes) {
      final present = raw['${key}Present'] == true;
      if (!present) return null;
      final changed = raw['${key}Changed'] == true;
      if (changed) {
        final bytes = raw['${key}Sign'];
        return bytes is Uint8List ? bytes : null;
      }
      return prevBytes;
    }

    int? resolveDistance(String key) {
      final present = raw['${key}Present'] == true;
      if (!present) return null;
      final d = raw['${key}Dist'];
      if (d is int) return d < 0 ? null : d;
      if (d is num) return d < 0 ? null : d.toInt();
      return null;
    }

    return AlertEvent(
      speedStatus: SpeedStatus.fromValue(raw['speedStatus'] as int?),
      currentSpeedLimitSign:
          resolveImage('cur', previous?.currentSpeedLimitSign),
      nextSign: resolveImage('next', previous?.nextSign),
      nextDistanceMeters: resolveDistance('next'),
      cameraSign: resolveImage('cam', previous?.cameraSign),
      cameraDistanceMeters: resolveDistance('cam'),
      tollSign: resolveImage('toll', previous?.tollSign),
      tollDistanceMeters: resolveDistance('toll'),
    );
  }

  bool get isSpeeding => speedStatus == SpeedStatus.exceeding;

  @override
  String toString() =>
      'AlertEvent(status: $speedStatus, next: ${nextDistanceMeters}m, '
      'camera: ${cameraDistanceMeters}m, toll: ${tollDistanceMeters}m)';
}
