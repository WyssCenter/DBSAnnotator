import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'save_target.dart';

/// Global bounds of the widget at [context], for [shareOrSaveFile]'s `origin`.
///
/// Pass the export button's `currentContext` before the first await; after
/// one the widget may be gone. Null when it is not laid out.
Rect? shareOriginFrom(BuildContext? context) {
  final box = context?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// How an export ended. [saved]: written to disk. [handedOff]: the share sheet
/// reported success, which does not prove the target app kept the file (iOS
/// counts "Copy" as success). [notDelivered]: cancelled, dismissed or failed.
enum ExportOutcome { saved, handedOff, notDelivered }

bool get _isMobile => Platform.isAndroid || Platform.isIOS;

/// MIME type for the file kinds we export. Android's `MimeTypeMap` does not
/// know `.docx`, and without an explicit type some target apps refuse it.
String? mimeTypeFor(String filename) {
  final ext = _ext(filename).toLowerCase();
  return switch (ext) {
    '.pdf' => 'application/pdf',
    '.docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.tsv' => 'text/tab-separated-values',
    '.zip' => 'application/zip',
    _ => null,
  };
}

/// A non-empty popover anchor for the iPad share sheet. share_plus's iOS
/// plugin throws when a popover is required and the origin is null or empty
/// (`FPPSharePlusPlugin.m`), sending the export into the app container.
Rect safeOrigin(Rect? origin, Size screen) {
  if (origin != null && !origin.isEmpty) return origin;
  return Rect.fromCenter(
    center: Offset(screen.width / 2, screen.height / 2),
    width: 1,
    height: 1,
  );
}

/// Deliver [file] to the user: the OS share sheet on mobile, or a saved copy
/// on desktop, where `share_plus` has none. Never throws, and always reports
/// the outcome via [messenger], so an export cannot fail silently.
///
/// [messenger] must be resolved before the first await, so the snackbar is
/// safe across the async gap. [origin] anchors the iPadOS share popover and
/// [screen] supplies its fallback.
Future<ExportOutcome> shareOrSaveFile(
  ScaffoldMessengerState messenger,
  File file,
  String filename, {
  Rect? origin,
  Size screen = const Size(768, 1024),
}) async {
  if (_isMobile) {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: mimeTypeFor(filename))],
          subject: filename,
          sharePositionOrigin: safeOrigin(origin, screen),
        ),
      );
      // Confirm on mobile too, so a dismissed sheet is distinguishable.
      if (result.status != ShareResultStatus.unavailable) {
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(
              result.status == ShareResultStatus.success
                  ? 'Shared $filename'
                  : 'Not shared: $filename',
            ),
          ),
        );
        return result.status == ShareResultStatus.success
            ? ExportOutcome.handedOff
            : ExportOutcome.notDelivered;
      }
    } catch (e) {
      debugPrint('Share sheet unavailable: $e');
      // Fall through to a disk save.
    }
  }
  final saved = await _saveToDisk(file, filename);
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(
        saved == null
            ? 'Not saved: $filename'
            : saved.isEmpty
            ? 'Saved $filename'
            : 'Saved to $saved',
      ),
    ),
  );
  return saved != null ? ExportOutcome.saved : ExportOutcome.notDelivered;
}

/// An export's bytes, plus an optional warning to show once it is delivered.
typedef ExportPayload = ({List<int> bytes, String? warning});

/// Build a file and deliver it, reporting every failure; see
/// [shareOrSaveFile]. The payload's warning is shown whatever the outcome.
///
/// The messenger, screen size and share anchor are captured before the first
/// await, because a menu item is unmounted by the time the iPad share sheet
/// needs its anchor. So [anchor] should key the enclosing button, not a menu
/// item that is about to disappear.
Future<ExportOutcome> exportFile(
  BuildContext context, {
  required String filename,
  required Future<ExportPayload> Function() build,
  GlobalKey? anchor,
  String failureLabel = 'Export failed',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final screen = MediaQuery.sizeOf(context);
  final origin = shareOriginFrom(anchor?.currentContext);
  Directory? dir;
  try {
    final payload = await build();
    final root = Directory(
      '${(await getApplicationCacheDirectory()).path}/dbs_annotator_exports',
    );
    await root.create(recursive: true);
    await _sweepStaleExports(root);
    dir = await root.createTemp('export-');
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(payload.bytes);
    final outcome = await shareOrSaveFile(
      messenger,
      file,
      filename,
      origin: origin,
      screen: screen,
    );
    final warning = payload.warning;
    if (warning != null) {
      messenger.showSnackBar(
        SnackBar(duration: const Duration(seconds: 6), content: Text(warning)),
      );
    }
    return outcome;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$failureLabel: $e')));
    return ExportOutcome.notDelivered;
  } finally {
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // Left for the next export's sweep, which removes it after an hour.
      }
    }
  }
}

/// Remove export folders an earlier run left behind in [root], which only this
/// app writes to. Best effort.
Future<void> _sweepStaleExports(Directory root) async {
  final cutoff = DateTime.now().subtract(const Duration(hours: 1));
  try {
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      if (!pickedBasename(entry.path).startsWith('export-')) continue;
      try {
        if ((await entry.stat()).modified.isBefore(cutoff)) {
          await entry.delete(recursive: true);
        }
      } catch (_) {
        // In use or already gone; a later sweep retries.
      }
    }
  } catch (_) {
    // The exports directory could not be listed.
  }
}

/// Save [file] to a user-visible location: a native Save-As dialog first, then
/// the first writable well-known directory. Null when the user cancelled the
/// dialog or nothing was writable, and empty when the dialog saved it
/// somewhere with no file path, as Android's document picker does. Never
/// throws.
Future<String?> _saveToDisk(File file, String filename) async {
  if (debugSaveDir case final dir?) {
    return (await file.copy('${dir.path}/$filename')).path;
  }
  // 1) Native Save-As dialog. A null Uri is a cancel, so nothing is written
  //    elsewhere. Any other result means the bytes were written, even when
  //    the Uri is not a `file` one (Android's document picker), so a second
  //    copy would only duplicate it.
  try {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save $filename',
      fileName: filename,
      bytes: await file.readAsBytes(),
      mimeType: mimeTypeFor(filename) ?? 'application/octet-stream',
    );
    if (uri == null) return null;
    return pickerUriToPath(uri) ?? '';
  } catch (_) {
    // No dialog available; auto-save below.
  }

  // 2) First writable well-known directory. Application-support resolves even
  //    on a minimal Linux box where XDG Downloads/Documents are unset.
  final getters = <Future<Directory?> Function()>[
    getDownloadsDirectory,
    getApplicationDocumentsDirectory,
    getApplicationSupportDirectory,
  ];
  for (final getDir in getters) {
    try {
      final dir = await getDir();
      if (dir == null) continue;
      await Directory(dir.path).create(recursive: true);
      final dest = '${dir.path}/$filename';
      await file.copy(dest);
      return dest;
    } catch (_) {
      // Unwritable; try the next location.
    }
  }

  return null;
}

/// The extension of [filename] including the dot ('' when there is none).
String _ext(String filename) {
  final i = filename.lastIndexOf('.');
  return i < 0 ? '' : filename.substring(i);
}
