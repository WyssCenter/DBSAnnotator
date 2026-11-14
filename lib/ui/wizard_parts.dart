import 'package:flutter/material.dart';

import '../app_info.dart' show kNoticeShort;
import '../core/bids.dart';

/// The wizard's fixed bottom bar: Back on the left, the current step's name in
/// the middle, Next on the right. A null callback disables that button.
class StepControls extends StatelessWidget {
  const StepControls({
    super.key,
    this.onBack,
    this.onNext,
    this.onClose,
    required this.label,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;

  /// Shown in place of Next on the last step.
  final VoidCallback? onClose;
  final String label;

  @override
  Widget build(BuildContext context) {
    const size = Size(120, 48);
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(minimumSize: size),
                child: const Text('Back'),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      kNoticeShort,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClose case final close?)
                FilledButton.icon(
                  onPressed: close,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Close'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(180, 56),
                    textStyle: Theme.of(context).textTheme.titleMedium,
                  ),
                )
              else
                FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(minimumSize: size),
                  child: const Text('Next'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The BIDS entries naming a new or opened file.
class BidsEntries {
  BidsEntries(this.defaultTask)
    : task = TextEditingController(text: defaultTask);

  final String defaultTask;
  final subject = TextEditingController();
  final run = TextEditingController(text: '01');
  final session = TextEditingController(
    text: BidsName.sessionStamp(DateTime.now()),
  );
  final TextEditingController task;
  final acquisition = TextEditingController();

  /// The entries sanitised for a path; empty ones fall back to defaults.
  BidsName get name {
    String or(TextEditingController c, String fallback) {
      final label = BidsName.label(c.text.trim());
      return label.isEmpty ? fallback : label;
    }

    return BidsName(
      subject: or(subject, 'unknown'),
      session: or(session, BidsName.sessionStamp(DateTime.now())),
      task: or(task, defaultTask),
      run: BidsName.index(run.text.trim()),
      acquisition: or(acquisition, ''),
    );
  }

  void fill(BidsName bids) {
    subject.text = bids.subject;
    task.text = bids.task.isEmpty ? defaultTask : bids.task;
    run.text = bids.run;
    if (bids.session.isNotEmpty) session.text = bids.session;
    acquisition.text = bids.acquisition;
  }

  void dispose() {
    for (final c in [subject, run, session, task, acquisition]) {
      c.dispose();
    }
  }
}

/// The patient and visit, with the rest of the BIDS file name folded away.
class BidsNameFields extends StatelessWidget {
  const BidsNameFields({super.key, required this.entries, this.subjectError});

  final BidsEntries entries;

  /// Shown on the Patient ID field, such as when Next finds it empty.
  final String? subjectError;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: entries.subject,
              decoration: InputDecoration(
                labelText: 'Patient ID',
                helperText: 'Required',
                errorText: subjectError,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextField(
              controller: entries.session,
              decoration: const InputDecoration(labelText: 'Session ID'),
            ),
          ),
        ],
      ),
      ExpansionTile(
        title: const Text('Research file naming'),
        maintainState: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
        shape: const Border(),
        collapsedShape: const Border(),
        children: [
          Row(
            children: [
              for (final (i, (ctrl, label, flex)) in [
                (entries.task, 'Task ID', 3),
                (entries.acquisition, 'Acquisition ID', 3),
                (entries.run, 'Run ID', 2),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  flex: flex,
                  child: TextField(
                    controller: ctrl,
                    keyboardType: ctrl == entries.run
                        ? TextInputType.number
                        : null,
                    decoration: InputDecoration(
                      labelText: label,
                      hintText: ctrl == entries.acquisition ? 'Optional' : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: Listenable.merge([
              entries.subject,
              entries.session,
              entries.task,
              entries.acquisition,
              entries.run,
            ]),
            builder: (context, _) => Text(
              'File name: ${entries.name.filename}. The parts follow the '
              'BIDS naming convention; Acquisition ID is added only when filled '
              'in.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ],
  );
}

/// Whose session is open, shown above every step after the first. Tapping it
/// returns to the first step.
class SessionStrip extends StatelessWidget {
  const SessionStrip({super.key, required this.parts, required this.onTap});

  final List<String> parts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(parts.join('  ·  '), overflow: TextOverflow.ellipsis),
      ),
    ),
  );
}
