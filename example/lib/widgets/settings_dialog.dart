import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapzone_speed_alert/mapzone_speed_alert.dart';

import '../models/vehicle_profile.dart';

/// What the settings dialog returns.
class SettingsResult {
  const SettingsResult({
    required this.vehicle,
    required this.simulate,
    required this.speedMultiplier,
  });

  final VehicleProfile vehicle;
  final bool simulate;
  final double speedMultiplier;
}

/// Vehicle profile + route simulation, in one dialog reached from the settings
/// FAB — the same place the MapZone Android app puts them.
///
/// Simulation speed is a *multiplier*, not km/h: `vietmap_flutter_navigation`
/// only exposes `setSpeedMultiplier`, so the km/h presets the Android app offers
/// have no equivalent here. 2–3× is enough to overshoot most limits and trigger
/// the speeding cue.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.vehicle,
    required this.simulate,
    required this.speedMultiplier,
  });

  final VehicleProfile vehicle;
  final bool simulate;
  final double speedMultiplier;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  static const List<double> _presets = [1, 1.5, 2, 3];

  late VehicleType _type = widget.vehicle.type;
  late final TextEditingController _seats =
      TextEditingController(text: widget.vehicle.seats.toString());
  late final TextEditingController _weight =
      TextEditingController(text: widget.vehicle.weightKg.toString());
  late bool _simulate = widget.simulate;
  late double _multiplier = widget.speedMultiplier;

  @override
  void dispose() {
    _seats.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      SettingsResult(
        vehicle: VehicleProfile(
          type: _type,
          seats: int.tryParse(_seats.text) ?? widget.vehicle.seats,
          weightKg: int.tryParse(_weight.text) ?? widget.vehicle.weightKg,
        ),
        simulate: _simulate,
        speedMultiplier: _multiplier,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(Icons.settings, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Cài đặt'),
        ],
      ),
      content: SizedBox(
        // maxFinite lets the dialog size itself to the screen; a fixed width
        // overflows on a phone.
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _label(theme, 'Loại xe'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: VehicleType.values
                    .map((t) => _VehicleCard(
                          type: t,
                          selected: t == _type,
                          onTap: () => setState(() => _type = t),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              _label(theme, 'Thông số'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _numberField(_seats, 'Chỗ ngồi', 3)),
                  const SizedBox(width: 8),
                  Expanded(child: _numberField(_weight, 'Trọng tải (kg)', 6)),
                ],
              ),
              const SizedBox(height: 16),
              _label(theme, 'Mô phỏng'),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _simulate,
                onChanged: (v) => setState(() => _simulate = v),
                title: const Text('Simulator mode'),
                subtitle: const Text('Chạy tuyến giả lập thay vì GPS thật'),
              ),
              if (_simulate) ...[
                const SizedBox(height: 4),
                Text('Hệ số tốc độ mô phỏng',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: _presets
                      .map((m) => ChoiceChip(
                            label: Text('${_fmt(m)}×'),
                            selected: _multiplier == m,
                            onSelected: (_) => setState(() => _multiplier = m),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Lưu', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  static String _fmt(double m) =>
      m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toString();

  Widget _label(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.labelLarge
            ?.copyWith(color: theme.colorScheme.primary),
      );

  Widget _numberField(TextEditingController c, String label, int maxLen) =>
      TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(maxLen),
        ],
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
      );
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final VehicleType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              type.icon,
              size: 24,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              type.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
