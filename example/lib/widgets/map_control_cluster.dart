import 'package:flutter/material.dart';

/// The bottom-right stack of map controls, mirroring the MapZone Android app's
/// cluster (settings → overview → recenter) plus a mute button, which that app
/// has no equivalent of: it lets the SDK play its own audio, whereas this
/// plugin hands the WAVs to the host so the categories can be muted per type.
///
/// Settings hides while driving and overview only appears once a route exists,
/// so the cluster stays as small as the current state allows.
class MapControlCluster extends StatelessWidget {
  const MapControlCluster({
    super.key,
    required this.showSettings,
    required this.showOverview,
    required this.onSettings,
    required this.onOverview,
    required this.onMute,
    required this.onRecenter,
  });

  final bool showSettings;
  final bool showOverview;
  final VoidCallback onSettings;
  final VoidCallback onOverview;
  final VoidCallback onMute;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget small(String tag, IconData icon, VoidCallback onTap, String tip) =>
        FloatingActionButton.small(
          heroTag: tag,
          onPressed: onTap,
          tooltip: tip,
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundColor: scheme.onSurface,
          elevation: 4,
          child: Icon(icon),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showSettings) ...[
          small('settings', Icons.settings, onSettings, 'Cài đặt'),
          const SizedBox(height: 10),
        ],
        if (showOverview) ...[
          small('overview', Icons.visibility, onOverview, 'Tổng quan tuyến'),
          const SizedBox(height: 10),
        ],
        small('mute', Icons.volume_up, onMute, 'Cấu hình voice'),
        const SizedBox(height: 10),
        FloatingActionButton(
          heroTag: 'recenter',
          onPressed: onRecenter,
          tooltip: 'Về vị trí của tôi',
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 6,
          child: const Icon(Icons.my_location),
        ),
      ],
    );
  }
}
