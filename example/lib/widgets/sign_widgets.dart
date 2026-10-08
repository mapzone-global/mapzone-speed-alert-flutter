import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

import '../state/alert_controller.dart';

Color speedStatusColor(SpeedStatus status) {
  switch (status) {
    case SpeedStatus.compliant:
      return const Color(0xFF2E7D32);
    case SpeedStatus.approaching:
      return const Color(0xFFEF6C00);
    case SpeedStatus.exceeding:
      return const Color(0xFFC62828);
  }
}

String speedStatusLabel(SpeedStatus status) {
  switch (status) {
    case SpeedStatus.compliant:
      return 'Trong giới hạn';
    case SpeedStatus.approaching:
      return 'Sắp tới giới hạn';
    case SpeedStatus.exceeding:
      return 'Vượt tốc độ!';
  }
}

/// The four sign slots the engine renders, stacked top-left over the map —
/// the same column the MapZone Android app uses: current limit big, the rest
/// small, each on a white disc with its distance on a dark pill underneath.
///
/// The whole column disappears when the engine has no sign to show, so an empty
/// road leaves the map clean. A camera or toll slot going empty is also how a
/// muted category becomes visible as *absence* — the engine gates the icon on
/// the same mute mask as the voice.
class SignOverlay extends StatelessWidget {
  const SignOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final alert = context.select<AlertController, AlertEvent?>((p) => p.alert);
    if (alert == null) return const SizedBox.shrink();

    final hasAny = alert.currentSpeedLimitSign != null ||
        alert.nextSign != null ||
        alert.cameraSign != null ||
        alert.tollSign != null;
    if (!hasAny) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SignTile(image: alert.currentSpeedLimitSign, size: 76),
        _SignTile(
            image: alert.nextSign,
            distanceMeters: alert.nextDistanceMeters,
            size: 50),
        _SignTile(
            image: alert.cameraSign,
            distanceMeters: alert.cameraDistanceMeters,
            size: 50),
        _SignTile(
            image: alert.tollSign,
            distanceMeters: alert.tollDistanceMeters,
            size: 50),
      ],
    );
  }
}

/// Road-restriction signs (no stopping / parking, closed road, vehicle ban,
/// built-up area), a row under the speed chip. Hidden while every slot is
/// empty.
class RestrictionRow extends StatelessWidget {
  const RestrictionRow({super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.select<AlertController, RestrictionEvent?>(
        (p) => p.restrictions);
    if (r == null || r.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      alignment: WrapAlignment.end,
      children: [
        _SignTile(image: r.stop, distanceMeters: r.stopDistMeters, size: 40),
        _SignTile(
            image: r.closed, distanceMeters: r.closedDistMeters, size: 40),
        _SignTile(
            image: r.vehicle, distanceMeters: r.vehicleDistMeters, size: 40),
        // The built-up-area artwork is a landscape rectangle.
        _SignTile(
            image: r.bua,
            distanceMeters: r.buaDistMeters,
            size: 40,
            width: 60),
      ],
    );
  }
}

class _SignTile extends StatelessWidget {
  const _SignTile({
    required this.image,
    required this.size,
    this.distanceMeters,
    this.width,
  });

  final Uint8List? image;
  final int? distanceMeters;
  final double size;

  /// Set for rectangular artwork; the tile then drops the round backdrop.
  final double? width;

  @override
  Widget build(BuildContext context) {
    if (image == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              shape: width == null ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: width == null ? null : BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
            ),
            child: SizedBox(
              width: width ?? size,
              height: size,
              child: Image.memory(image!, gaplessPlayback: true),
            ),
          ),
          if (distanceMeters != null && distanceMeters! > 0)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _formatDistance(distanceMeters!),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }

  static String _formatDistance(int m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '$m m';
}

/// Current speed + speed-limit status, top-right.
///
/// The MapZone Android app plumbs `speedStatus` through but never renders it;
/// this is where you actually see the speeding cue fire, so the example keeps
/// it.
class SpeedChip extends StatelessWidget {
  const SpeedChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AlertController>(
      builder: (context, p, _) {
        final status = p.alert?.speedStatus ?? SpeedStatus.compliant;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: speedStatusColor(status),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${p.speedKmh.toStringAsFixed(0)} km/h',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              Text(
                speedStatusLabel(status),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}
