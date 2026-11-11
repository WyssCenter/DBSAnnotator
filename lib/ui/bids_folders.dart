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

/// Edit the BIDS folders in [prefs]: choose the default, add one, or drop
/// one from the list. Dropping a folder never deletes it or its files.
Future<void> showBidsFoldersDialog(
  BuildContext context,
  UserPrefs prefs,
) => showDialog<void>(
  context: context,
  builder: (context) => StatefulBuilder(
    builder: (context, setState) {
      final folders = prefs.bidsFolders ?? const <BidsFolder>[];
      Future<void> save() async {
        setState(() {});
        await saveUserPrefs(prefs);
      }

      return AlertDialog(
        title: const Text('Storage folders (BIDS)'),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (folders.isEmpty)
                const Text(
                  'No BIDS folder yet. Add one, for example one per cohort.',
                ),
              RadioGroup<String>(
                groupValue: prefs.startFolder?.name,
                onChanged: (name) {
                  prefs.defaultBidsFolder = name;
                  save();
                },
                child: Column(
                  children: [
                    for (final f in folders)
                      ListTile(
                        leading: Radio<String>(value: f.name),
                        title: Text(f.name),
                        subtitle: Text(f.path),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove from the list',
                          onPressed: () {
                            prefs.bidsFolders = [
                              for (final o in folders)
                                if (o.name != f.name) o,
                            ];
                            if (prefs.defaultBidsFolder == f.name) {
                              prefs.defaultBidsFolder = null;
                            }
                            save();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add'),
            onPressed: () async {
              await addBidsFolder(context, prefs);
              setState(() {});
            },
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  ),
);

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
