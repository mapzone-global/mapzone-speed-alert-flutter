import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

import '../state/alert_controller.dart';

/// Voice-alert configuration (calls setMutedAlertTypes natively).
///
/// A switch that is ON means the category is announced; OFF means it is muted.
/// That polarity matches the MapZone iOS sample.
///
/// The layout follows the two rules the SDK enforces in C++ and that a flat list
/// of toggles cannot express:
///
///  * Speed-limit and speeding cues can never be muted — `setMutedVoiceTriggers`
///    force-clears their bits, so they have no [VoiceAlertType] to toggle. They
///    get a locked row rather than being silently absent.
///  * Muting a camera or toll category also hides its on-screen sign, because the
///    icon distance is gated on the same mask. Muting any other category only
///    silences the voice — restriction signs keep showing in the restriction
///    row. Hence the two separate groups.
class MuteSheet extends StatelessWidget {
  const MuteSheet({super.key});

  /// Categories whose voice AND on-screen icon disappear together when muted.
  static const Map<VoiceAlertType, String> _withSign = {
    VoiceAlertType.speedCamera: 'Camera tốc độ',
    VoiceAlertType.trafficEnforcementCamera: 'Camera xử phạt',
    VoiceAlertType.redLightCamera: 'Camera đèn đỏ',
    VoiceAlertType.aiCamera: 'Camera AI',
    VoiceAlertType.toll: 'Trạm thu phí',
  };

  /// Categories whose mute only silences the voice; any sign keeps showing.
  static const Map<VoiceAlertType, String> _voiceOnly = {
    VoiceAlertType.noLeftTurn: 'Cấm rẽ trái',
    VoiceAlertType.noRightTurn: 'Cấm rẽ phải',
    VoiceAlertType.noUTurn: 'Cấm quay đầu',
    VoiceAlertType.noOvertaking: 'Cấm vượt',
    VoiceAlertType.noOvertakingEnd: 'Hết cấm vượt',
    VoiceAlertType.noParking: 'Cấm đỗ xe',
    VoiceAlertType.noStopping: 'Cấm dừng xe',
    VoiceAlertType.roadClosed: 'Đường cấm',
    VoiceAlertType.vehicleRestricted: 'Cấm loại xe',
    VoiceAlertType.noStraight: 'Cấm đi thẳng',
    VoiceAlertType.buildUpAreaStart: 'Bắt đầu khu dân cư',
    VoiceAlertType.buildUpAreaEnd: 'Hết khu dân cư',
    VoiceAlertType.restStation: 'Trạm dừng nghỉ',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AlertController>();
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child:
                      Text('Cấu hình voice', style: theme.textTheme.titleMedium),
                ),
                TextButton(
                    onPressed: p.unmuteAll, child: const Text('Bật tất cả')),
                TextButton(
                    onPressed: p.muteAll, child: const Text('Tắt tất cả')),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              children: [
                _header(theme, 'Cảnh báo tốc độ'),
                const SwitchListTile(
                  dense: true,
                  value: true,
                  onChanged: null,
                  secondary: Icon(Icons.lock_outline),
                  title: Text('Giới hạn tốc độ & vượt tốc'),
                  subtitle: Text(
                      'Luôn bật — SDK không cho phép tắt cảnh báo an toàn này'),
                ),
                _header(theme, 'Camera & Trạm thu phí',
                    note:
                        'Tắt tiếng sẽ ẩn luôn biển báo tương ứng trên màn hình'),
                ..._withSign.entries.map((e) => _tile(p, e.key, e.value)),
                _header(theme, 'Biển báo khác',
                    note:
                        'Chỉ tắt tiếng — biển báo (nếu có) vẫn hiển thị'),
                ..._voiceOnly.entries.map((e) => _tile(p, e.key, e.value)),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, String title, {String? note}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.primary)),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(note, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _tile(AlertController p, VoiceAlertType type, String label) {
    return SwitchListTile(
      dense: true,
      title: Text(label),
      value: !p.isMuted(type),
      onChanged: (_) => p.toggleMute(type),
    );
  }
}
