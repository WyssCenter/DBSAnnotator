import 'package:flutter/material.dart';

import '../core/prefs/user_prefs.dart';
import '../report/upload_actions.dart';

/// The report page size, saved into [prefs] when changed.
class PageSizeMenu extends StatelessWidget {
  const PageSizeMenu({super.key, required this.prefs});

  final UserPrefs prefs;

  @override
  Widget build(BuildContext context) => DropdownMenu<String>(
    key: ObjectKey(prefs),
    initialSelection: prefs.reportPageSize ?? kDefaultReportPageSize,
    label: const Text('Page size'),
    width: 160,
    requestFocusOnTap: false,
    dropdownMenuEntries: [
      for (final size in kReportPageSizes)
        DropdownMenuEntry(
          value: size,
          label: size == 'letter' ? 'US Letter' : 'A4',
        ),
    ],
    onSelected: (size) {
      if (size == null) return;
      prefs.reportPageSize = size;
      saveUserPrefs(prefs);
    },
  );
}

/// One button on an action row: what it says, what it does, and why it is off
/// when it is. A per-button reason exists because the two ways of merging do
/// not have the same platform support.
typedef ReportActionButton = ({
  String label,
  Future<void> Function() run,
  String? unavailable,
});

/// One offered action: what it makes, and either the buttons to make it or the
/// reason it cannot be made.
class ReportActionRow extends StatelessWidget {
  const ReportActionRow({
    super.key,
    required this.action,
    required this.reason,
    required this.buttons,
  });

  final ReportAction action;

  /// Null when the upload supports this action at all.
  final String? reason;
  final List<ReportActionButton> buttons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = reason == null;
    final ink = enabled ? null : theme.disabledColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  action.label,
                  style: theme.textTheme.titleSmall?.copyWith(color: ink),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline, size: 18),
                tooltip: 'About this export',
                visualDensity: VisualDensity.compact,
                onPressed: () => _showInfo(context, action),
              ),
            ],
          ),
          Text(
            reason ?? action.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: enabled ? theme.colorScheme.onSurfaceVariant : ink,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final button in buttons)
                Tooltip(
                  message: button.unavailable ?? '',
                  child: OutlinedButton(
                    onPressed: enabled && button.unavailable == null
                        ? button.run
                        : null,
                    child: Text(button.label),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How [action] exports, what it needs and what it creates.
Future<void> _showInfo(BuildContext context, ReportAction action) {
  final theme = Theme.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(action.label),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (heading, text) in [
                ('How it is exported', action.how),
                ('What it needs', action.needs),
                ('What it creates', action.creates),
              ]) ...[
                Text(heading, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(text, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
