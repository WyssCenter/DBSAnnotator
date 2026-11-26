import 'package:flutter/material.dart';

import '../app_info.dart';
import 'stim_params_form.dart' show LimitRange, StimLimits, presetLabel;

/// Edit the starting frequency, amplitude and pulse width of each DBS
/// indication. A row left blank has no defaults; Restore defaults puts back
/// [defaults], the ones the app comes with. Null on Cancel.
Future<Map<String, List<num>>?> showStimDefaultsDialog(
  BuildContext context, {
  required StimLimits limits,
  required List<String> indications,
  required Map<String, List<num>> defaults,
}) => showDialog<Map<String, List<num>>>(
  context: context,
  builder: (_) => _StimDefaultsDialog(limits, indications, defaults),
);

class _StimDefaultsDialog extends StatefulWidget {
  const _StimDefaultsDialog(this.limits, this.indications, this.defaults);

  final StimLimits limits;
  final List<String> indications;
  final Map<String, List<num>> defaults;

  @override
  State<_StimDefaultsDialog> createState() => _StimDefaultsDialogState();
}

class _StimDefaultsDialogState extends State<_StimDefaultsDialog> {
  late final _rows = {
    for (final name in {...widget.indications, ...widget.limits.defaults.keys})
      name: _controllers(widget.limits.defaults[name]),
  };

  /// The field that cannot be saved, and why.
  ({String name, int column, String message})? _invalid;

  static List<TextEditingController> _controllers(List<num>? values) => [
    for (var i = 0; i < 3; i++)
      TextEditingController(text: values == null ? '' : presetLabel(values[i])),
  ];

  void _restore() => setState(() {
    for (final name in widget.defaults.keys) {
      _rows.putIfAbsent(name, () => _controllers(null));
    }
    for (final MapEntry(key: name, value: ctrls) in _rows.entries) {
      final values = widget.defaults[name];
      for (var i = 0; i < 3; i++) {
        ctrls[i].text = values == null ? '' : presetLabel(values[i]);
      }
    }
    _invalid = null;
  });

  static const _columns = [
    ('Frequency', 'Hz'),
    ('Amplitude', 'mA'),
    ('Pulse width', 'µs'),
  ];

  @override
  void dispose() {
    for (final c in _rows.values.expand((r) => r)) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final ranges = <LimitRange>[
      widget.limits.frequency,
      widget.limits.amplitude,
      widget.limits.pulseWidth,
    ];
    final out = <String, List<num>>{};
    for (final MapEntry(key: name, value: ctrls) in _rows.entries) {
      final texts = [for (final c in ctrls) c.text.trim()];
      if (texts.every((t) => t.isEmpty)) continue;
      final values = <num>[];
      for (var i = 0; i < 3; i++) {
        final v = num.tryParse(texts[i]);
        final (label, unit) = _columns[i];
        if (v == null || v < ranges[i].min || v > ranges[i].max) {
          setState(
            () => _invalid = (
              name: name,
              column: i,
              message:
                  '$label must be ${presetLabel(ranges[i].min)} to '
                  '${presetLabel(ranges[i].max)} $unit',
            ),
          );
          return;
        }
        values.add(v);
      }
      out[name] = values;
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const DefaultsTitle(
        'Stimulation defaults',
        section: 'stimulation-defaults',
      ),
      constraints: const BoxConstraints(),
      scrollable: true,
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Filled in on both sides when the initial assessment starts. '
              'Leave a row blank to start with empty fields.',
            ),
            const SizedBox(height: 12),
            for (final MapEntry(key: name, value: ctrls) in _rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 190, child: Text(name)),
                    for (var i = 0; i < 3; i++) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: ctrls[i],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: _columns[i].$1,
                            suffixText: _columns[i].$2,
                            isDense: true,
                            errorText:
                                _invalid?.name == name && _invalid?.column == i
                                ? _invalid?.message
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: picklistActions(context, onRestore: _restore, onSave: _save),
    );
  }
}
