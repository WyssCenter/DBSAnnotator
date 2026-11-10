import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../core/prefs/user_prefs.dart';

/// Whether a path from the document picker autosaves back to the file the
/// user chose. False on iOS/iPadOS, where `UIDocumentPickerViewController`
/// returns a sandbox copy: autosaving to it is still worth doing, but the UI
/// must not imply the original changed.
bool pickedPathAutosavesToOriginal(String? path) =>
    path != null && !Platform.isIOS;

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

/// Working-copy path for [fileName].
Future<String> workingPath(String fileName) async =>
    '${(await workingDir()).path}/$fileName';

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

/// Ask for the folder a new file is created in, opening at the default BIDS
/// folder. Null when cancelled.
Future<String?> chooseSaveFolder(UserPrefs prefs) async {
  final String? folder;
  try {
    folder =
        debugSaveDir?.path ??
        await FilePicker.getDirectoryPath(
          dialogTitle: 'Choose the folder to save this session in',
          initialDirectory: prefs.startFolder?.path,
        );
  } catch (_) {
    return null;
  }
  return folder;
}

/// Create a new TSV seeded with [header] and report where it went: in
/// [folder] when given, never over an existing file, else where the user
/// chooses. Null if they cancelled.
Future<NewTsvTarget?> createNewTsv({
  required String dialogTitle,
  required String fileName,
  required String header,
  String? folder,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(header));
  if (folder != null) {
    final file = File('$folder/$fileName');
    await file.create(exclusive: true);
    await file.writeAsBytes(bytes, flush: true);
    return (path: file.path, location: file.path, fellBack: false);
  }
  if (debugSaveDir case final dir?) {
    final path = '${dir.path}/$fileName';
    await File(path).writeAsBytes(bytes);
    return (path: path, location: path, fellBack: false);
  }
  try {
    final uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
      mimeType: 'text/tab-separated-values',
      type: FileType.custom,
      allowedExtensions: const ['tsv'],
    );
    if (uri == null) return null; // cancelled
    final path = pickerUriToPath(uri);
    return (path: path, location: path ?? uri.toString(), fellBack: false);
  } catch (_) {
    // No dialog available, typically a Linux box without zenity/kdialog.
    final dir = await getApplicationDocumentsDirectory();
    await Directory(dir.path).create(recursive: true);
    final path = _unusedPath(dir.path, fileName);
    await File(path).writeAsString(header);
    return (path: path, location: path, fellBack: true);
  }
}

/// `<dir>/<fileName>`, suffixed `-2`, `-3`, ... if that name is taken.
///
/// The fallback above shows no dialog, so nothing warns about overwriting,
/// and the session stamp is date-only while Patient ID and Run both default
/// to `01`: same patient, same run, same day collide.
String _unusedPath(String dir, String fileName) {
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
