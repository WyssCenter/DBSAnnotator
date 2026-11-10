import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import 'bids_merge_ui.dart' show canWriteChosenFolder;

/// The import area around [child]: on the desktop it also takes session files,
/// or one BIDS folder, dropped from the file manager.
class ImportDropZone extends StatefulWidget {
  const ImportDropZone({
    super.key,
    required this.onFiles,
    required this.onFolder,
    required this.say,
    required this.child,
  });

  /// Dropped files, by name; a null content is a file that could not be read.
  final void Function(List<({String name, String? content})> files) onFiles;
  final void Function(String folder) onFolder;
  final void Function(String message) say;
  final Widget child;

  @override
  State<ImportDropZone> createState() => _ImportDropZoneState();
}

class _ImportDropZoneState extends State<ImportDropZone> {
  bool _dragging = false;

  Future<void> _dropped(List<String> paths) async {
    final folders = [
      for (final p in paths)
        if (FileSystemEntity.isDirectorySync(p)) p,
    ];
    if (folders.length > 1) widget.say('Drop one BIDS folder at a time.');
    final files = [
      for (final p in paths)
        if (!folders.contains(p))
          (
            name: p.split(RegExp(r'[\\/]')).last,
            content: await File(p)
                .readAsBytes()
                .then<String?>(utf8.decode, onError: (_) => null),
          ),
    ];
    if (files.isNotEmpty) widget.onFiles(files);
    if (folders.isNotEmpty) widget.onFolder(folders.first);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final zone = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _dragging
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: _dragging ? scheme.primary : scheme.outline,
          width: _dragging ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.upload_file_outlined, size: 40, color: scheme.primary),
          const SizedBox(height: 8),
          Text(
            canWriteChosenFolder
                ? 'Drop session files or a BIDS folder here'
                : 'Import session files or a BIDS folder',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (canWriteChosenFolder)
            Text('or choose them', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          widget.child,
        ],
      ),
    );
    if (!canWriteChosenFolder) return zone;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        _dropped([for (final f in d.files) f.path]);
      },
      child: zone,
    );
  }
}
