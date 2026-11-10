/// Leaving a session: whether to keep its recovery copy.
///
/// The working copy is what brings a session back after a crash, so it is
/// only ever deleted when the user says so. Leaving the workflow and closing
/// the desktop window both ask; a crash, or a phone or tablet app being swiped
/// away, asks nothing and keeps it.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

/// Asked before the desktop window closes, set by the open session screen.
/// Returns whether the window may close. With `closingWindow`, messages that
/// would be a snack bar are dialogs, since the window is about to go.
Future<bool> Function({bool closingWindow})? activeSessionGuard;

/// What the leave dialogs are told, from the last autosave's two outcomes.
/// A save still running counts as a failed file write: the file may lack the
/// latest entries.
({bool onlyCopy, bool copyMayBeStale, bool entriesUnsaved}) leaveGuardState({
  required bool workingFailed,
  required bool fileFailed,
  required bool hasSavePath,
  required bool savePathIsSandboxCopy,
  required bool exportedSinceChange,
  required bool hasEntries,
  required bool stillSaving,
}) {
  final onlyCopy =
      !exportedSinceChange &&
      (!hasSavePath || savePathIsSandboxCopy || fileFailed || stillSaving);
  return (
    onlyCopy: onlyCopy,
    copyMayBeStale: workingFailed && hasEntries,
    entriesUnsaved: workingFailed && onlyCopy && hasEntries,
  );
}

/// What the user chose when asked to leave a session.
enum LeaveChoice { keep, discard }

/// Wait for autosaves, including ones queued meanwhile, read through
/// [current]. False when they did not finish within 10 seconds.
Future<bool> waitForSaves(Future<void> Function() current) async {
  var pending = current();
  while (true) {
    try {
      await pending.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return false;
    }
    final next = current();
    if (identical(next, pending)) return true;
    pending = next;
  }
}

/// Ask whether to keep the recovery copy at [workingPath]. Deletes nothing:
/// the caller deletes it on [LeaveChoice.discard] once leaving has
/// really happened. [onlyCopy] is true when no other file holds the session.
/// [copyMayBeStale] is true when the last write of the recovery copy failed.
/// [stillSaving] is true when a save had not finished by the time of asking.
/// [entriesUnsaved] is true when that failure leaves the entries nowhere on
/// disk, which matters only when there is no copy to keep. Returns null when
/// the user cancels.
Future<LeaveChoice?> askLeaveSession(
  BuildContext context,
  String? workingPath, {
  required bool onlyCopy,
  required bool copyMayBeStale,
  required bool entriesUnsaved,
  bool stillSaving = false,
}) async {
  final hasCopy = workingPath != null && File(workingPath).existsSync();
  if (!hasCopy) {
    if (!entriesUnsaved && !stillSaving) return LeaveChoice.keep;
    final leave =
        await askLeaveUnsaved(
          context,
          stillSaving: stillSaving && !entriesUnsaved,
        ) ??
        false;
    return leave ? LeaveChoice.keep : null;
  }
  final keep = await askKeepRecoveryCopy(
    context,
    onlyCopy: onlyCopy,
    copyMayBeStale: copyMayBeStale,
    entriesUnsaved: entriesUnsaved,
    stillSaving: stillSaving,
  );
  if (keep == null) return null;
  return keep ? LeaveChoice.keep : LeaveChoice.discard;
}

/// Offer back a session the app was closed in the middle of. True to reopen,
/// false to discard, null when dismissed, which keeps the copy for next time:
/// it is only deleted on an explicit Discard.
Future<bool?> askReopenUnfinished(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    scrollable: true,
    content: SizedBox(width: 480, child: Text(message)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Discard'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Reopen'),
      ),
    ],
  ),
);

/// True to leave anyway, null to stay. Asked when entries could not be saved,
/// or, with [stillSaving], when a save had not finished.
Future<bool?> askLeaveUnsaved(
  BuildContext context, {
  bool stillSaving = false,
}) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(
      stillSaving ? 'Changes not saved yet' : 'Changes could not be saved',
    ),
    scrollable: true,
    content: SizedBox(
      width: 480,
      child: Text(
        stillSaving
            ? 'A save is still running, so the changes may not be on disk '
                  'yet. They may be lost if you leave, unless you exported or '
                  'shared them.'
            : 'The changes in this session could not be saved to disk and '
                  'will be lost if you leave, unless you exported or shared '
                  'them.',
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Stay'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Leave and lose them'),
      ),
    ],
  ),
);

/// True to keep the recovery copy, false to discard it, null to cancel.
/// [copyMayBeStale] warns that the copy may be missing the latest entries;
/// [entriesUnsaved] says they are missing and nothing else holds them.
Future<bool?> askKeepRecoveryCopy(
  BuildContext context, {
  required bool onlyCopy,
  bool copyMayBeStale = false,
  bool entriesUnsaved = false,
  bool stillSaving = false,
}) {
  final failed = entriesUnsaved
      ? ' The last save failed. This copy is missing the latest changes, '
            'which will be lost if you leave.'
      : stillSaving
      ? ' A save is still running, so the latest changes may not be on disk '
            'yet.'
      : copyMayBeStale
      ? ' The last save failed, so this copy may be missing the latest '
            'changes.'
      : '';
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Keep a recovery copy of this session?'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Text(
          onlyCopy
              ? 'Changes in this session are not saved anywhere else unless you '
                    'exported or shared them. Discarding deletes this copy.$failed'
              : 'The app keeps a copy of this session so it can offer it back '
                    'if the app closes unexpectedly. Keep it to be offered the '
                    'session again next time; discard it if you are done. Your '
                    'saved file is not changed either way.$failed',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(onlyCopy ? 'Delete the only copy' : 'Discard copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Keep copy'),
        ),
      ],
    ),
  );
}
