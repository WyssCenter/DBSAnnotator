import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart'
    show FileSaveLocation, XTypeGroup, getSaveLocation;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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

/// Where a newly created TSV ended up.
typedef NewTsvTarget = ({
  /// Path for autosave to write back to, or null when the picker gave back
  /// something `dart:io` cannot write, as Android's `content://` URIs are.
  /// Recording does not depend on it: see [workingPath].
  String? path,

  String location,

  /// True when no save dialog could be shown and a default directory was used.
  bool fellBack,
});

/// Ask for the folder a new file is created in, opening at the last one,
/// and remember the choice in [prefs]. Null when cancelled.
Future<String?> chooseSaveFolder(UserPrefs prefs) async {
  final String? folder;
  try {
    folder =
        debugSaveDir?.path ??
        await FilePicker.getDirectoryPath(
          dialogTitle: 'Choose the folder to save this session in',
          initialDirectory: prefs.saveFolder,
        );
  } catch (_) {
    return null;
  }
  if (folder != null) {
    prefs.saveFolder = folder;
    await saveUserPrefs(prefs);
  }
  return folder;
}

/// Whether Save-As goes through `file_selector`, which returns the chosen path
/// without writing anything. `FilePicker.saveFile` writes its bytes to the path
/// before returning, so it cannot be used where a path must be checked first.
bool get hasDesktopSaveDialog =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Refusal wording for the file a session or notes screen is saved in.
const String sessionFileReason =
    'that is the file this session is already saved in. Choose another name.';

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
}) async {
  final FileSaveLocation? chosen;
  try {
    chosen = await getSaveLocation(
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

/// Ask the user where to create a new TSV, seed it with [header], and report
/// where it went. Returns null if they cancelled. Creating and seeding are
/// one step, so the file cannot be left without its header.
///
/// Throws [SameFileException] when the choice is [avoid], before anything is
/// written to it. On desktop the path is only chosen by the dialog, and this
/// function writes the header once the path is known to be another file.
Future<NewTsvTarget?> createNewTsv({
  required String dialogTitle,
  required String fileName,
  required String header,
  required ConfirmReplace confirmReplace,
  AvoidFile? avoid,
  String? folder,
}) async {
  final headerBytes = Uint8List.fromList(utf8.encode(header));
  if (folder != null) {
    final file = File('$folder/$fileName');
    refuseIfAvoided(file.path, avoid);
    await file.create(exclusive: true);
    await file.writeAsBytes(headerBytes, flush: true);
    return (path: file.path, location: file.path, fellBack: false);
  }
  if (debugSaveDir case final dir?) {
    final path = '${dir.path}/$fileName';
    refuseIfAvoided(path, avoid);
    await File(path).writeAsBytes(headerBytes);
    return (path: path, location: path, fellBack: false);
  }
  if (hasDesktopSaveDialog) {
    final String? path;
    try {
      path = await chooseSavePath(
        suggestedName: fileName,
        extension: 'tsv',
        confirmReplace: confirmReplace,
        avoid: avoid,
      );
    } on SaveDialogUnavailable {
      return _newTsvInDocuments(fileName, header);
    }
    if (path == null) return null;
    await File(path).writeAsBytes(headerBytes);
    return (path: path, location: path, fellBack: false);
  }
  final Uri? uri;
  try {
    uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: headerBytes,
      mimeType: 'text/tab-separated-values',
      type: FileType.custom,
      allowedExtensions: const ['tsv'],
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
  } catch (_) {
    return _newTsvInDocuments(fileName, header);
  }
  if (uri == null) return null; // cancelled
  final path = pickerUriToPath(uri);
  if (path != null) refuseIfAvoided(path, avoid);
  return (path: path, location: path ?? uri.toString(), fellBack: false);
}

/// The fallback when no save dialog could be shown.
Future<NewTsvTarget> _newTsvInDocuments(String fileName, String header) async {
  final dir = await getApplicationDocumentsDirectory();
  await Directory(dir.path).create(recursive: true);
  final path = unusedPath(dir.path, fileName);
  await File(path).writeAsString(header);
  return (path: path, location: path, fellBack: true);
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
