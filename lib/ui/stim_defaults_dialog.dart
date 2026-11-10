import 'package:flutter/material.dart';

import 'stim_params_form.dart' show LimitRange, StimLimits, presetLabel;
import 'theme.dart' show DbsColors;

/// Edit the starting frequency, amplitude and pulse width of each DBS
/// indication. A row left blank has no defaults. Null on Cancel.
Future<Map<String, List<num>>?> showStimDefaultsDialog(
  BuildContext context, {
  required StimLimits limits,
  required List<String> indications,
}) => showDialog<Map<String, List<num>>>(
  context: context,
  builder: (_) => _StimDefaultsDialog(limits, indications),
);

class _StimDefaultsDialog extends StatefulWidget {
  const _StimDefaultsDialog(this.limits, this.indications);

  final StimLimits limits;
  final List<String> indications;

  @override
  State<_StimDefaultsDialog> createState() => _StimDefaultsDialogState();
}

class _StimDefaultsDialogState extends State<_StimDefaultsDialog> {
  late final _rows = {
    for (final name in {...widget.indications, ...widget.limits.defaults.keys})
      name: [
        for (var i = 0; i < 3; i++)
          TextEditingController(
            text: switch (widget.limits.defaults[name]) {
              final v? => presetLabel(v[i]),
              null => '',
            },
          ),
      ],
  };
  String? _error;

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
            () => _error =
                '$name: $label must be '
                '${presetLabel(ranges[i].min)}-${presetLabel(ranges[i].max)} '
                '$unit.',
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
      title: const Text('Default settings per DBS indication'),
      scrollable: true,
      content: SizedBox(
        width: 560,
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
                    SizedBox(width: 110, child: Text(name)),
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
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: DbsColors.invalid),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
