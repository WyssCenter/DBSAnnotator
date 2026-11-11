import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart'
    show FileSaveLocation, XTypeGroup, getSaveLocation;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/bids.dart';
import '../core/prefs/user_prefs.dart';

/// Whether a path from the document picker autosaves back to the file the
/// user chose. False on iOS/iPadOS (`UIDocumentPickerViewController`) and
/// Android (file_picker copies into the cache), which hand back a sandbox
/// copy: autosaving to it is still worth doing, but the UI must not imply the
/// original changed.
bool pickedPathAutosavesToOriginal(String? path) =>
    path != null && !Platform.isIOS && !Platform.isAndroid;

/// Shown wherever a sandbox-copy save path is in effect, so "autosaved" is
/// never read as "written back to your file".
const String sandboxCopyNotice =
    'Autosave keeps edits inside the app only. The file you opened is not '
    'updated. Use Export to save your changes.';

/// The final segment of [path], handling both separators. A wrong answer is
/// silent: it feeds `sourceFile`, and reports drop provenance when empty.
String pickedBasename(String path) =>
    path.replaceAll('\\', '/').split('/').last;

/// The filesystem path for a URI handed back by the picker. The scheme may be
/// `file`, `content`, `http(s)`, `data` or `blob` depending on platform, and
/// only `file` can back an autosave, so anything else yields null.
String? pickerUriToPath(Uri? uri) =>
    uri != null && uri.scheme == 'file' ? uri.toFilePath() : null;

/// Read a picked file as text, or null if it could not be read. Null rather
/// than a throw, because every call site names the file in its own message.
Future<String?> readPickedText(PlatformFile picked) async {
  try {
    return utf8.decode(await picked.readAsBytes());
  } catch (_) {
    return null;
  }
}

/// Stands in for app storage under `flutter_test`, which has no platform
/// channel to resolve it. Mirrors `debugPainterFontFamily`.
Directory? debugWorkingDir;

/// Stands in for the file picker's selection, for recorded docs videos.
List<PlatformFile>? debugPickedFiles;

/// Replaces every Save-As dialog with this folder, for recorded docs videos.
Directory? debugSaveDir;

/// In-progress session files, in the app's own storage: always writable on
/// every platform, so autosave never depends on what the picker returned.
Future<Directory> workingDir() async {
  final base = debugWorkingDir ?? await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/work');
  await dir.create(recursive: true);
  return dir;
}

/// Working-copy path for [fileName], suffixed if another session holds it.
Future<String> workingPath(String fileName) async =>
    unusedPath((await workingDir()).path, fileName);

/// Working copies left by a run that never reached an export, newest first.
Future<List<File>> unfinishedWork() async {
  try {
    final files = (await workingDir())
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.tsv'))
        .toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  } catch (_) {
    return const [];
  }
}

/// Drop a working copy and any `.tmp` left by an interrupted write.
Future<void> discardWork(String? path) async {
  if (path == null) return;
  for (final p in [path, '$path.tmp']) {
    try {
      final f = File(p);
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // Left behind it is only offered again; not worth a message.
    }
  }
}

/// Whether Save-As goes through `file_selector`, which returns the chosen path
/// without writing anything. `FilePicker.saveFile` writes its bytes to the path
/// before returning, so it cannot be used where a path must be checked first.
bool get hasDesktopSaveDialog =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// A file a save dialog must not end on, and the refusal to show when it is
/// chosen.
typedef AvoidFile = ({String path, String reason});

