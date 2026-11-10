/// Adding the BIDS folders sessions are saved in.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/prefs/user_prefs.dart';
import 'bids_merge_ui.dart' show canWriteChosenFolder;

/// Ask for a name and, on the desktop, a location, then add the folder to
/// [prefs] and save them. On a tablet the folder lives in the app's storage.
/// Null when cancelled.
Future<BidsFolder?> addBidsFolder(BuildContext context, UserPrefs prefs) async {
  final String path;
  if (canWriteChosenFolder) {
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose or create the BIDS folder',
    );
    if (picked == null) return null;
    path = picked;
  } else {
    path = '';
  }
  if (!context.mounted) return null;
  final suggested = path.isEmpty
      ? ''
      : path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).last;
  final name = await _askName(context, suggested);
  if (name == null || name.isEmpty) return null;
  final folder = (
    name: name,
    path: path.isEmpty
        ? '${(await getApplicationDocumentsDirectory()).path}/bids/$name'
        : path,
  );
  await Directory(folder.path).create(recursive: true);
  prefs.bidsFolders = [
    for (final f in prefs.bidsFolders ?? const <BidsFolder>[])
      if (f.name != name) f,
    folder,
  ];
  prefs.defaultBidsFolder ??= name;
  await saveUserPrefs(prefs);
  return folder;
}

Future<String?> _askName(BuildContext context, String suggested) {
  final ctrl = TextEditingController(text: suggested);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Name this BIDS folder'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Name, for example the cohort',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
