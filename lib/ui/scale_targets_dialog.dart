/// Per-scale optimisation targets, the counterpart of the desktop export
/// dialog's scale table (`export_dialog.py`).
///
/// These are what make the aggregate index, and so the green best and
/// second-best bands, mean anything: "best" is defined only relative to what
/// the clinician is trying to achieve. The default is `Min` on every scale
/// with the bounds declared in Step 2, as the desktop dialog opens.
///
/// The entry-review figure and the export flow share one set of targets, so
/// the figure on screen and the ranking in the report cannot disagree.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/session/scale_scoring.dart';

/// Human label per mode, matching the desktop's radio labels.
const Map<ScaleMode, String> _modeLabels = {
  ScaleMode.min: 'Lower is better',
  ScaleMode.max: 'Higher is better',
  ScaleMode.custom: 'Custom target',
  ScaleMode.ignore: 'Ignore',
};

/// Short label for the compact dropdown.
const Map<ScaleMode, String> _modeShort = {
  ScaleMode.min: 'Lower is better',
  ScaleMode.max: 'Higher is better',
  ScaleMode.custom: 'Custom',
  ScaleMode.ignore: 'Ignore',
};

/// Edit [prefs]; returns the new list, or null if cancelled.
Future<List<ScalePref>?> showScaleTargetsDialog(
  BuildContext context,
  List<ScalePref> prefs,
) => showDialog<List<ScalePref>>(
  context: context,
  builder: (_) => _ScaleTargetsDialog(prefs: prefs),
);

class _ScaleTargetsDialog extends StatefulWidget {
  const _ScaleTargetsDialog({required this.prefs});

  final List<ScalePref> prefs;

  @override
  State<_ScaleTargetsDialog> createState() => _ScaleTargetsDialogState();
}

/// Mutable working copy of one row. Text controllers rather than parsed doubles
/// so a half-typed "1." does not snap back under the cursor.
class _Row {
  _Row(this.pref)
    : min = TextEditingController(text: _fmt(pref.min)),
      max = TextEditingController(text: _fmt(pref.max)),
      custom = TextEditingController(
        text: pref.custom == null ? '' : _fmt(pref.custom!),
      ),
      mode = pref.mode;

  final ScalePref pref;
  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController custom;
  ScaleMode mode;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double _num(TextEditingController c, double fallback) =>
      double.tryParse(c.text.trim()) ?? fallback;

  ScalePref toPref() => (
    name: pref.name,
    min: _num(min, pref.min),
    max: _num(max, pref.max),
    mode: mode,
    custom: mode == ScaleMode.custom ? _num(custom, 0) : null,
  );

  void dispose() {
    min.dispose();
    max.dispose();
    custom.dispose();
  }
}

class _ScaleTargetsDialogState extends State<_ScaleTargetsDialog> {
  late final List<_Row> _rows = widget.prefs
      .map((p) => _Row(p))
      .toList(growable: false);

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// Apply one mode to every scale, for the common all-Min or all-Max case.
  void _setAll(ScaleMode mode) => setState(() {
    for (final r in _rows) {
      r.mode = mode;
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Scale targets'),
      content: SizedBox(
        width: 520,
        child: _rows.isEmpty
            ? const Text('No symptom and side effect ratings yet.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'How each rating is scored when ranking the '
                    'configurations. The two configurations with the most '
                    'favourable scores are shaded. This is a score ranking '
                    'only; it ignores side effects and notes.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Set all:', style: theme.textTheme.labelMedium),
                      for (final m in [ScaleMode.min, ScaleMode.max])
                        OutlinedButton(
                          onPressed: () => _setAll(m),
                          child: Text(_modeShort[m]!),
                        ),
                    ],
                  ),
                  const Divider(),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [for (final r in _rows) _rowTile(r, theme)],
                      ),
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
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, [for (final r in _rows) r.toPref()]),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _rowTile(_Row row, ThemeData theme) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(row.pref.name, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _numField(row.min, 'Min'),
            _numField(row.max, 'Max'),
            SizedBox(
              width: _scaled(210),
              child: DropdownButtonFormField<ScaleMode>(
                initialValue: row.mode,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Target'),
                items: [
                  for (final m in ScaleMode.values)
                    DropdownMenuItem(
                      value: m,
                      child: Tooltip(
                        message: _modeLabels[m]!,
                        child: Text(_modeShort[m]!),
                      ),
                    ),
                ],
                onChanged: (m) => setState(() => row.mode = m ?? row.mode),
              ),
            ),
            if (row.mode == ScaleMode.custom) _numField(row.custom, 'Value'),
          ],
        ),
      ],
    ),
  );

  /// [width] grown with the text size, so a label never outgrows its field.
  double _scaled(double width) => MediaQuery.textScalerOf(context).scale(width);

  Widget _numField(TextEditingController c, String label) => SizedBox(
    width: _scaled(88),
    child: TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
      decoration: InputDecoration(labelText: label, isDense: true),
    ),
  );
}