/// Thrown when the user picks an [AvoidFile]; [toString] is the reason.
class SameFileException implements Exception {
  SameFileException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Whether [path] is the [avoid] file, spelled any way.
bool isAvoided(String path, AvoidFile? avoid) =>
    avoid != null && _samePath(path, avoid.path);

/// Throws [SameFileException] when [path] is the [avoid] file.
void refuseIfAvoided(String path, AvoidFile? avoid) {
  if (avoid != null && isAvoided(path, avoid)) {
    throw SameFileException(avoid.reason);
  }
}

bool _samePath(String a, String b) {
  String norm(String p) {
    final slashed = p.replaceAll('\\', '/');
    return Platform.isWindows || Platform.isMacOS
        ? slashed.toLowerCase()
        : slashed;
  }

  if (norm(a) == norm(b)) return true;
  try {
    return File(a).existsSync() &&
        File(b).existsSync() &&
        FileSystemEntity.identicalSync(a, b);
  } catch (_) {
    return false;
  }
}

/// Asks whether to replace the file called [fileName]; false means keep it.
typedef ConfirmReplace = Future<bool> Function(String fileName);

/// Whether the desktop Save-As dialog asks before replacing a file. The Linux
/// one (GtkFileChooserNative via file_selector_linux) does not.
bool get dialogConfirmsReplace =>
    debugDialogConfirmsReplace ?? !Platform.isLinux;

/// Stands in for [dialogConfirmsReplace] under `flutter_test`.
bool? debugDialogConfirmsReplace;

/// Asks in a dialog whether to replace [fileName]. False when dismissed or
/// when [context] is gone.
Future<bool> askReplace(BuildContext context, String fileName) async {
  if (!context.mounted) return false;
  final replace = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Replace $fileName?'),
      content: const Text('A file with this name already exists.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
  return replace ?? false;
}

/// Thrown by [chooseSavePath] when the dialog could not be shown.
class SaveDialogUnavailable implements Exception {}

/// Show the desktop Save-As dialog and return the path to write, or null when
/// cancelled or when the user declined to replace an existing file.
///
/// `file_selector` only returns a path. A name typed without [extension] gets
/// it appended here (the Windows dialog does not add it), and that final path
/// was never confirmed by the dialog, so it is checked and confirmed here on
/// every platform. A path as typed is confirmed here only where the dialog does
/// not ask itself ([dialogConfirmsReplace]). Throws [SameFileException] when
/// the path is [avoid], and [SaveDialogUnavailable] when no dialog could open.
Future<String?> chooseSavePath({
  required String suggestedName,
  required String extension,
  required ConfirmReplace confirmReplace,
  AvoidFile? avoid,
  String? initialDirectory,
}) async {
  final FileSaveLocation? chosen;
  try {
    chosen = await getSaveLocation(
      initialDirectory: initialDirectory,
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
      ],
    );
  } catch (_) {
    throw SaveDialogUnavailable();
  }
  if (chosen == null) return null;
  final suffix = '.$extension';
  final typed = chosen.path;
  final path = typed.toLowerCase().endsWith(suffix) ? typed : '$typed$suffix';
  refuseIfAvoided(path, avoid);
  final unconfirmed = path != typed || !dialogConfirmsReplace;
  if (unconfirmed && File(path).existsSync()) {
    if (!await confirmReplace(pickedBasename(path))) return null;
  }
  return path;
}

/// `<dir>/<fileName>`, suffixed `-2`, `-3`, ... if that name is taken.
///
/// The fallbacks show no dialog, so nothing warns about overwriting,
/// and the session stamp is date-only while Patient ID and Run both default
/// to `01`: same patient, same run, same day collide.
String unusedPath(String dir, String fileName) {
  if (!File('$dir/$fileName').existsSync()) return '$dir/$fileName';
  final dot = fileName.lastIndexOf('.');
  final stem = dot < 0 ? fileName : fileName.substring(0, dot);
  final ext = dot < 0 ? '' : fileName.substring(dot);
  for (var n = 2; n < 1000; n++) {
    final candidate = '$dir/$stem-$n$ext';
    if (!File(candidate).existsSync()) return candidate;
  }
  return '$dir/$stem-${DateTime.now().millisecondsSinceEpoch}$ext';
}

/// Where a report's Save-As dialog opens for [subject]: the folder the last
/// report went to, unless that was a patient's `derivatives/sub-*` folder, in
/// which case this patient's own one in [root]. Null when neither exists.
String? reportFolderFor(
  UserPrefs prefs, {
  String? root,
  required String subject,
}) {
  final last = prefs.reportFolder;
  final patientFolder = RegExp(r'[\\/]derivatives[\\/]sub-[^\\/]+$');
  if (last != null &&
      !patientFolder.hasMatch(last) &&
      Directory(last).existsSync()) {
    return last;
  }
  final own = root == null
      ? null
      : '$root/derivatives/sub-${BidsName.label(subject)}';
  return own != null && Directory(own).existsSync() ? own : null;
}

/// Remember the folder of [savedPath] for the next report, in [prefs] and in
/// the stored preferences, changing nothing else there.
Future<void> rememberReportFolder(UserPrefs prefs, String savedPath) async {
  if (savedPath.isEmpty) return;
  final folder = File(savedPath).parent.path;
  prefs.reportFolder = folder;
  final stored = await loadUserPrefs();
  stored.reportFolder = folder;
  await saveUserPrefs(stored);
}
