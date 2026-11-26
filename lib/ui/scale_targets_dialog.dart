/// What "better" means for each rating, for the ranking of one session or
/// report, and the column layout the rating dialogs share.
///
/// The figure on screen and the report rank with the same targets, so they
/// cannot disagree.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/session/scale_scoring.dart';

/// What each target means, shown on hover and in "Set all".
const Map<ScaleMode, String> _modeLabels = {
  ScaleMode.min: 'Lower is better',
  ScaleMode.max: 'Higher is better',
  ScaleMode.custom: 'Closest to a value is better',
  ScaleMode.ignore: 'Not counted in the ranking',
};

/// The target as the Better when column shows it.
const Map<ScaleMode, String> _modeShort = {
  ScaleMode.min: 'Lower',
  ScaleMode.max: 'Higher',
  ScaleMode.custom: 'Closest to',
  ScaleMode.ignore: 'Not ranked',
};

/// Widths of the shared columns, before text scaling.
const double kRangeWidth = 64;
const double kTargetWidth = 150;
const double kValueWidth = 72;

/// [width] grown with the text size, so a label never outgrows its field.
double scaledWidth(BuildContext context, double width) =>
    MediaQuery.textScalerOf(context).scale(width);

/// A number field [width] wide, showing [label] when [labelled], else naming
/// itself to screen readers only, under a header that shows it.
Widget numberField(
  BuildContext context,
  TextEditingController c,
  String label, {
  double width = kRangeWidth,
  bool labelled = false,
}) => SizedBox(
  width: scaledWidth(context, width),
  child: Semantics(
    label: label,
    child: TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
      decoration: InputDecoration(
        labelText: labelled ? label : null,
        isDense: true,
      ),
    ),
  ),
);

/// The header over one-line rows: [first] takes the rest of the width, then
/// each column at its width, and [trailing] blank space for row buttons.
Widget tableHeader(
  BuildContext context,
  String first,
  List<(String, double)> columns, {
  double trailing = 0,
}) {
  final style = Theme.of(context).textTheme.labelMedium
      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(child: Text(first, style: style)),
        for (final (label, width) in columns) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: scaledWidth(context, width),
            child: Text(label, style: style),
          ),
        ],
        if (trailing > 0) SizedBox(width: trailing),
      ],
    ),
  );
}

/// The target of one rating, and the value to get close to when it is
/// Closest to; the value's column is kept empty otherwise, so rows line up.
class TargetFields extends StatelessWidget {
  const TargetFields({
    super.key,
    required this.mode,
    required this.custom,
    required this.onChanged,
    this.labelled = false,
  });

  final ScaleMode mode;
  final TextEditingController custom;
  final ValueChanged<ScaleMode> onChanged;

  /// Whether the fields show their own labels, where no header names them.
  final bool labelled;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: scaledWidth(context, kTargetWidth),
        child: Semantics(
          label: 'Better when',
          child: DropdownButtonFormField<ScaleMode>(
            key: ValueKey(mode),
            initialValue: mode,
            isDense: true,
            isExpanded: true,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              labelText: labelled ? 'Better when' : null,
              isDense: true,
            ),
            items: [
              for (final m in ScaleMode.values)
                DropdownMenuItem(
                  value: m,
                  child: Tooltip(
                    message: _modeLabels[m]!,
                    child: Text(
                      _modeShort[m]!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            onChanged: (m) => onChanged(m ?? mode),
          ),
        ),
      ),
      const SizedBox(width: 8),
      if (mode == ScaleMode.custom)
        numberField(
          context,
          custom,
          'Value',
          width: kValueWidth,
          labelled: labelled,
        )
      else
        SizedBox(width: scaledWidth(context, kValueWidth)),
    ],
  );
}

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
        width: 552,
        child: _rows.isEmpty
            ? const Text('No symptom and side effect ratings yet.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'How each rating is scored when ranking the '
                    'configurations. The two with the highest scores are '
                    'shaded, and only configurations rated on every ranked '
                    'rating are ranked. The ranking ignores the notes. These '
                    'targets apply to this session or report only; the '
                    'defaults are in Symptom and side effect ratings.',
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
                          child: Text(_modeLabels[m]!),
                        ),
                    ],
                  ),
                  const Divider(),
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final wide =
                            box.maxWidth - scaledWidth(context, _fixed) >= 140;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (wide) tableHeader(context, 'Rating', _columns),
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final r in _rows)
                                      wide
                                          ? _rowTile(r, theme)
                                          : _wrappedTile(r, theme),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
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
          child: const Text('Save'),
        ),
      ],
    );
  }

  static const _columns = [
    ('Min', kRangeWidth),
    ('Max', kRangeWidth),
    ('Better when', kTargetWidth),
    ('Value', kValueWidth),
  ];

  /// The columns' total width with their gaps, before text scaling.
  static final double _fixed = _columns.fold(0.0, (w, c) => w + 8 + c.$2);

  /// A row on a narrow window: the name, then its labelled fields wrapped.
  Widget _wrappedTile(_Row row, ThemeData theme) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(row.pref.name, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            numberField(context, row.min, 'Min', labelled: true),
            numberField(context, row.max, 'Max', labelled: true),
            TargetFields(
              mode: row.mode,
              custom: row.custom,
              labelled: true,
              onChanged: (m) => setState(() => row.mode = m),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _rowTile(_Row row, ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(row.pref.name, style: theme.textTheme.bodyLarge)),
        const SizedBox(width: 8),
        numberField(context, row.min, '${row.pref.name} minimum'),
        const SizedBox(width: 8),
        numberField(context, row.max, '${row.pref.name} maximum'),
        const SizedBox(width: 8),
        TargetFields(
          mode: row.mode,
          custom: row.custom,
          onChanged: (m) => setState(() => row.mode = m),
        ),
      ],
    ),
  );
}
