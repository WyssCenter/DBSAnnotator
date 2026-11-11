/// Pick which sections the exported report contains.
///
/// The desktop equivalent offers bare checkbox labels; each row here carries a
/// line describing what the section includes, so the choice can be made without
/// exporting twice to find out.
library;

import 'package:flutter/material.dart';

import '../report/attestation.dart';
import '../report/longitudinal_sections.dart';
import '../report/report_sections.dart';

/// One choosable section: whatever the caller's enum calls itself, plus the
/// two strings the dialog shows. Generic so the session and longitudinal
/// reports share one dialog rather than one each.
typedef SectionChoice<T> = ({T value, String label, String description});

/// Choose sections for an export. Returns the selection, or null if cancelled.
///
/// [onEditTargets], when given, adds a "Scale targets…" action: the desktop
/// keeps the scale-optimisation table inside its export dialog, and the targets
/// are what the ranking in some of these sections is measured against, so this
/// is the moment the user wants to check them.
Future<Set<T>?> showSectionsDialog<T>(
  BuildContext context,
  String title,
  List<SectionChoice<T>> choices,
  Set<T> selected, {
  Future<void> Function()? onEditTargets,
}) => showDialog<Set<T>>(
  context: context,
  builder: (_) => _SectionsDialog<T>(
    title: title,
    choices: choices,
    selected: selected,
    onEditTargets: onEditTargets,
  ),
);

/// The session report's chooser.
Future<Set<ReportSection>?> showReportSectionsDialog(
  BuildContext context,
  Set<ReportSection> selected, {
  Future<void> Function()? onEditTargets,
}) => showSectionsDialog<ReportSection>(
  context,
  'Session report sections',
  [
    for (final s in ReportSection.values)
      (value: s, label: s.label, description: s.description),
  ],
  selected,
  onEditTargets: onEditTargets,
);

/// The longitudinal report's chooser.
Future<Set<LongitudinalSection>?> showLongitudinalSectionsDialog(
  BuildContext context,
  Set<LongitudinalSection> selected, {
  Future<void> Function()? onEditTargets,
}) => showSectionsDialog<LongitudinalSection>(
  context,
  'Longitudinal report sections',
  [
    for (final s in LongitudinalSection.values)
      (value: s, label: s.label, description: s.description),
  ],
  selected,
  onEditTargets: onEditTargets,
);

class _SectionsDialog<T> extends StatefulWidget {
  const _SectionsDialog({
    required this.title,
    required this.choices,
    required this.selected,
    this.onEditTargets,
  });

  final String title;
  final List<SectionChoice<T>> choices;
  final Set<T> selected;
  final Future<void> Function()? onEditTargets;

  @override
  State<_SectionsDialog<T>> createState() => _SectionsDialogState<T>();
}

class _SectionsDialogState<T> extends State<_SectionsDialog<T>> {
  late final Set<T> _on = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in widget.choices)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  value: _on.contains(c.value),
                  title: Text(c.label),
                  subtitle: Text(
                    c.description,
                    style: theme.textTheme.bodySmall,
                  ),
                  onChanged: (v) => setState(
                    () => v == true ? _on.add(c.value) : _on.remove(c.value),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onEditTargets != null)
          TextButton.icon(
            onPressed: widget.onEditTargets,
            icon: const Icon(Icons.adjust, size: 18),
            label: const Text('Scale targets…'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        // Nothing selected would produce a title page and nothing else, which
        // is never what anyone means.
        FilledButton(
          onPressed: _on.isEmpty ? null : () => Navigator.pop(context, _on),
          child: const Text('Export'),
        ),
      ],
    );
  }
}

/// Ask who recorded the session and, when [rated], who rated the scales, for
/// the report's attestation. Both are optional; an empty one prints as a line
/// to sign on. Returns null if cancelled.
Future<ReportAttestation?> askAttestation(
  BuildContext context, {
  required bool rated,
}) async {
  final recorded = TextEditingController();
  final ratedBy = TextEditingController();
  final out = await showDialog<ReportAttestation>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Attestation'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Printed at the end of the report and not saved anywhere else. '
              'Leave a name empty to sign by hand.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: recorded,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Documented by (optional)',
              ),
            ),
            if (rated) ...[
              const SizedBox(height: 8),
              TextField(
                controller: ratedBy,
                decoration: const InputDecoration(
                  labelText: 'Rated by (optional)',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            recordedBy: recorded.text.trim(),
            ratedBy: ratedBy.text.trim(),
          )),
          child: const Text('Export'),
        ),
      ],
    ),
  );
  recorded.dispose();
  ratedBy.dispose();
  return out;
}
